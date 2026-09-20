#!/usr/bin/env bash
set -euo pipefail

# Generate the Flutter Android platform files without overwriting lib/ or pubspec.yaml.
flutter create --platforms=android .

echo "Android platform files generated."
echo "Run: flutter pub get && flutter run -d android"
