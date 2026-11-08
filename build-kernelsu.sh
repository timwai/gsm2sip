#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
: "${ANDROID_HOME:=${ANDROID_SDK_ROOT:-}}"
if [[ -z "$ANDROID_HOME" ]]; then echo "ANDROID_HOME/ANDROID_SDK_ROOT is required" >&2; exit 2; fi
export ANDROID_HOME ANDROID_SDK_ROOT="$ANDROID_HOME"
command -v java >/dev/null || { echo "JDK 17+ required" >&2; exit 2; }
command -v gradle >/dev/null || { echo "Gradle 8.5 required (or install wrapper)" >&2; exit 2; }
command -v go >/dev/null || { echo "Go is required" >&2; exit 2; }
command -v zip >/dev/null || { echo "zip is required" >&2; exit 2; }
command -v file >/dev/null || { echo "file is required" >&2; exit 2; }

SDK_PLATFORM="$ANDROID_HOME/platforms/android-34"
[[ -d "$SDK_PLATFORM" ]] || { echo "Missing Android SDK platform android-34" >&2; exit 2; }

# Generate the default debug key first; app/build.gradle.kts intentionally uses
# the same key for release so a module update preserves the package signature.
gradle --no-daemon assembleDebug
gradle --no-daemon assembleRelease
APK="$ROOT/app/build/outputs/apk/release/app-release.apk"
[[ -s "$APK" ]] || APK="$ROOT/app/build/outputs/apk/release/app-release-unsigned.apk"
[[ -s "$APK" ]] || { echo "Release APK not found" >&2; exit 1; }

STAGE="$ROOT/build/kernelsu-stage"
DIST="$ROOT/dist"
rm -rf "$STAGE" "$DIST"
mkdir -p "$STAGE/system/priv-app/Gateway" \
         "$STAGE/system/etc/permissions" \
         "$STAGE/tools/arm64" "$STAGE/tools/arm"
cp "$APK" "$STAGE/system/priv-app/Gateway/Gateway.apk"
cp "$ROOT/magisk/system/etc/permissions/privapp-permissions-gateway.xml" \
   "$STAGE/system/etc/permissions/privapp-permissions-gateway.xml"
cp "$ROOT/kernelsu/module.prop" "$STAGE/module.prop"
cp "$ROOT/kernelsu/service.sh" "$STAGE/service.sh"
cp "$ROOT/LICENSE" "$STAGE/LICENSE"
cp "$ROOT/kernelsu/README.md" "$STAGE/README-gsm2sip-KernelSU.txt"

build_go_tool() {
    local name="$1" arch="$2" arm="$3" out="$4"
    (cd "$ROOT/tools/$name" && CGO_ENABLED=0 GOOS=linux GOARCH="$arch" GOARM="$arm" \
        go build -trimpath -ldflags='-s -w' -o "$out" .)
    chmod 0755 "$out"
}
build_go_tool tinymix arm64 7 "$STAGE/tools/arm64/tinymix"
build_go_tool tinypcm arm64 7 "$STAGE/tools/arm64/tinypcm"
build_go_tool tinymix arm 7 "$STAGE/tools/arm/tinymix"
build_go_tool tinypcm arm 7 "$STAGE/tools/arm/tinypcm"

# Upstream tinycap is a prebuilt ARM64 executable; verify rather than silently
# ship a wrong-architecture file.
if [[ -s "$ROOT/magisk/tinycap" ]] && file "$ROOT/magisk/tinycap" | grep -Eqi 'ARM aarch64|ARM64'; then
    cp "$ROOT/magisk/tinycap" "$STAGE/tools/arm64/tinycap"
    chmod 0755 "$STAGE/tools/arm64/tinycap"
else
    echo "ERROR: magisk/tinycap is missing or not ARM64" >&2
    exit 1
fi

# Verify all packaged executables and APK before archiving.
file "$STAGE/system/priv-app/Gateway/Gateway.apk"
file "$STAGE/tools/arm64/"*
file "$STAGE/tools/arm/"*
grep -q 'id=gsm2sip-kernelsu' "$STAGE/module.prop"
unzip -t "$STAGE/system/priv-app/Gateway/Gateway.apk" >/dev/null
mkdir -p "$DIST"
(
  cd "$STAGE"
  zip -qr "$DIST/gsm2sip-kernelsu-thor-v1.4.18.zip" .
)
sha256sum "$DIST/gsm2sip-kernelsu-thor-v1.4.18.zip" > "$DIST/gsm2sip-kernelsu-thor-v1.4.18.zip.sha256"
cat > "$DIST/build-manifest.txt" <<EOF
repository=timwai/gsm2sip
source_ref=${GITHUB_SHA:-local}
app_version=1.4.18
app_version_code=457
module_id=gsm2sip-kernelsu
target=arm64-android15-thor
audio_profile=unverified-generic-qualcomm
EOF
echo "Built: $DIST/gsm2sip-kernelsu-thor-v1.4.18.zip"
