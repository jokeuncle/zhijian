#!/bin/zsh
set -euo pipefail
TASK_ROOT="${0:A:h:h}"
TASK_VERSION="${1:-1.0.0-preview.2}"
TASK_BUILD_NUMBER="${2:-2}"
cd "$TASK_ROOT"
"$TASK_ROOT/scripts/build.sh" "${TASK_VERSION%%-*}" "$TASK_BUILD_NUMBER"
TASK_NATIVE_BIN="$(swift build -c release --show-bin-path)"
swift build -c release --triple x86_64-apple-macosx14.0 --scratch-path .build-intel --product ZhijianApp
swift build -c release --triple x86_64-apple-macosx14.0 --scratch-path .build-intel --product zhijian
TASK_INTEL_BIN="$(swift build -c release --triple x86_64-apple-macosx14.0 --scratch-path .build-intel --show-bin-path)"
TASK_APP="$TASK_ROOT/build/知间.app"
for TASK_PRODUCT in ZhijianApp zhijian; do
    lipo -create "$TASK_NATIVE_BIN/$TASK_PRODUCT" "$TASK_INTEL_BIN/$TASK_PRODUCT" -output "$TASK_APP/Contents/MacOS/$TASK_PRODUCT"
    lipo "$TASK_APP/Contents/MacOS/$TASK_PRODUCT" -verify_arch arm64 x86_64
done
codesign --force --deep --sign - "$TASK_APP"
codesign --verify --deep --strict "$TASK_APP"
mkdir -p "$TASK_ROOT/dist"
TASK_ARCHIVE="Zhijian-$TASK_VERSION-macOS-universal"
ditto -c -k --sequesterRsrc --keepParent "$TASK_APP" "$TASK_ROOT/dist/$TASK_ARCHIVE.zip"
TASK_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/zhijian-release.XXXXXX")"
trap 'rm -rf "$TASK_STAGE"' EXIT
ditto "$TASK_APP" "$TASK_STAGE/知间.app"
ln -s /Applications "$TASK_STAGE/Applications"
cp "$TASK_ROOT/docs/INSTALL.zh-CN.txt" "$TASK_STAGE/首次打开说明.txt"
hdiutil create -volname "知间 $TASK_VERSION" -srcfolder "$TASK_STAGE" -ov -format UDZO "$TASK_ROOT/dist/$TASK_ARCHIVE.dmg"
hdiutil verify "$TASK_ROOT/dist/$TASK_ARCHIVE.dmg"
cd "$TASK_ROOT/dist"
shasum -a 256 "$TASK_ARCHIVE.dmg" "$TASK_ARCHIVE.zip" > SHA256SUMS.txt
print "通用预览版已生成：$TASK_ROOT/dist"
