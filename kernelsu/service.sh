#!/system/bin/sh
# KernelSU late_start service for gsm2sip.
# Does not modify Magisk databases, disable PermissionController, or change
# global SMS policy. KernelSU root approval remains user-controlled.

MODDIR="${0%/*}"
TAG="gsm2sip-KSU"
PKG="com.callagent.gateway"
LOG() { log -t "$TAG" "$*"; }

# Wait until Android package manager is ready.
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

# Audio helpers are copied to a writable executable location because vendor
# SELinux policies may deny execution from the system overlay.
ABI="$(getprop ro.product.cpu.abi)"
case "$ABI" in
    arm64*|aarch64*)
        MIX="$MODDIR/tools/arm64/tinymix"
        PCM="$MODDIR/tools/arm64/tinypcm"
        CAP="$MODDIR/tools/arm64/tinycap"
        ;;
    arm*)
        MIX="$MODDIR/tools/arm/tinymix"
        PCM="$MODDIR/tools/arm/tinypcm"
        CAP=""
        ;;
    *)
        LOG "Unsupported primary ABI: $ABI"
        MIX=""; PCM=""; CAP=""
        ;;
esac

install_tool() {
    SRC="$1"
    NAME="$2"
    [ -n "$SRC" ] && [ -f "$SRC" ] || return 0
    mkdir -p /data/local/tmp
    cp "$SRC" "/data/local/tmp/$NAME" || { LOG "copy failed: $NAME"; return 1; }
    chmod 0755 "/data/local/tmp/$NAME"
    chown 0:0 "/data/local/tmp/$NAME" 2>/dev/null
    LOG "installed $NAME for $ABI"
}
install_tool "$MIX" tinymix
install_tool "$PCM" tinypcm
install_tool "$CAP" tinycap

# Runtime permissions used by GSM/SMS forwarding. Protected permissions are
# granted by privapp-permissions XML; pm grant is only for runtime permissions.
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

# RECORD_AUDIO may be used from the foreground gateway service. Do not disable
# PermissionController; only set this package's own AppOp.
appops set "$PKG" RECORD_AUDIO allow >/dev/null 2>&1 && LOG "RECORD_AUDIO appop allowed"

# Diagnostics: record the exact device identity without assuming an audio
# profile. Do not load any device-specific kernel module on thor.
LOG "boot service complete: ABI=$ABI hardware=$(getprop ro.hardware) board=$(getprop ro.board.platform) fingerprint=$(getprop ro.build.fingerprint)"
for PERM in CAPTURE_AUDIO_OUTPUT MODIFY_PHONE_STATE READ_PRIVILEGED_PHONE_STATE CALL_PRIVILEGED; do
    dumpsys package "$PKG" 2>/dev/null | grep -m1 "$PERM" | while read LINE; do LOG "$LINE"; done
done
