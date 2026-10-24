# Installing FileOrbit

## Requirements

| Item | This preview |
| --- | --- |
| Mac | Apple Silicon (M-series) |
| macOS | Deployment target: macOS 15 or later |
| Verified local platform | Apple Silicon on macOS 27.2 |
| Interface | Liquid Glass on macOS 26+; native material on earlier versions |
| Office conversion | Separate local LibreOffice installation |
| Apple signing status | Ad hoc signed; no Developer ID signature or notarization |

Older macOS versions and Intel builds have not yet been verified. This is an early preview, so review converted documents where precise layout matters.

## Download and install

1. Open the [v0.3.0-preview.1 release](https://github.com/nikhilsainethi/FileOrbit/releases/tag/v0.3.0-preview.1).
2. Under **Assets**, download **FileOrbit-macOS-arm64.zip**. The automatically generated “Source code” archives contain the project, not the app.
3. Double-click the ZIP to extract it.
4. Drag **FileOrbit.app** into your **Applications** folder. Grant permissions to this installed copy, rather than to a copy in Downloads or a synced folder.
5. Open FileOrbit. Its menu-bar icon remains available while it runs in the background.

For an integrity check, download `SHA256SUMS.txt` from the same release. In Terminal, run this in the folder containing the downloaded ZIP and compare the result with its entry in the checksum file:

```sh
shasum -a 256 FileOrbit-macOS-arm64.zip
```

A matching checksum confirms the download matches the release asset; it is not a substitute for Apple notarization or choosing a source you trust.

## First launch and macOS security

This preview is **not notarized or signed with an Apple Developer ID**. macOS may say that Apple cannot verify the developer or check the app for malicious software.

If you have reviewed the source/release and choose to run this preview, first try opening the app. Then use **System Settings → Privacy & Security**, find the notice for FileOrbit and select **Open Anyway** if offered. Confirm the app-specific prompt yourself. Apple documents this process in [Safely open apps on your Mac](https://support.apple.com/en-us/102445).

Do not disable Gatekeeper globally or remove quarantine attributes to install FileOrbit. If macOS reports malware or a damaged app, stop, check the download and report the exact message. Managed Macs may not allow this preview; follow your organization’s policy.

## Enable the Finder shortcut

1. Open **FileOrbit → Settings** from the menu-bar icon.
2. Click **Enable in Accessibility**.
3. In System Settings, enable **FileOrbit** under **Privacy & Security → Accessibility**. On the tested macOS 27 build, the pane is named **Device Control and Data Access**. Authenticate with macOS if requested.
4. After granting or refreshing permission, quit and reopen FileOrbit once. This starts its keyboard listeners with authorization already active. Return to Settings and use **Refresh** if the status has not changed.
5. Click one file in **Finder** so Finder is the active app. Press and release the same **⌘ key twice quickly**. Do not hold another key or click between the taps.
6. On the first invocation, macOS asks whether FileOrbit may control **Finder**. Choose **Allow** to let the app read the selected file.

The file’s conversion wheel should appear immediately. No second file selection or upload is required. Choose a format or **Compress** to start.

Accessibility permission lets the app observe the shortcut. Finder Automation lets it obtain the selected file’s path. The app does not record typed text. If you prefer not to grant these permissions, use drag-and-drop, **Choose a file**, or **Open With → FileOrbit** instead.

## Enable Office conversions

FileOrbit’s app download includes **qpdf** for PDF tools, **resvg** for SVG rendering and **cwebp** for WebP encoding. Image and basic PDF operations use macOS. **LibreOffice is optional and is not bundled.**

For DOCX → PDF/TXT, PPTX → PDF/images, and TXT → PDF/DOCX:

1. Download the **macOS (Apple Silicon)** version from the [official LibreOffice download page](https://www.libreoffice.org/download/).
2. Install **LibreOffice.app** in Applications and complete its first launch if macOS requests it.
3. In **FileOrbit → Settings**, choose **Check again**. LibreOffice should appear as **Available**.
4. If it is installed elsewhere, use **Locate…** to select LibreOffice.app or its `soffice` executable.

DOCX embedded-image compression does not require LibreOffice. Missing converters hide the corresponding conversion actions. Office conversion uses an isolated LibreOffice profile; it does not automate your open Word or PowerPoint documents. Fonts and complex layouts may differ from Microsoft Office.

## Everyday use

Select one supported file in Finder, double-tap **⌘**, then choose an action. Arrow keys select actions and **Return** runs the selection. **Escape** or clicking outside closes the idle wheel. Normal Command shortcuts cancel the double-tap gesture.

Results are saved beside the source as `name-converted.ext` or `name-compressed.ext`. Existing files are never overwritten. Name collisions receive a unique name; multipage exports use a new folder. Compression only saves a result when it is smaller. Use **Reveal in Finder** on the floating completion pill to reveal the output. Hover over the pill for Quick Look, Copy and verified Undo.

The source folder must be writable. Select a downloaded local file; files that exist only in cloud storage may need to download first. FileOrbit performs conversions locally, but a result saved in a cloud-synced folder follows that folder’s normal sync behavior.

**Settings → Appearance** offers System, Light and Dark. Dark uses smoked graphite with emerald highlights; the choice changes FileOrbit only and persists after relaunch.

Hover over Compress or a multipage PDF image action for outer presets. The legend switches Convert, Modify and Quick Actions. While dragging a file in Finder, Shift, Option and Control select those respective modes; drop onto a wedge to run it or the hub to collect files in Glass Shelf. Studio is available from the menu-bar icon for action order, appearance preview and local history.

For PDF redaction, choose Modify → Redact, draw regions on each page, then export a separate copy. Redaction flattens all pages and removes searchable text and interactive objects. Inspect the result before sharing.

Launch at login is available in Settings and is off by default. There is no automatic updater in this preview.

## Troubleshooting

### Double-tap Command does nothing

- Confirm FileOrbit is running; its menu-bar icon should be present.
- Click exactly one file in Finder. The shortcut is intentionally inactive in other apps.
- Press and release the same Command key twice quickly, without any intervening key or mouse click.
- Check FileOrbit’s Accessibility permission, then quit and reopen the app.
- If the app was replaced or rebuilt, refresh the permission entry as described below.

### Permission looks enabled after an update, but the shortcut still fails

An ad hoc build’s signature can change when it is rebuilt. macOS may keep an enabled-looking entry for the previous signature.

1. Quit FileOrbit.
2. Open **System Settings → Privacy & Security → Accessibility** (or **Device Control and Data Access**).
3. Select the old **FileOrbit** entry and use **−** to remove it.
4. Use **+** to add `/Applications/FileOrbit.app`, then enable it.
5. Reopen FileOrbit and test the shortcut from Finder.

If FileOrbit reports that Finder access is denied, open **Privacy & Security → Automation**, expand FileOrbit and enable Finder. Do not grant unrelated app permissions.

### A format or compression action is missing

Check **Settings → Local converters**. LibreOffice is required for Office/text conversion; qpdf enables PDF compression and metadata removal; resvg enables SVG rendering; cwebp enables WebP output. The downloaded preview includes qpdf, resvg and cwebp, while a source build needs them bundled or installed separately.

The wheel also filters unsupported operations: same-format conversion, animated or multipage images, and unrecognized file types are not offered. PDF-to-editable-Office is not included. OCR is available under Modify for supported images and PDFs.

### Compression did not produce a file

An already optimized image, PDF or text-heavy DOCX may not become smaller. FileOrbit preserves the original and reports when it cannot create a smaller copy. Stronger presets can reduce image dimensions or quality; review the preset description before choosing one.

### Shortcut diagnostics

Diagnostics are optional and off by default. To investigate a shortcut problem, enable them and quit/reopen FileOrbit:

```sh
defaults write io.fileorbit.mac FileOrbit.shortcutDiagnostics -bool true
```

Try the shortcut, then read the recent entries:

```sh
/usr/bin/log show --last 5m --style compact --predicate 'subsystem == "io.fileorbit.mac" AND category == "Shortcut"'
```

These local entries record permission/listener state, modifier key codes and flags, event timing, whether Finder is active, and recognition results. They do not record typed text, ordinary key codes, file names, paths or file contents. Review any log excerpt before sharing it in a public issue.

Turn diagnostics off after testing, then quit/reopen FileOrbit:

```sh
defaults write io.fileorbit.mac FileOrbit.shortcutDiagnostics -bool false
```

## Updating and uninstalling

To update, quit FileOrbit, download the newer release, and replace the Applications copy. Preview builds may need the one-time permission refresh above. Your original files and conversion results are independent of the app.

To uninstall, disable **Launch FileOrbit when I log in** if you enabled it, quit FileOrbit, then move FileOrbit.app from Applications to the Trash. Remove its Accessibility entry and turn off its Finder Automation access in System Settings if they remain. LibreOffice is a separate application and can stay installed.

For source builds and CLI usage, see the [README](../README.md). For tested behavior and outstanding platform coverage, see the [verification record](TESTING.md).
