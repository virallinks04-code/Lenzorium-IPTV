#!/usr/bin/env bash
# Generates the Flutter platform folders (Gradle, Windows runner) around the
# Lenzorium sources. Existing files (our AndroidManifest, MainActivity) are kept.
set -e
cd "$(dirname "$0")"
flutter create . --org com.lenzorium --project-name lenzorium_player --platforms=android,windows
rm -f test/widget_test.dart
flutter pub get
echo "Done. Try: flutter run -d windows   or   flutter run -d <android-device>"
