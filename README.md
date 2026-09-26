# studybible2

A new Flutter project.

## Local macOS debug build with Xcode 27

The project still declares macOS 10.15 support, but Xcode 27 only accepts
deployment targets of macOS 12 or newer. To build the current code locally
without changing that product policy, run:

```sh
./tool/build_macos_debug_xcode27.sh
```

The script applies macOS 12 only to that build invocation, including the
Runner, Flutter Assemble, and CocoaPods targets. It does not launch the app.
The resulting local debug app is:

```text
build/macos/DerivedData/Build/Products/Debug/Biblical Heritage.app
```

That artifact requires macOS 12 or later. A normal `flutter build macos` on
Xcode 27 will continue to reject the declared 10.15 target; use an older
compatible Xcode when producing a true 10.15-compatible artifact.

For the usual interactive debug workflow (terminal logs, Flutter attachment,
and hot reload), close any already-running Biblical Heritage instance and run:

```sh
./tool/run_macos_debug_xcode27.sh
```

This builds first with the same local-only macOS 12 override, starts that exact
artifact, and runs `flutter attach -d macos`. Stopping the wrapper also stops
the app it launched. Unlike `dlbr` (`flutter run -d macos`), it does not ask
Flutter's Xcode build step to accept the unsupported 10.15 target.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
