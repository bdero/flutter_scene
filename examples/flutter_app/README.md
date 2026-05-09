# Scene Examples App

This is a Flutter App that contains several Flutter Scene usage examples.

The app is just a simple harness with a dropdown that selects an example widget.

## Running

The platform stubs (`macos/`, `ios/`, `android/`, `linux/`, `windows/`) are gitignored — generate them once on a fresh clone:

```sh
flutter create . --platforms=macos,ios,android,linux,windows
```

Then run the app with Flutter GPU enabled:

```sh
flutter run --enable-flutter-gpu --enable-impeller
```

(Add `-d <device>` if multiple devices are connected.)

