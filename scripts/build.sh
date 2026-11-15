#!/bin/zsh
set -euo pipefail
TASK_ROOT="${0:A:h:h}"
TASK_VERSION="${1:-1.0.0}"
TASK_BUILD_NUMBER="${2:-2}"
if [[ ! "$TASK_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' || ! "$TASK_BUILD_NUMBER" =~ '^[0-9]+$' ]]; then
    print -u2 "版本应为 x.y.z，构建号应为非负整数。"
    exit 1
fi
cd "$TASK_ROOT"
swift build -c release
TASK_BIN="$(swift build -c release --show-bin-path)"
TASK_APP="$TASK_ROOT/build/知间.app"
mkdir -p "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources"
cp "$TASK_BIN/ZhijianApp" "$TASK_APP/Contents/MacOS/ZhijianApp"
cp "$TASK_BIN/zhijian" "$TASK_APP/Contents/MacOS/zhijian"
cp -R "$TASK_BIN/Zhijian_DictionaryCore.bundle" "$TASK_APP/Contents/Resources/"
cat > "$TASK_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ZhijianApp</string>
<key>CFBundleIdentifier</key><string>studio.zhijian.dictionary</string>
<key>CFBundleName</key><string>知间</string>
<key>CFBundleDisplayName</key><string>知间</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHumanReadableCopyright</key><string>知间 — 个人概念词典</string>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $TASK_VERSION" "$TASK_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $TASK_BUILD_NUMBER" "$TASK_APP/Contents/Info.plist"
if [[ ! -f "$TASK_APP/Contents/Resources/AppIcon.icns" ]]; then
    swift "$TASK_ROOT/scripts/make-icon.swift" "$TASK_ROOT/build/AppIcon.iconset"
    iconutil -c icns "$TASK_ROOT/build/AppIcon.iconset" -o "$TASK_APP/Contents/Resources/AppIcon.icns"
fi
codesign --force --deep --sign - "$TASK_APP"
print "已构建：$TASK_APP"
