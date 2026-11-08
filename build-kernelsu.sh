#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$ANDROID_HOME" || ! -d "$ANDROID_HOME" ]]; then
  echo "ERROR: ANDROID_HOME/ANDROID_SDK_ROOT must point to an installed Android SDK." >&2
  exit 2
fi
export ANDROID_HOME ANDROID_SDK_ROOT="$ANDROID_HOME"

for cmd in java keytool base64 go zip unzip file sha256sum; do
  command -v "$cmd" >/dev/null || { echo "ERROR: missing required command: $cmd" >&2; exit 2; }
done
[[ -f "$ANDROID_HOME/platforms/android-34/android.jar" ]] || {
  echo "ERROR: Android SDK platform android-34 is missing." >&2
  exit 2
}
[[ -f "$ROOT/gradle/wrapper/gradle-wrapper.jar" ]] || {
  echo "ERROR: Gradle wrapper JAR is missing." >&2
  exit 2
}
chmod +x "$ROOT/gradlew"

# Use a stable signing key when supplied through Actions secrets. Otherwise
# generate a local debug key so CI can still produce a first-install ZIP.
mkdir -p "$HOME/.android"
if [[ -n "${GSM2SIP_KEYSTORE_BASE64:-}" ]]; then
  KEYSTORE="$HOME/.android/gsm2sip-release.keystore"
  printf '%s' "$GSM2SIP_KEYSTORE_BASE64" | base64 --decode > "$KEYSTORE"
  export GSM2SIP_KEYSTORE_PATH="$KEYSTORE"
  export GSM2SIP_KEYSTORE_PASSWORD="${GSM2SIP_KEYSTORE_PASSWORD:?Missing GSM2SIP_KEYSTORE_PASSWORD}"
  export GSM2SIP_KEY_ALIAS="${GSM2SIP_KEY_ALIAS:?Missing GSM2SIP_KEY_ALIAS}"
  export GSM2SIP_KEY_PASSWORD="${GSM2SIP_KEY_PASSWORD:?Missing GSM2SIP_KEY_PASSWORD}"
else
  KEYSTORE="$HOME/.android/debug.keystore"
  if [[ ! -s "$KEYSTORE" ]]; then
    keytool -genkeypair -v \
      -keystore "$KEYSTORE" -storepass android \
      -alias androiddebugkey -keypass android \
      -dname "CN=Android Debug,O=Android,C=US" \
      -keyalg RSA -keysize 2048 -validity 10000
  fi
  export GSM2SIP_KEYSTORE_PATH="$KEYSTORE"
  export GSM2SIP_KEYSTORE_PASSWORD="${GSM2SIP_KEYSTORE_PASSWORD:-android}"
  export GSM2SIP_KEY_ALIAS="${GSM2SIP_KEY_ALIAS:-androiddebugkey}"
  export GSM2SIP_KEY_PASSWORD="${GSM2SIP_KEY_PASSWORD:-android}"
fi
keytool -list -keystore "$GSM2SIP_KEYSTORE_PATH" \
  -storepass "$GSM2SIP_KEYSTORE_PASSWORD" -alias "$GSM2SIP_KEY_ALIAS" >/dev/null

echo "=== Building gsm2sip APK ==="
./gradlew --no-daemon assembleDebug assembleRelease

APK="$ROOT/app/build/outputs/apk/release/app-release.apk"
[[ -s "$APK" ]] || { echo "ERROR: signed release APK not found: $APK" >&2; exit 1; }

STAGE="$ROOT/build/kernelsu-stage"
DIST="$ROOT/dist"
rm -rf "$STAGE" "$DIST"
mkdir -p "$STAGE/system/priv-app/Gateway" \
         "$STAGE/system/etc/permissions" \
         "$STAGE/tools/arm64"

cp "$APK" "$STAGE/system/priv-app/Gateway/Gateway.apk"
cp "$ROOT/magisk/system/etc/permissions/privapp-permissions-gateway.xml" \
   "$STAGE/system/etc/permissions/privapp-permissions-gateway.xml"
cp "$ROOT/kernelsu/module.prop" "$STAGE/module.prop"
cp "$ROOT/kernelsu/customize.sh" "$STAGE/customize.sh"
cp "$ROOT/kernelsu/service.sh" "$STAGE/service.sh"
cp "$ROOT/kernelsu/uninstall.sh" "$STAGE/uninstall.sh"
cp "$ROOT/LICENSE" "$STAGE/LICENSE"
cp "$ROOT/kernelsu/README.md" "$STAGE/README-gsm2sip-KernelSU.txt"

build_go_tool() {
  local name="$1"
  local out="$2"
  (cd "$ROOT/tools/$name" && CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
    go build -trimpath -ldflags='-s -w' -o "$out" .)
  chmod 0755 "$out"
}
build_go_tool tinymix "$STAGE/tools/arm64/tinymix"
build_go_tool tinypcm "$STAGE/tools/arm64/tinypcm"

# tinycap is an upstream prebuilt; reject a wrong ABI instead of shipping it.
if [[ -s "$ROOT/magisk/tinycap" ]] && file "$ROOT/magisk/tinycap" | grep -Eqi 'ARM aarch64|ARM64'; then
  cp "$ROOT/magisk/tinycap" "$STAGE/tools/arm64/tinycap"
  chmod 0755 "$STAGE/tools/arm64/tinycap"
else
  echo "ERROR: magisk/tinycap is missing or not ARM64." >&2
  exit 1
fi

# Verify the APK, ZIP structure, module metadata and native helper ABIs.
unzip -t "$STAGE/system/priv-app/Gateway/Gateway.apk" >/dev/null
grep -q '^id=gsm2sip-kernelsu$' "$STAGE/module.prop"
grep -q '^versionCode=458$' "$STAGE/module.prop"
for f in customize.sh service.sh uninstall.sh; do
  [[ -s "$STAGE/$f" ]] || { echo "ERROR: missing module script $f" >&2; exit 1; }
done
file "$STAGE/tools/arm64/"*
file "$STAGE/system/priv-app/Gateway/Gateway.apk"

mkdir -p "$DIST"
ZIP="$DIST/gsm2sip-kernelsu-thor-v1.4.18-ksu2.zip"
(
  cd "$STAGE"
  zip -X -qr "$ZIP" .
)
unzip -t "$ZIP" >/dev/null
unzip -Z1 "$ZIP" | grep -qx 'module.prop'
unzip -Z1 "$ZIP" | grep -qx 'customize.sh'
sha256sum "$ZIP" > "$ZIP.sha256"

cat > "$DIST/build-manifest.txt" <<EOF
repository=timwai/gsm2sip
source_ref=${GITHUB_SHA:-local}
app_version=1.4.18
app_version_code=457
module_id=gsm2sip-kernelsu
module_version=v1.4.18-ksu2
module_version_code=458
target=arm64-android15-thor
audio_profile=generic-qualcomm-unverified
EOF

echo "Built: $ZIP"
echo "SHA256: $(cut -d' ' -f1 "$ZIP.sha256")"
