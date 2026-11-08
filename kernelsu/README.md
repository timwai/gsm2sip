# gsm2sip KernelSU module

This module packages the upstream gsm2sip Android APK as a privileged system
app and deploys the matching ARM audio helper binaries. It is intended for
KernelSU with a compatible system-overlay provider (Meta-OverlayFS is suitable).

## Important: Xiaomi 12S Ultra (thor)

The module is installable on ARM64 Android 15, but this does **not** mean the
thor call-audio path is verified. The upstream project has verified audio
profiles for selected Qualcomm, Exynos, MediaTek and Tensor devices; SM8475
(thor) is not listed as a verified device. This package deliberately does not
apply Poco X3/SM6150 mixer controls or load an unrelated kernel module.

Expect SIP registration and call control to be testable after installation;
two-way GSM/RTP audio must be validated on the actual thor ROM. If the audio
profile falls back to generic Qualcomm, the call may connect without usable
audio.

## Install

1. Ensure KernelSU is installed and its module/overlay support is working.
2. Install the ZIP from KernelSU Manager (not recovery).
3. Reboot.
4. Open KernelSU Manager and explicitly grant root to **gsm2sip / Gateway**.
5. Open Gateway, grant any remaining Android permissions, choose the default
   phone app if prompted, configure SIP, and start the gateway.

The module does not write KernelSU's internal authorization database. Root
approval remains controlled by KernelSU Manager.

## Safety choices

This port intentionally does not:
- hide or disable Android PermissionController;
- alter SMS rate limits or silence the system SMS application;
- seed Magisk's SQLite root policy;
- load the Exynos-only `abox_pos.ko` on Qualcomm;
- force a thor mixer profile or globally change audio properties.

The service only grants the Gateway app's runtime permissions, sets its own
RECORD_AUDIO AppOp, and copies the audio helper binaries to
`/data/local/tmp`.

## Build

Run `./build-kernelsu.sh` from the repository root. The output is written to
`dist/gsm2sip-kernelsu-thor-v1.4.18.zip`.
