#!/system/bin/sh
# Remove only helper binaries that still match the copies owned by this module.
MODDIR="${0%/*}"
TAG="gsm2sip-KSU"

remove_if_same() {
    NAME="$1"
    SOURCE="$2"
    TARGET="/data/local/tmp/$NAME"
    if [ -s "$SOURCE" ] && [ -s "$TARGET" ] && cmp -s "$SOURCE" "$TARGET"; then
        rm -f "$TARGET"
        log -t "$TAG" "removed module-owned helper: $TARGET"
    fi
}

remove_if_same tinymix "$MODDIR/tools/arm64/tinymix"
remove_if_same tinypcm "$MODDIR/tools/arm64/tinypcm"
remove_if_same tinycap "$MODDIR/tools/arm64/tinycap"
