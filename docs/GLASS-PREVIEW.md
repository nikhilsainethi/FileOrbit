# Local glass-wheel preview

This is an unpublished design preview for review. It uses a separate app identity and preferences from FileOrbit, and does not register the double-tap Command shortcut or file-type associations. The installed app and its macOS permissions remain separate. The preview stays visible when you switch apps so you can compare it with feedback in chat; close it with Escape or the × button.

The preview performs real local conversions and compression. Use copies of sample files in a dedicated folder when reviewing it. Outputs are saved beside the selected sample, with the same collision protection as FileOrbit.

## Build

From the source directory, use a new output folder:

```sh
FILEORBIT_BUILD_DIR=/tmp/fileorbit-glass-build \
FILEORBIT_VENDOR_DIR=/path/to/vendor \
./scripts/build-preview.sh /tmp/fileorbit-glass-preview
```

The vendor directory has the same `qpdf/` and `resvg/` layout used by the normal app builder. LibreOffice remains an optional local installation for Office conversions. See [installation instructions](INSTALL.md) for dependencies and supported formats.

The builder creates `FileOrbit Preview.app` and a separately named preview ZIP. It refuses to replace existing preview output or write into Applications. Its bundle identifier is `io.fileorbit.preview`, with `FileOrbitPreview=true` in its Info.plist. The public FileOrbit package is not changed.

## Review

Extract the ZIP to a local scratch folder, then open **FileOrbit Preview.app**. Use its menu-bar **Choose File…** action, or launch it with a sample selected:

```sh
open -n '/tmp/fileorbit-glass-preview/FileOrbit Preview.app' --args \
  --open '/absolute/path/to/sample-folder/Design study.png'
```

Hover or use the arrow keys to select an action, and press Return or click to run it. Escape returns from compression settings or dismisses the idle wheel. Settings and file selection remain available from the menu bar. Command-O opens the chooser in the preview. Its Preview appearance menu offers System, Light, and Dark without changing your Mac’s appearance. Processing can be cancelled; results can be revealed in Finder.

This preview is locally ad-hoc signed, not notarized. It is intended for local review before approving a public update. Do not replace the installed FileOrbit with the preview.
