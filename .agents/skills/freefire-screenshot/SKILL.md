---
name: freefire-screenshot
description: Launch Free Fire or Free Fire MAX on a connected Android device through ADB and produce a visually verified local PNG screenshot. Use when a user asks to open Free Fire on the linked phone and capture an in-game screen.
metadata:
  short-description: Capture a verified Free Fire screenshot over ADB
---

# Free Fire screenshot workflow

Use this skill for the local Android workflow only. The deliverable is a PNG that visibly shows the Free Fire game, not a splash screen, black loading frame, launcher, browser, or account page.

## Control and safety boundaries

- Treat ADB as the Android control proof. First verify `adb devices` reports a device in state `device`; iPhone Mirroring, UU Remote, or a remote-desktop window is not evidence that the Android phone is controllable.
- Device serials, installed packages, login state, and game state are time-sensitive. Discover them on every run; do not hard-code the serial from an earlier run.
- This workflow launches the selected package and captures the screen only. Do not tap Guest, Facebook, More, Logout, or any external login page; do not type credentials, accept unexpected permissions or terms, create an account, or upload the image.
- If Chrome/Facebook, an account chooser, a permission prompt, or a legal/age confirmation appears, stop and report the exact state. Do not work around it automatically.

## Run the helper

From the project root:

```bash
bash .agents/skills/freefire-screenshot/scripts/capture_freefire_screenshot.sh \
  --variant max \
  --out /absolute/path/freefire-max.png
```

Use `--variant standard` for the regular Free Fire package. If more than one ADB device is online, pass the exact `--serial <serial>` after inspecting `adb devices`; never guess between devices.

The helper performs this sequence:

1. Resolve `adb` and verify the requested device is online.
2. Verify the selected package is installed (`com.dts.freefiremax` for MAX, `com.dts.freefireth` for standard).
3. Launch it with the Android launcher intent.
4. Poll the resumed activity until the selected package is foreground, then wait for the configurable settle period. The first frame can be black or a resource-loading screen and must not be handed off.
5. Capture with `adb exec-out screencap -p`, validate that the output is a non-empty PNG, and re-read the foreground activity.

The script's `foreground` check is necessary but not sufficient: visually inspect the saved PNG with `view_image` or an equivalent image preview. If it is black, still loading, the launcher, or an external page, wait and capture again; do not report it as an in-game screenshot.

## Failure handling

- No device, an offline/unauthorized device, multiple devices without `--serial`, or a missing package: stop with the diagnostic; do not change device configuration.
- A black frame after launch: increase `--settle-seconds` and retry the capture. Do not use a Mac mirror as a substitute for ADB evidence.
- A login/account/permission/browser screen: stop before any input. The user must handle credentials, permissions, or agreements themselves unless they explicitly request and authorize that separate action.

## Known package/activity facts

- Regular Free Fire: package `com.dts.freefireth`.
- Free Fire MAX: package `com.dts.freefiremax`.
- Both builds observed in this project use the activity component suffix `com.dts.freefireth.FFMainActivity`; always verify the live foreground activity rather than assuming it.
