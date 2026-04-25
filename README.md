# Banuba External Camera Demo (Route B)

This project is a minimal UIKit demo that:

- Captures frames from **external UVC camera** (iPadOS 17+) or built-in cameras using `AVCaptureSession`.
- Feeds frames into **Banuba Face AR SDK Player API** via `Stream` + `BNBFrameData`.
- Renders output in real time to an `EffectPlayerView`.
- Lets you toggle an "aging-style" effect (defaults to `TrollGrandma` if you copy it into `/effects`).

## Quick Start

1) Install CocoaPods deps

```bash
pod install
```

2) Open workspace

- Open `BanubaExternalCamDemo.xcworkspace` (NOT `.xcodeproj`).

3) Add your Banuba client token

- Edit `BanubaExternalCamDemo/BanubaClientToken.swift` and paste your token.

4) (Optional) Add an effect

- Copy any Banuba effect folder into `BanubaExternalCamDemo/effects/`.
- The demo button toggles `TrollGrandma` by default.

5) Run on iPad

- Plug an external UVC camera (USB-C) if you want to test external capture.
- Select `External` segment in the top bar.

## Notes

- The app runs even without effects; it starts with an empty effect (passthrough).
- Orientation is configured for iPad landscape usage.
