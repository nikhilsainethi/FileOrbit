#!/usr/bin/env python3
"""Verify an extracted FileOrbit release using only its packaged CLI and helpers.

Usage: python3 scripts/verify-package.py /path/to/FileOrbit-macOS-arm64.zip
All fixtures and outputs are temporary. Exit 0 means full coverage passed;
exit 3 means native checks passed but LibreOffice was unavailable; exit 1 is a failure.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import struct
import subprocess
import sys
import tempfile
import time


class VerificationError(RuntimeError):
    pass


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def execute(arguments: list[str], environment: dict[str, str], timeout: int = 180) -> str:
    process = subprocess.Popen(arguments, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               text=True, env=environment, start_new_session=True)
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate()
        raise VerificationError(f"Timed out after {timeout}s: {Path(arguments[0]).name}") from None
    if process.returncode:
        raise VerificationError(f"{Path(arguments[0]).name} exited {process.returncode}: "
                                f"{(stderr or stdout).strip()[-2000:]}")
    return stdout


def png_dimensions(path: Path) -> tuple[int, int]:
    with path.open("rb") as handle:
        header = handle.read(24)
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise VerificationError("PNG output has no valid IHDR header")
    return struct.unpack(">II", header[16:24])


def jpeg_dimensions(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    if not data.startswith(b"\xff\xd8"):
        raise VerificationError("JPEG output has no valid start marker")
    cursor = 2
    frame_markers = {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}
    while cursor < len(data):
        if data[cursor] != 0xFF:
            break
        while cursor < len(data) and data[cursor] == 0xFF:
            cursor += 1
        if cursor >= len(data):
            break
        marker = data[cursor]
        cursor += 1
        if marker in {0xD8, 0x01}:
            continue
        if marker in {0xD9, 0xDA} or cursor + 2 > len(data):
            break
        size = struct.unpack(">H", data[cursor:cursor + 2])[0]
        if size < 2 or cursor + size > len(data):
            break
        if marker in frame_markers and size >= 8:
            height, width = struct.unpack(">HH", data[cursor + 3:cursor + 7])
            return width, height
        cursor += size
    raise VerificationError("JPEG output has no readable frame dimensions")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    archive = args.archive.resolve(strict=True)
    environment = dict(os.environ)
    # Ensure the package, rather than development-shell overrides, is exercised.
    for name in ("FILEORBIT_QPDF", "FILEORBIT_RESVG", "FILEORBIT_SOFFICE"):
        environment.pop(name, None)
    checks: list[str] = []
    skipped: list[str] = []
    measurements: dict[str, object] = {}
    started = time.monotonic()

    def passed(name: str) -> None:
        checks.append(name)

    try:
        with tempfile.TemporaryDirectory(prefix="fileorbit-package-check-") as temporary:
            root = Path(temporary)
            execute(["/usr/bin/ditto", "-x", "-k", str(archive), str(root)], environment, 60)
            app = root / "FileOrbit.app"
            gui = app / "Contents/MacOS/FileOrbit"
            cli = app / "Contents/MacOS/fileorbit-cli"
            if not gui.is_file() or not cli.is_file() or os.path.samefile(gui, cli):
                raise VerificationError("The GUI and CLI must be distinct packaged executables")
            passed("distinct_gui_and_cli")
            for binary in (gui, cli):
                data = binary.read_bytes()
                if b"/Users/" in data or b"/home/" in data:
                    raise VerificationError("A packaged executable contains local build paths")
            passed("no_local_build_paths")
            resources = app / "Contents/Resources"
            licenses = resources / "Licenses"
            required_notices = [resources / "FileOrbit-LICENSE.txt", resources / "THIRD_PARTY_NOTICES.md"]
            required_notices += [licenses / name for name in (
                "qpdf/LICENSE.txt", "qpdf/NOTICE.md", "openssl/LICENSE.txt", "openssl/AUTHORS.md",
                "libjpeg-turbo/LICENSE.md", "libjpeg-turbo/README.ijg", "rust/LICENSE-MIT",
                "rust/LICENSE-APACHE", "rust/COPYRIGHT-library.html", "unicode/LICENSE.txt")]
            if any(not path.is_file() or not path.stat().st_size for path in required_notices):
                raise VerificationError("A required bundled license or attribution is missing")
            manifest = json.loads((licenses / "resvg-dependencies.json").read_text(encoding="utf-8"))
            packages = manifest.get("packages", [])
            if not packages:
                raise VerificationError("The resvg dependency notice inventory is empty")
            for package in packages:
                entries = package.get("license_files", [])
                if not entries:
                    raise VerificationError("A dependency has no included license text")
                for entry in entries:
                    notice = (licenses / entry["path"]).resolve()
                    if not notice.is_relative_to(licenses.resolve()) or not notice.is_file() or digest(notice) != entry["sha256"]:
                        raise VerificationError("A dependency license is missing or differs from its recorded hash")
            passed("bundled_license_inventory")
            execute(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], environment, 30)
            passed("extracted_code_signature")
            engines = json.loads(execute([str(cli), "--engines"], environment, 10))
            passed("cli_exits_and_returns_json")
            for name in ("qpdf", "resvg"):
                path = Path(engines.get(name, "missing"))
                expected = (app / ("Contents/Helpers/qpdf/bin/qpdf" if name == "qpdf" else "Contents/Helpers/resvg"))
                if not path.is_file() or not expected.is_file() or path.resolve() != expected.resolve():
                    raise VerificationError(f"The CLI did not discover its bundled {name} helper")
                execute([str(path), "--version"], environment, 10)
                passed(f"bundled_{name}_runs")
            qpdf = Path(engines["qpdf"])
            libreoffice = Path(engines.get("libreoffice", "missing"))
            has_office = libreoffice.is_file() and os.access(libreoffice, os.X_OK)
            measurements["libreoffice_available"] = has_office
            fixtures = root / "Fixtures with spaces Ω"
            fixtures.mkdir()

            def convert(source: Path, option: str, value: str) -> tuple[Path, dict[str, object]]:
                before = digest(source)
                record = json.loads(execute([str(cli), str(source), option, value], environment))
                outputs = record.get("outputs", [])
                if len(outputs) != 1:
                    raise VerificationError(f"Expected one output from {source.name}: {outputs}")
                output = Path(outputs[0])
                if not output.is_file() or not output.stat().st_size or not output.resolve().is_relative_to(fixtures.resolve()):
                    raise VerificationError("Output is missing, empty, or outside the test directory")
                if digest(source) != before:
                    raise VerificationError(f"Source changed during processing: {source.name}")
                if record.get("inputBytes") != source.stat().st_size or record.get("outputBytes") != output.stat().st_size:
                    raise VerificationError("Reported sizes do not match the actual files")
                return output, record

            svg = fixtures / "Orbit sample Ω.svg"
            svg.write_text('''<svg xmlns="http://www.w3.org/2000/svg" width="2048" height="2048" viewBox="0 0 2048 2048">
<defs><linearGradient id="g" x2="1" y2="1"><stop stop-color="#11344a"/><stop offset=".37" stop-color="#48c9ae"/><stop offset=".73" stop-color="#f2ba71"/><stop offset="1" stop-color="#514b81"/></linearGradient></defs>
<rect width="2048" height="2048" fill="url(#g)"/>
<circle cx="840" cy="920" r="530" fill="#eeeeee" fill-opacity=".22"/>
<circle cx="1170" cy="1030" r="590" fill="none" stroke="#def9ef" stroke-width="17"/>
<path d="M120 1650 Q700 100 1810 1260" fill="none" stroke="#e7a46d" stroke-width="43"/>
</svg>''', encoding="utf-8")
            png, _ = convert(svg, "--to", "png")
            if png_dimensions(png) != (2048, 2048):
                raise VerificationError("SVG raster output dimensions were not preserved")
            passed("svg_to_png_and_source_integrity")
            capabilities = json.loads(execute([str(cli), "--capabilities", str(png)], environment, 10))
            available = {action["id"] for action in capabilities.get("actions", [])}
            first_jpeg = None
            pdf = None
            for format_name in ("jpg", "heic", "tiff", "pdf"):
                if f"convert-{format_name}" not in available:
                    skipped.append(f"native_encoder_{format_name}_unavailable")
                    continue
                output, _ = convert(png, "--to", format_name)
                passed(f"png_to_{format_name}")
                if format_name == "jpg":
                    first_jpeg = output
                if format_name == "pdf":
                    pdf = output
            if first_jpeg is None or pdf is None:
                raise VerificationError("Required native JPEG/PDF actions were missing")
            first_hash = digest(first_jpeg)
            second_jpeg, _ = convert(png, "--to", "jpg")
            if second_jpeg == first_jpeg or digest(first_jpeg) != first_hash:
                raise VerificationError("A filename collision overwrote the first result")
            passed("collision_preserves_original_and_first_result")
            compressed_image, record = convert(first_jpeg, "--compress", "small")
            if compressed_image.stat().st_size >= first_jpeg.stat().st_size or max(jpeg_dimensions(compressed_image)) > 1600:
                raise VerificationError("Image compression did not reduce both size and dimensions")
            measurements["image_compression_bytes"] = {"before": record["inputBytes"], "after": record["outputBytes"]}
            passed("image_compression_small")
            uncompressed_pdf = fixtures / "Uncompressed verification.pdf"
            execute([str(qpdf), "--stream-data=uncompress", "--object-streams=disable", str(pdf), str(uncompressed_pdf)], environment, 60)
            before_pages = execute([str(qpdf), "--show-npages", str(uncompressed_pdf)], environment, 10).strip()
            compressed_pdf, pdf_record = convert(uncompressed_pdf, "--compress", "gentle")
            after_pages = execute([str(qpdf), "--show-npages", str(compressed_pdf)], environment, 10).strip()
            if before_pages != after_pages or compressed_pdf.stat().st_size >= uncompressed_pdf.stat().st_size:
                raise VerificationError("PDF compression changed page count or did not shrink")
            execute([str(qpdf), "--check", str(compressed_pdf)], environment, 30)
            measurements["pdf_compression_bytes"] = {"before": pdf_record["inputBytes"], "after": pdf_record["outputBytes"]}
            passed("pdf_compression_preserves_page_count")
            if has_office:
                text = fixtures / "Office verification Ω.txt"
                sentinel = "FileOrbit packaged Office round-trip 73915"
                text.write_text(sentinel + "\nUnicode check: café Ω.\n", encoding="utf-8")
                office_pdf, _ = convert(text, "--to", "pdf")
                if execute([str(qpdf), "--show-npages", str(office_pdf)], environment, 10).strip() != "1":
                    raise VerificationError("Office text fixture should produce one PDF page")
                passed("txt_to_pdf_with_libreoffice")
                docx, _ = convert(text, "--to", "docx")
                passed("txt_to_docx_with_libreoffice")
                roundtrip, _ = convert(docx, "--to", "txt")
                if sentinel not in roundtrip.read_text(encoding="utf-8"):
                    raise VerificationError("DOCX round-trip lost the sentinel text")
                passed("docx_to_txt_sentinel_preserved")
            else:
                skipped.append("LibreOffice missing: TXT/PDF/DOCX round-trip not exercised")
            leftovers = [path.name for path in fixtures.iterdir() if path.name.startswith(".fileorbit-")]
            if leftovers:
                raise VerificationError(f"Temporary processing folders were left behind: {leftovers}")
            passed("temporary_processing_folders_removed")
            # Temp-only tests leave source documents, prior results and the installed app untouched.
            result = {"status": "passed" if not skipped else "partial", "archive": str(archive),
                      "checks_passed": len(checks), "checks": checks, "skipped": skipped,
                      "measurements": measurements, "seconds": round(time.monotonic() - started, 3)}
            print(json.dumps(result, indent=2, ensure_ascii=False))
            return 0 if not skipped else 3
    except (VerificationError, OSError, ValueError, KeyError, TypeError) as error:
        print(json.dumps({"status": "failed", "archive": str(archive), "checks_passed": len(checks),
                          "checks": checks, "error": str(error)}, indent=2), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
