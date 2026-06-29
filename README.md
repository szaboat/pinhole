# Pinhole

Pinhole is a native macOS menu-bar utility that dims everything except a
rectangle you select. The clear area stays fully interactive, so mouse,
trackpad, scrolling, and keyboard input continue to work in the application
underneath it.

[Download the latest release](https://github.com/szaboat/pinhole/releases/latest)
for macOS 12 or newer. The app is not notarized, so macOS may warn before
opening it.

![Pinhole demo](demo.webp)

## Run

Requirements: macOS 12 or newer and Xcode 14 or newer.

```sh
swift run Pinhole
```

Click a window to keep that window visible, or drag to select a custom pinhole.
Use the close button or the menu-bar item to remove the overlay. Choose
**Select Window or Pinhole...** to draw a new one.

## Build an application bundle

```sh
./scripts/build-app.sh
open dist/Pinhole.app
```

The build script creates a universal application for both Apple Silicon and
Intel Macs and ad-hoc signs it for local use.

## License

Pinhole is available under the [MIT License](LICENSE).
