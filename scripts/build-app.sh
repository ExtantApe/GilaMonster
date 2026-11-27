#!/bin/bash
# Builds dist/GilaMonster.app (or --out DIR), ad-hoc signed. Needs only the Command Line Tools.
#   scripts/build-app.sh              this Mac's architecture
#   scripts/build-app.sh --universal  Apple silicon and Intel
#   scripts/build-app.sh --dmg        also makes a .zip and .dmg for a GitHub release
#   scripts/build-app.sh --out DIR    builds DIR/GilaMonster.app instead (default: dist)
#   scripts/build-app.sh --guard-only runs the safety check below and stops
# Refuses to start while anything runs from the target bundle: the build deletes it first, and on 2026-11-17
# that pulled the bundle out from under the owner's running GilaMonster. Build into another folder with --out.
set -euo pipefail
cd "$(dirname "$0")/.."

universal=false; dmg=false; out="dist"; guard_only=false
while [ $# -gt 0 ]; do
    case "$1" in
        --universal) universal=true ;;
        --dmg) dmg=true; universal=true ;;
        --out) [ $# -ge 2 ] || { echo "--out needs a folder" >&2; exit 2; }; out="$2"; shift ;;
        --guard-only) guard_only=true ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
out="${out%/}"

version=$(sed -n 's/.*static let version = "\(.*\)"/\1/p' Sources/GilaMonsterCore/Support.swift)
app="$out/GilaMonster.app"

# Anything running from inside the bundle (the app, gilamonster-mcp, gilamonster-session) stops the build.
mkdir -p "$out"
abs_app="$(cd "$out" && pwd -P)/GilaMonster.app"
# Paths are compared after resolving links, so /var and /private/var, or a doubled slash, can't slip past.
running=""
while read -r pid exe; do
    case "$exe" in */GilaMonster.app/Contents/*) ;; *) continue ;; esac
    real="$(cd "$(dirname "$exe")" 2>/dev/null && pwd -P)/$(basename "$exe")" || continue
    case "$real" in "$abs_app"/*) running+="$pid $exe"$'\n' ;; esac
done < <(ps -axo pid=,comm=)
running="${running%$'\n'}"
if [ -n "$running" ]; then
    echo "Not building: $app is in use, and the build deletes it first." >&2
    echo "$running" | sed 's/^/  running: /' >&2
    echo "Quit it first, or build somewhere else: scripts/build-app.sh --out dist-next" >&2
    exit 3
fi
if $guard_only; then echo "Nothing is running from $app."; exit 0; fi

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

if $universal; then
    swift build -c release --product GilaMonster --arch arm64
    swift build -c release --product GilaMonster --arch x86_64
    swift build -c release --product gilamonster-mcp --arch arm64
    swift build -c release --product gilamonster-mcp --arch x86_64
    swift build -c release --product gilamonster-session --arch arm64
    swift build -c release --product gilamonster-session --arch x86_64
    lipo -create -output "$app/Contents/MacOS/gilamonster-session" \
        .build/arm64-apple-macosx/release/gilamonster-session \
        .build/x86_64-apple-macosx/release/gilamonster-session
    lipo -create -output "$app/Contents/MacOS/gilamonster-mcp" \
        .build/arm64-apple-macosx/release/gilamonster-mcp \
        .build/x86_64-apple-macosx/release/gilamonster-mcp
    lipo -create -output "$app/Contents/MacOS/GilaMonster" \
        .build/arm64-apple-macosx/release/GilaMonster \
        .build/x86_64-apple-macosx/release/GilaMonster
else
    swift build -c release --product GilaMonster
    swift build -c release --product gilamonster-mcp
    swift build -c release --product gilamonster-session
    cp .build/release/gilamonster-session "$app/Contents/MacOS/gilamonster-session"
    cp .build/release/GilaMonster "$app/Contents/MacOS/GilaMonster"
    cp .build/release/gilamonster-mcp "$app/Contents/MacOS/gilamonster-mcp"
fi
strip -x "$app/Contents/MacOS/GilaMonster" 2>/dev/null || true
strip -x "$app/Contents/MacOS/gilamonster-mcp" 2>/dev/null || true
strip -x "$app/Contents/MacOS/gilamonster-session" 2>/dev/null || true

[ -f brand/AppIcon.icns ] || swift scripts/brand-kit.swift brand/kit
cp brand/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp brand/MenuBarTemplate.png brand/MenuBarTemplate@2x.png "$app/Contents/Resources/"
# The display face (K786): Lilita One, SIL OFL 1.1, with its licence beside it as the OFL asks.
mkdir -p "$app/Contents/Resources/Fonts"
cp brand/fonts/lilitaone/LilitaOne-Regular.ttf "$app/Contents/Resources/Fonts/"
cp brand/fonts/lilitaone/OFL.txt "$app/Contents/Resources/Fonts/LilitaOne-OFL.txt"
# The pixel faces (K820): Departure Mono and Pixelify Sans, both SIL OFL 1.1, each with its licence.
cp brand/fonts/departuremono/DepartureMono-Regular.otf "$app/Contents/Resources/Fonts/"
cp brand/fonts/departuremono/OFL.txt "$app/Contents/Resources/Fonts/DepartureMono-OFL.txt"
cp "brand/fonts/pixelifysans/PixelifySans[wght].ttf" "$app/Contents/Resources/Fonts/"
cp brand/fonts/pixelifysans/OFL.txt "$app/Contents/Resources/Fonts/PixelifySans-OFL.txt"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>GilaMonster</string>
    <key>CFBundleDisplayName</key><string>GilaMonster</string>
    <key>CFBundleIdentifier</key><string>com.extantape.gilamonster</string>
    <key>CFBundleExecutable</key><string>GilaMonster</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License. Not affiliated with Mojang or Microsoft.</string>
</dict>
</plist>
PLIST

# Local builds sign with the owner's own self-signed "GilaMonster Local Signing" certificate when it's in
# the login keychain, so every rebuild keeps one identity and macOS doesn't ask for Keychain access or
# notification permission again after each swap. Without it, and always for release builds (--dmg, or
# in CI), the signature is ad hoc: required to run on Apple silicon, but not an Apple Developer signature,
# so macOS still asks people to approve the first launch. The README explains how.
identity="GilaMonster Local Signing"
if ! $dmg && [ -z "${CI:-}" ] && security find-identity -p codesigning 2>/dev/null | grep -q "\"$identity\""; then
    codesign --force --deep --sign "$identity" "$app"
    echo "Signed with $identity"
else
    codesign --force --deep --sign - "$app"
    echo "Signed ad hoc"
fi

if $dmg; then
    ( cd "$out" && rm -f GilaMonster-*.zip GilaMonster-*.dmg && ditto -c -k --keepParent "GilaMonster.app" "GilaMonster-$version.zip" )
    staging=$(mktemp -d)
    cp -R "$app" "$staging/"
    ln -s /Applications "$staging/Applications"
    hdiutil create -quiet -volname "GilaMonster" -srcfolder "$staging" -ov -format UDZO "$out/GilaMonster-$version.dmg"
    rm -rf "$staging"
fi

echo "Built $app ($(du -sh "$app" | cut -f1))"
