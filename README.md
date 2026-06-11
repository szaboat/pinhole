# FocusC

FocusC is a native macOS menu-bar utility that dims everything except a
rectangle you select. The clear area remains fully interactive, so mouse,
trackpad, scrolling, and keyboard input continue to work in the application
underneath it.

## Run

Requirements: macOS 12 or newer and Xcode 14 or newer.

```sh
swift run FocusC
```

Drag to select the area to keep visible. Use **Close Focus** or the menu-bar
item to remove the overlay. Choose **Select Focus Area...** to draw a new one.

## Build an application bundle

```sh
./scripts/build-app.sh
open dist/FocusC.app
```

The build script creates a universal application for both Apple Silicon and
Intel Macs and ad-hoc signs it for local use.

## License

FocusC is available under the [MIT License](LICENSE).
