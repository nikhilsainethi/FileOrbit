#!/usr/bin/env python3
"""Verify an extracted FileOrbit release using only its packaged CLI and helpers.

Usage: python3 scripts/verify-package.py /path/to/FileOrbit-macOS-arm64.zip
Production and isolated FileOrbit Preview archives are accepted.
All fixtures and outputs are temporary. Exit 0 means full coverage passed;
exit 3 means native checks passed but LibreOffice was unavailable; exit 1 is a failure.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import signal
import struct
import subprocess
import sys
import tempfile
import time
import zlib


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



def webp_dimensions(path: Path) -> tuple[int, int, bool]:
    data = path.read_bytes()
    if len(data) < 30 or data[:4] != b"RIFF" or data[8:12] != b"WEBP" or struct.unpack("<I", data[4:8])[0] + 8 != len(data):
        raise VerificationError("WebP output has an invalid RIFF container")
    cursor = 12
    while cursor + 8 <= len(data):
        kind, size = data[cursor:cursor + 4], struct.unpack("<I", data[cursor + 4:cursor + 8])[0]
        payload = data[cursor + 8:cursor + 8 + size]
        if len(payload) != size:
            raise VerificationError("WebP output contains a truncated chunk")
        if kind == b"VP8X" and size >= 10:
            return int.from_bytes(payload[4:7], "little") + 1, int.from_bytes(payload[7:10], "little") + 1, bool(payload[0] & 0x10)
        if kind == b"VP8L" and size >= 5 and payload[0] == 0x2F:
            bits = int.from_bytes(payload[1:5], "little")
            return (bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1, bool(bits & (1 << 28))
        if kind == b"VP8 " and size >= 10 and payload[3:6] == b"\x9d\x01\x2a":
            return int.from_bytes(payload[6:8], "little") & 0x3FFF, int.from_bytes(payload[8:10], "little") & 0x3FFF, False
        cursor += 8 + size + size % 2
    raise VerificationError("WebP output has no readable image dimensions")


def png_chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def make_metadata_png(path: Path) -> None:
    # Black/white blocks remain deterministic across platform color profiles.
    width, height = 64, 48
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            value = 255 if ((x // 8) + (y // 8)) % 2 else 0
            alpha = 0 if x < 16 else 255
            rows.extend((value if alpha else 0,) * 3 + (alpha,))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
                     + png_chunk(b"tEXt", b"Author\0PRIVATE IMAGE AUTHOR 6817")
                     + png_chunk(b"IDAT", zlib.compress(rows)) + png_chunk(b"IEND", b""))


def png_rgba(path: Path) -> tuple[int, int, bytes]:
    """Decode the bounded 8-bit PNG test outputs without third-party Python modules."""
    data = path.read_bytes()
    width, height = png_dimensions(path)
    if width * height > 16_000_000:
        raise VerificationError("PNG fixture unexpectedly exceeds its verification pixel budget")
    cursor, compressed, header = 8, bytearray(), None
    while cursor + 12 <= len(data):
        size = int.from_bytes(data[cursor:cursor + 4], "big")
        kind = data[cursor + 4:cursor + 8]
        payload = data[cursor + 8:cursor + 8 + size]
        if len(payload) != size or cursor + size + 12 > len(data):
            raise VerificationError("PNG output contains a truncated chunk")
        expected = int.from_bytes(data[cursor + 8 + size:cursor + 12 + size], "big")
        if zlib.crc32(kind + payload) & 0xFFFFFFFF != expected:
            raise VerificationError("PNG output failed its chunk checksum")
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", payload)
        elif kind == b"IDAT":
            compressed.extend(payload)
        cursor += size + 12
    if header is None or header[2] != 8 or header[3] not in (0, 2, 4, 6) or any(header[4:]):
        raise VerificationError("PNG test output uses an unsupported pixel layout")
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[header[3]]
    stride = width * channels
    pixels = zlib.decompress(compressed)
    if len(pixels) != (stride + 1) * height:
        raise VerificationError("PNG decompressed image length does not match dimensions")
    previous, result = bytearray(stride), bytearray()
    for row_index in range(height):
        offset = row_index * (stride + 1)
        filter_type, row = pixels[offset], bytearray(pixels[offset + 1:offset + stride + 1])
        if filter_type > 4:
            raise VerificationError("PNG contains an unknown row filter")
        for i in range(stride):
            left = row[i - channels] if i >= channels else 0
            above = previous[i]
            upper_left = previous[i - channels] if i >= channels else 0
            if filter_type == 1:
                predictor = left
            elif filter_type == 2:
                predictor = above
            elif filter_type == 3:
                predictor = (left + above) // 2
            elif filter_type == 4:
                prediction = left + above - upper_left
                distances = (abs(prediction - left), abs(prediction - above), abs(prediction - upper_left))
                predictor = (left, above, upper_left)[distances.index(min(distances))]
            else:
                predictor = 0
            row[i] = (row[i] + predictor) & 255
        for i in range(0, stride, channels):
            if channels == 4:
                result.extend(row[i:i + 4])
            elif channels == 3:
                result.extend(row[i:i + 3]); result.append(255)
            elif channels == 2:
                result.extend((row[i], row[i], row[i], row[i + 1]))
            else:
                result.extend((row[i], row[i], row[i], 255))
        previous = row
    return width, height, bytes(result)


def make_document_pdf(path: Path) -> None:
    """Two differently sized pages with removable metadata and separate text regions."""
    first = b"BT /F1 24 Tf 72 680 Td (SECRET REGION 73915) Tj 0 -200 Td (PUBLIC CONTENT SURVIVES 24680) Tj ET\n"
    second = b"BT /F1 24 Tf 72 500 Td (SECOND PAGE PUBLIC 73915) Tj ET\n"
    metadata = b'<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description xmlns:dc="http://purl.org/dc/elements/1.1/" dc:title="PRIVATE XMP 6817"/></rdf:RDF></x:xmpmeta>'
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R /Metadata 9 0 R >>",
        b"<< /Type /Pages /Kids [4 0 R 6 0 R] /Count 2 >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents 5 0 R >>",
        b"<< /Length %d >>\nstream\n" % len(first) + first + b"endstream",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 612] /Resources << /Font << /F1 3 0 R >> >> /Contents 7 0 R >>",
        b"<< /Length %d >>\nstream\n" % len(second) + second + b"endstream",
        b"<< /Author (PRIVATE AUTHOR 6817) /Title (PRIVATE TITLE 6817) >>",
        b"<< /Type /Metadata /Subtype /XML /Length %d >>\nstream\n" % len(metadata) + metadata + b"\nendstream",
    ]
    output, offsets = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n"), [0]
    for number, obj in enumerate(objects, 1):
        offsets.append(len(output))
        output.extend(f"{number} 0 obj\n".encode() + obj + b"\nendobj\n")
    xref = len(output)
    output.extend(f"xref\n0 {len(offsets)}\n0000000000 65535 f \n".encode())
    for offset in offsets[1:]:
        output.extend(f"{offset:010d} 00000 n \n".encode())
    output.extend(f"trailer\n<< /Size {len(offsets)} /Root 1 0 R /Info 8 0 R /ID [<00112233445566778899aabbccddeeff> <ffeeddccbbaa99887766554433221100>] >>\nstartxref\n{xref}\n%%EOF\n".encode())
    path.write_bytes(output)


def normalized_text(text: str) -> str:
    return " ".join(re.findall(r"[A-Z0-9]+", text.upper()))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    archive = args.archive.resolve(strict=True)
    environment = dict(os.environ)
    # Ensure the package, rather than development-shell overrides, is exercised.
    for name in ("FILEORBIT_QPDF", "FILEORBIT_RESVG", "FILEORBIT_SOFFICE", "FILEORBIT_CWEBP"):
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
            candidates = [root / name for name in ("FileOrbit.app", "FileOrbit Preview.app") if (root / name).is_dir()]
            if len(candidates) != 1:
                raise VerificationError("Archive must contain exactly one FileOrbit.app or FileOrbit Preview.app")
            app = candidates[0]
            measurements["application_name"] = app.name
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
            webp_notices = {
                "webp/libwebp/COPYING": "5aec868f669e384a22372a4e8a1a6cd7d44c64cd451f960ca69cc170d1e13acf",
                "webp/libwebp/PATENTS": "cc3273e0694ea5896145e0677699b53471b03ea43021ddc50e7923fbb9f5023c",
                "webp/libwebp/AUTHORS": "f251be89fd442bd9d701360730aea163cc8e2076ff03528f59267dc2c4f8b60a",
                "webp/libpng/LICENSE": "bdb0a645ea18c60507d0368379b1ac5474b92255fcc2d115e07486a7672ba526",
            }
            for relative, expected_hash in webp_notices.items():
                notice = licenses / relative
                if not notice.is_file() or digest(notice) != expected_hash:
                    raise VerificationError(f"The pinned WebP dependency notice is missing or altered: {relative}")
            passed("bundled_license_inventory")
            execute(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], environment, 30)
            passed("extracted_code_signature")
            engines = json.loads(execute([str(cli), "--engines"], environment, 10))
            passed("cli_exits_and_returns_json")
            for name in ("qpdf", "resvg", "cwebp"):
                path = Path(engines.get(name, "missing"))
                expected = app / {"qpdf": "Contents/Helpers/qpdf/bin/qpdf", "resvg": "Contents/Helpers/resvg", "cwebp": "Contents/Helpers/cwebp"}[name]
                if not path.is_file() or not expected.is_file() or path.resolve() != expected.resolve():
                    raise VerificationError(f"The CLI did not discover its bundled {name} helper")
                version = execute([str(path), "-version" if name == "cwebp" else "--version"], environment, 10)
                if name == "cwebp":
                    if version.splitlines()[0] != "1.6.0":
                        raise VerificationError("Bundled cwebp does not match pinned version 1.6.0")
                    libraries = [line.strip().split(" (", 1)[0] for line in execute(["/usr/bin/otool", "-L", str(path)], environment, 10).splitlines()[1:]]
                    if not libraries or any(not library.startswith(("/usr/lib/", "/System/Library/")) for library in libraries):
                        raise VerificationError("Bundled cwebp depends on a non-system runtime library")
                    measurements["cwebp_runtime_libraries"] = libraries
                    passed("bundled_cwebp_system_libraries_only")
                passed(f"bundled_{name}_runs")
            qpdf = Path(engines["qpdf"])
            libreoffice = Path(engines.get("libreoffice", "missing"))
            has_office = libreoffice.is_file() and os.access(libreoffice, os.X_OK)
            measurements["libreoffice_available"] = has_office
            fixtures = root / "Fixtures with spaces Ω"
            fixtures.mkdir()

            def process(source: Path, arguments: list[str], expected_count: int = 1) -> tuple[list[Path], dict[str, object]]:
                before = digest(source)
                record = json.loads(execute([str(cli), str(source), *arguments], environment))
                outputs = [Path(value) for value in record.get("outputs", [])]
                if len(outputs) != expected_count or len(set(outputs)) != expected_count:
                    raise VerificationError(f"Expected {expected_count} distinct outputs from {source.name}: {outputs}")
                for output in outputs:
                    if not output.is_file() or not output.stat().st_size or not output.resolve().is_relative_to(fixtures.resolve()) or output.resolve() == source.resolve():
                        raise VerificationError("Output is missing, empty, outside the test directory, or overwrites its source")
                if digest(source) != before:
                    raise VerificationError(f"Source changed during processing: {source.name}")
                if record.get("inputBytes") != source.stat().st_size or record.get("outputBytes") != sum(output.stat().st_size for output in outputs):
                    raise VerificationError("Reported sizes do not match the actual files")
                return outputs, record

            def convert(source: Path, option: str, value: str) -> tuple[Path, dict[str, object]]:
                outputs, record = process(source, [option, value])
                return outputs[0], record

            def pdf_objects(source: Path) -> dict[str, object]:
                return json.loads(execute([str(qpdf), "--json-output=2", str(source)], environment, 30))["qpdf"][1]

            def text_content(source: Path) -> str:
                output, _ = convert(source, "--to", "txt")
                return output.read_text(encoding="utf-8")

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
            if "convert-webp" not in available:
                raise VerificationError("The packaged CLI does not advertise its bundled WebP encoder")
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

            image_metadata = fixtures / "Image metadata and alpha Ω.png"
            make_metadata_png(image_metadata)
            webp, _ = convert(image_metadata, "--to", "webp")
            if webp_dimensions(webp) != (64, 48, True):
                raise VerificationError("WebP conversion lost dimensions or transparency")
            webp_png, _ = convert(webp, "--to", "png")
            original_pixels = png_rgba(image_metadata)
            roundtrip_pixels = png_rgba(webp_png)
            if original_pixels[:2] != roundtrip_pixels[:2]:
                raise VerificationError("WebP round-trip changed dimensions")
            for offset in range(0, len(original_pixels[2]), 4):
                original = original_pixels[2][offset:offset + 4]
                actual = roundtrip_pixels[2][offset:offset + 4]
                if original[3] != actual[3] or (original[3] and max(abs(a - b) for a, b in zip(original[:3], actual[:3])) > 8):
                    raise VerificationError("WebP round-trip lost alpha or visibly changed the black/white test pattern")
            passed("webp_roundtrip_preserves_dimensions_alpha_and_pattern")
            scrubbed_images, _ = process(image_metadata, ["--scrub-metadata"])
            if b"PRIVATE IMAGE AUTHOR 6817" in scrubbed_images[0].read_bytes() or png_rgba(scrubbed_images[0]) != original_pixels:
                raise VerificationError("Image metadata scrub left identifying text or changed pixels")
            passed("image_metadata_removed_without_pixel_changes")

            document = fixtures / "Document tools verification Ω.pdf"
            make_document_pdf(document)
            execute([str(qpdf), "--check", str(document)], environment, 30)
            original_text = text_content(document)
            for sentinel in ("SECRET REGION 73915", "PUBLIC CONTENT SURVIVES 24680", "SECOND PAGE PUBLIC 73915"):
                if sentinel not in normalized_text(original_text):
                    raise VerificationError("Generated PDF fixture is missing expected text")
            mods = json.loads(execute([str(cli), "--capabilities", str(document)], environment, 10))
            if not {"split", "redact", "ocr", "metadata"}.issubset({action["id"] for action in mods.get("modifications", [])}):
                raise VerificationError("The packaged CLI is missing required PDF modification capabilities")
            first_pages, _ = process(document, ["--to", "png", "--pdf-mode", "firstPage"])
            all_pages, _ = process(document, ["--to", "png", "--pdf-mode", "allPages"], expected_count=2)
            merged_pages, _ = process(document, ["--to", "png", "--pdf-mode", "mergedTallImage"])
            if png_dimensions(first_pages[0]) != (1224, 1584) or [png_dimensions(page) for page in all_pages] != [(1224, 1584), (1224, 1224)] or png_dimensions(merged_pages[0]) != (1224, 2808):
                raise VerificationError("PDF export mode page counts, order, or geometry are incorrect")
            if len({page.parent for page in all_pages}) != 1 or all_pages[0].parent == fixtures:
                raise VerificationError("All-pages export did not publish its pages in one dedicated folder")
            if digest(first_pages[0]) != digest(all_pages[0]):
                # Metadata/encoding differences are allowed, but the first-page pixels must match.
                if png_rgba(first_pages[0]) != png_rgba(all_pages[0]):
                    raise VerificationError("First-page export differs from page one of the all-pages export")
            pdf_webp, _ = process(document, ["--to", "webp", "--pdf-mode", "firstPage"])
            if webp_dimensions(pdf_webp[0])[:2] != (1224, 1584):
                raise VerificationError("PDF-to-WebP export has incorrect page geometry")
            passed("pdf_export_first_all_merged_and_webp")
            split_pages, _ = process(document, ["--split"], expected_count=2)
            for index, page in enumerate(split_pages):
                execute([str(qpdf), "--check", str(page)], environment, 30)
                if execute([str(qpdf), "--show-npages", str(page)], environment, 10).strip() != "1":
                    raise VerificationError("Split output contains more than one page")
                text = normalized_text(text_content(page))
                expected = "SECRET REGION 73915" if index == 0 else "SECOND PAGE PUBLIC 73915"
                forbidden = "SECOND PAGE PUBLIC 73915" if index == 0 else "SECRET REGION 73915"
                if expected not in text or forbidden in text:
                    raise VerificationError("Split output lost, mixed, or reordered page contents")
            passed("pdf_split_preserves_each_page_content_and_order")
            ocr_outputs, _ = process(document, ["--ocr"])
            recognized = normalized_text(ocr_outputs[0].read_text(encoding="utf-8"))
            if not all(sentinel in recognized for sentinel in ("SECRET REGION 73915", "PUBLIC CONTENT SURVIVES 24680", "SECOND PAGE PUBLIC 73915")):
                raise VerificationError("PDF OCR did not recognize the visible page sentinels")
            image_ocr, _ = process(first_pages[0], ["--ocr"])
            if "PUBLIC CONTENT SURVIVES 24680" not in normalized_text(image_ocr[0].read_text(encoding="utf-8")):
                raise VerificationError("Image OCR did not recognize visible fixture text")
            passed("pdf_and_image_ocr_recognize_visible_text")
            before_objects = pdf_objects(document)
            scrubbed_pdfs, _ = process(document, ["--scrub-metadata"])
            cleaned_objects = pdf_objects(scrubbed_pdfs[0])
            trailer = cleaned_objects["trailer"]["value"]
            catalog = cleaned_objects["obj:" + trailer["/Root"]]["value"]
            if "/Info" in trailer or "/Metadata" in catalog or "PRIVATE" in json.dumps(cleaned_objects) or trailer.get("/ID") == before_objects["trailer"]["value"].get("/ID"):
                raise VerificationError("PDF scrub retained document metadata or source IDs")
            if text_content(scrubbed_pdfs[0]) != original_text:
                raise VerificationError("PDF metadata scrub changed document text")
            passed("pdf_metadata_and_source_ids_removed_content_preserved")
            regions = fixtures / "Regions Ω.json"
            regions.write_text(json.dumps([{"pageIndex": 0, "x": 0.09, "y": 0.10, "width": 0.82, "height": 0.12}]), encoding="utf-8")
            redacted_pdfs, _ = process(document, ["--redact-regions", str(regions)])
            redacted = redacted_pdfs[0]
            execute([str(qpdf), "--check", str(redacted)], environment, 30)
            if execute([str(qpdf), "--show-npages", str(redacted)], environment, 10).strip() != "2":
                raise VerificationError("Redaction changed the PDF page count")
            redacted_objects = pdf_objects(redacted)
            if "/Info" in redacted_objects["trailer"]["value"] or any(token in json.dumps(redacted_objects) for token in ("/Font", "/Annots", "/Metadata", "/EmbeddedFiles", "PRIVATE")):
                raise VerificationError("Redacted PDF retained text resources or hidden source objects")
            redacted_ocr, _ = process(redacted, ["--ocr"])
            redacted_text = normalized_text(redacted_ocr[0].read_text(encoding="utf-8"))
            if "SECRET" in redacted_text or "PUBLIC CONTENT SURVIVES 24680" not in redacted_text or "SECOND PAGE PUBLIC 73915" not in redacted_text:
                raise VerificationError("Redaction left the secret readable or removed unselected page content")
            redacted_png, _ = process(redacted, ["--to", "png", "--pdf-mode", "firstPage"])
            width, height, pixels = png_rgba(redacted_png[0])
            pixel = ((int(height * 0.16) * width) + int(width * 0.5)) * 4
            if max(pixels[pixel:pixel + 3]) > 1:
                raise VerificationError("Selected redaction region was not rendered as opaque black")
            passed("pdf_redaction_removes_selected_content_and_preserves_unselected_text_visually")

            if has_office:
                text = fixtures / "Office verification Ω.txt"
                sentinel = "FileOrbit packaged Office round-trip 73915"
                text.write_text(sentinel + "\nUnicode check: café Ω.\n", encoding="utf-8")
                office_pdf, _ = convert(text, "--to", "pdf")
                if execute([str(qpdf), "--show-npages", str(office_pdf)], environment, 10).strip() != "1":
                    raise VerificationError("Office text fixture should produce one PDF page")
                passed("txt_to_pdf_with_libreoffice")
                office_ocr, _ = process(office_pdf, ["--ocr"])
                if normalized_text(sentinel) not in normalized_text(office_ocr[0].read_text(encoding="utf-8")):
                    raise VerificationError("OCR failed on the LibreOffice-generated PDF")
                passed("libreoffice_pdf_ocr_recognizes_sentinel")
                docx, _ = convert(text, "--to", "docx")
                passed("txt_to_docx_with_libreoffice")
                roundtrip, _ = convert(docx, "--to", "txt")
                if sentinel not in roundtrip.read_text(encoding="utf-8"):
                    raise VerificationError("DOCX round-trip lost the sentinel text")
                passed("docx_to_txt_sentinel_preserved")
            else:
                skipped.append("LibreOffice missing: TXT/PDF/DOCX round-trip not exercised")
            leftovers = [str(path.relative_to(fixtures)) for path in fixtures.rglob(".fileorbit-*")]
            if leftovers:
                raise VerificationError(f"Temporary processing folders were left behind: {leftovers}")
            passed("temporary_processing_folders_removed")
            # Temp-only tests leave source documents, prior results and the installed app untouched.
            result = {"status": "passed" if not skipped else "partial", "archive": str(archive),
                      "checks_passed": len(checks), "checks": checks, "skipped": skipped,
                      "measurements": measurements, "seconds": round(time.monotonic() - started, 3)}
            print(json.dumps(result, indent=2, ensure_ascii=False))
            return 0 if not skipped else 3
    except (VerificationError, OSError, ValueError, KeyError, TypeError, IndexError, zlib.error, struct.error) as error:
        print(json.dumps({"status": "failed", "archive": str(archive), "checks_passed": len(checks),
                          "checks": checks, "error": str(error)}, indent=2), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
