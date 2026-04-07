# MacStartupSound

MacStartupSound is a macOS menu bar app that detects a MacBook lid opening gesture and plays a startup-style sound.

## Features

- Reads the built-in lid angle sensor via IOKit HID.
- Detects rapid opening gestures using threshold + timing logic.
- Plays bundled `startup_sound.wav` on trigger.
- Supports custom sound files (`.mp3`, `.m4a`, `.wav`, `.aiff`).
- Lets you toggle sound on/off from the menu bar.

## Requirements

- macOS
- Xcode
- A MacBook with a compatible lid angle sensor

## Run locally

1. Open `MacStartupSound.xcodeproj` in Xcode.
2. Choose a scheme (for example `MacWindowsStartupSound`).
3. Build and run.
4. Use the menu bar icon to manage sound settings.

## Project layout

- `LidAngleSensor/` - Objective-C app source.
- `MacStartupSound.xcodeproj/` - Xcode project and schemes.
