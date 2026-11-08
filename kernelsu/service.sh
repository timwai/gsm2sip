#!/system/bin/sh
# KernelSU late_start service for gsm2sip.
# Root authorization remains under the user's control in KernelSU Manager.

MODDIR="${0%/*}"
TAG="gsm2sip-KSU"
PKG="com.callagent.gateway"
LOG() { log -t "$TAG" "$*"; }

# Wait for Android boot and PackageManager.
i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$i" -lt 150 ]; do
    sleep 2
    i=$((i + 1))
done
i=0
while ! pm path android >/dev/null 2>&1 && [ "$i" -lt 30 ]; do
    sleep 2
    i=$((i + 1))
done

# If Gateway was updated with adb install -r, copy that signed update into
# the module's privileged APK slot. It becomes active after the next reboot.
PRIV_APK="$MODDIR/system/priv-app/Gateway/Gateway.apk"
APK_PATH="$(pm path "$PKG" 2>/dev/null | head -1 | sed 's/^package://')"
if [ -n "$APK_PATH" ] && [ -f "$APK_PATH" ] && [ "$APK_PATH" != "$PRIV_APK" ]; then
    if ! cmp -s "$APK_PATH" "$PRIV_APK" 2>/dev/null; then
        if cp "$APK_PATH" "$PRIV_APK"; then
            chmod 0644 "$PRIV_APK"
            chown 0:0 "$PRIV_APK"
            LOG "updated privileged APK from $APK_PATH; reboot required"
        else
            LOG "ERROR: could not sync updated APK from $APK_PATH"
        fi
    fi
fi

# This package is built specifically for ARM64 thor devices.
ABI="$(getprop ro.product.cpu.abi)"
case "$ABI" in
    arm64*|aarch64*)
        MIX="$MODDIR/tools/arm64/tinymix"
        PCM="$MODDIR/tools/arm64/tinypcm"
        CAP="$MODDIR/tools/arm64/tinycap"
        ;;
    *)
        LOG "Unsupported primary ABI: $ABI (this module is ARM64-only)"
        MIX=""; PCM=""; CAP=""
        ;;
esac

install_tool() {
    SRC="$1"
    NAME="$2"
    [ -n "$SRC" ] && [ -s "$SRC" ] || return 0
    mkdir -p /data/local/tmp
    if cp "$SRC" "/data/local/tmp/$NAME"; then
        chmod 0755 "/data/local/tmp/$NAME"
        chown 0:0 "/data/local/tmp/$NAME" 2>/dev/null
        LOG "installed $NAME for $ABI"
    else
        LOG "ERROR: could not install helper $NAME"
    fi
}
install_tool "$MIX" tinymix
install_tool "$PCM" tinypcm
install_tool "$CAP" tinycap

# Grant only Gateway's requested runtime permissions. Protected permissions
# are granted through the priv-app allowlist XML after a reboot.
for PERM in \
    android.permission.RECORD_AUDIO \
    android.permission.READ_PHONE_STATE \
    android.permission.READ_PHONE_NUMBERS \
    android.permission.READ_CALL_LOG \
    android.permission.RECEIVE_SMS \
    android.permission.SEND_SMS \
    android.permission.ACCESS_FINE_LOCATION \
    android.permission.ACCESS_COARSE_LOCATION \
    android.permission.CALL_PHONE \
    android.permission.ANSWER_PHONE_CALLS \
    android.permission.POST_NOTIFICATIONS
do
    pm grant "$PKG" "$PERM" >/dev/null 2>&1 && LOG "granted $PERM"
done

# Keep the audio AppOp scoped to Gateway; never kill/disable PermissionController.
appops set --uid "$PKG" RECORD_AUDIO allow >/dev/null 2>&1 && LOG "UID RECORD_AUDIO appop allowed"
appops set "$PKG" RECORD_AUDIO allow >/dev/null 2>&1 && LOG "package RECORD_AUDIO appop allowed"

LOG "boot service complete: ABI=$ABI hardware=$(getprop ro.hardware) board=$(getprop ro.board.platform) fingerprint=$(getprop ro.build.fingerprint)"
PERM_DUMP="$(dumpsys package "$PKG" 2>/dev/null)"
for PERM in CAPTURE_AUDIO_OUTPUT MODIFY_PHONE_STATE READ_PRIVILEGED_PHONE_STATE CALL_PRIVILEGED; do
    if echo "$PERM_DUMP" | grep -q "$PERM.*granted=true"; then
        LOG "$PERM: GRANTED"
    else
        LOG "$PERM: NOT GRANTED — check system overlay and permission XML, then reboot"
    fi
done
LOG "APK path: $(pm path "$PKG" 2>/dev/null | head -1)"
