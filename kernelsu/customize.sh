#!/system/bin/sh
# KernelSU sources customize.sh after extracting the module.
# Keep this installer ARM64-only and restricted to Android 15+.

[ "${KSU:-false}" = "true" ] || abort "Install this ZIP from KernelSU Manager, not custom recovery."
[ "${ARCH:-}" = "arm64" ] || abort "This build requires an ARM64 device."
[ "${API:-0}" -ge 35 ] || abort "This build targets Android 15 or newer."

APK="$MODPATH/system/priv-app/Gateway/Gateway.apk"
PERMS="$MODPATH/system/etc/permissions/privapp-permissions-gateway.xml"
[ -s "$APK" ] || abort "Gateway APK is missing."
[ -s "$PERMS" ] || abort "Privileged permission allowlist is missing."
[ -s "$MODPATH/tools/arm64/tinymix" ] || abort "ARM64 tinymix is missing."
[ -s "$MODPATH/tools/arm64/tinypcm" ] || abort "ARM64 tinypcm is missing."
[ -s "$MODPATH/tools/arm64/tinycap" ] || abort "ARM64 tinycap is missing."

# KernelSU's default extractor sets regular files to 0644. Restore executable
# permissions for boot/install scripts and the audio helper programs.
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/customize.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/tools/arm64/tinymix" 0 0 0755
set_perm "$MODPATH/tools/arm64/tinypcm" 0 0 0755
set_perm "$MODPATH/tools/arm64/tinycap" 0 0 0755
set_perm "$APK" 0 0 0644
set_perm "$PERMS" 0 0 0644

ui_print "- gsm2sip KernelSU module"
ui_print "- Target: ARM64 / Android 15+ (thor)"
ui_print "- KernelSU: ${KSU_VER:-unknown}"
ui_print "- Install a system metamodule such as Meta-OverlayFS before reboot."
ui_print "- Reboot after installation, then grant Gateway root in KernelSU Manager."
ui_print "- Thor call-audio routing is experimental and not yet verified."
