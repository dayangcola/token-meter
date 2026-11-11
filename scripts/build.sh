#!/bin/zsh
set -euo pipefail
project_root=${0:A:h:h}
cd "$project_root"
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi
dependency_dir="$project_root/vendor/CodexBar"
[[ -x "$dependency_dir/CodexBarCLI" ]] || { print -u2 'Run: zsh scripts/fetch-dependency.sh'; exit 1; }
task_cache="$project_root/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$task_cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$task_cache"
swift build -c release --disable-sandbox --cache-path "$project_root/.build/cache"
binary_dir=$(swift build -c release --show-bin-path --disable-sandbox --cache-path "$project_root/.build/cache")
app="$project_root/dist/AI 额度栏.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"
cp "$binary_dir/AIQuotaBar" "$app/Contents/MacOS/AIQuotaBar"
cp "$dependency_dir/CodexBarCLI" "$app/Contents/Helpers/"
ditto "$dependency_dir/CodexBar_CodexBarCore.bundle" "$app/Contents/Helpers/CodexBar_CodexBarCore.bundle"
cp "$dependency_dir/THIRD_PARTY_NOTICES" "$app/Contents/Resources/THIRD_PARTY_NOTICES"
cp "$dependency_dir/LICENSE" "$app/Contents/Resources/CodexBar-LICENSE"
cp docs/使用说明.html "$app/Contents/Resources/使用说明.html"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AIQuotaBar</string>
<key>CFBundleIdentifier</key><string>local.aiquotabar.desktop</string>
<key>CFBundleName</key><string>AI 额度栏</string>
<key>CFBundleDisplayName</key><string>AI 额度栏</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Built locally. Includes CodexBar under the MIT License.</string>
</dict></plist>
PLIST
swift scripts/GenerateIcon.swift "$project_root/dist/AppIcon.iconset"
/usr/bin/iconutil -c icns "$project_root/dist/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"
/usr/bin/codesign --force --sign - "$app/Contents/Helpers/CodexBar_CodexBarCore.bundle"
/usr/bin/codesign --force --sign - "$app/Contents/MacOS/AIQuotaBar"
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --deep --strict "$app"
print "Built: $app"
