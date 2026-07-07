#!/bin/bash
# Build CodexBrain.app + the codexbrain CLI from source. Works on any Mac with Xcode tools.
#   ./install.sh          build app bundle + link CLI
#   ./install.sh --open   also launch the app when done
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Building (release)..."
swift build -c release

APP="CodexBrain.app"
BIN=".build/release/CodexBrain"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/CodexBrain"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>CodexBrain</string>
    <key>CFBundleIdentifier</key><string>com.maxrotemberg.codexbrain</string>
    <key>CFBundleName</key><string>CodexBrain</string>
    <key>CFBundleDisplayName</key><string>CodexBrain</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>CodexBrain reads the markdown notes in your vault folders to build your second brain.</string>
</dict>
</plist>
PLIST

# Prefer a real signing identity: it stays stable across rebuilds, so macOS asks
# for Documents access once instead of after every build. Ad-hoc is the fallback.
# Revoked certs make Gatekeeper DELETE the app on launch — skip them hard.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -v REVOKED | grep -o '"Apple Development[^"]*"' | head -1 | tr -d '"' || true)
if [ -n "$IDENTITY" ] && codesign --force -s "$IDENTITY" "$APP" 2>/dev/null; then
    echo "==> Signed with: $IDENTITY"
else
    codesign --force -s - "$APP" 2>/dev/null || true
    echo "==> Signed ad-hoc (permission prompt will repeat per rebuild)"
fi
echo "==> Built $PWD/$APP"

# CLI: prefer /usr/local/bin, fall back to ~/.local/bin (no sudo needed there)
CLI_TARGET="/usr/local/bin/codexbrain"
if ln -sf "$PWD/$BIN" "$CLI_TARGET" 2>/dev/null; then
    echo "==> CLI linked: codexbrain -> $CLI_TARGET"
else
    mkdir -p "$HOME/.local/bin"
    ln -sf "$PWD/$BIN" "$HOME/.local/bin/codexbrain"
    echo "==> CLI linked: ~/.local/bin/codexbrain (add ~/.local/bin to PATH if missing)"
fi

if [[ "${1:-}" == "--open" ]]; then
    open "$APP"
fi
echo "==> Done. Try: codexbrain ask \"what is my north star\""
