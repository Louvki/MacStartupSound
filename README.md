# MacStartupSound

Inspired by [MacMonium](https://github.com/yatinj30/MacMonium) MacStartupSound is a macOS menu bar app that detects a MacBook lid opening gesture and plays a sound of your choice.

## How to run

Compile the project using XCode and then run the app. You can move the app to the "Applications" folder and then add the app to your "Login items" so it starts up when you boot your mac. 


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
2. Build and run.
3. Use the menu bar icon to manage sound settings.

## Project layout

- `LidAngleSensor/` - Objective-C app source.
- `MacStartupSound.xcodeproj/` - Xcode project and schemes.
