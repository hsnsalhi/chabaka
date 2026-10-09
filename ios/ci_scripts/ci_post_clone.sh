#!/bin/sh
# Xcode Cloud : installe Flutter et prépare le projet iOS après le clone.
# Doc : https://docs.flutter.dev/deployment/ios#xcode-cloud
set -e

FLUTTER_VERSION="3.41.9"

echo "==> Installation de Flutter $FLUTTER_VERSION"
git clone --depth 1 -b "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$HOME/flutter"
export PATH="$PATH:$HOME/flutter/bin"
flutter --version
flutter precache --ios

cd "$CI_PRIMARY_REPOSITORY_PATH"

# Numéro de build = numéro de build Xcode Cloud, pour que chaque upload
# TestFlight soit strictement croissant (pubspec : version: X.Y.Z+N).
if [ -n "$CI_BUILD_NUMBER" ]; then
  echo "==> Numéro de build : $CI_BUILD_NUMBER"
  sed -i '' "s/^version: \([0-9.]*\)+.*/version: \1+$CI_BUILD_NUMBER/" pubspec.yaml
  grep '^version:' pubspec.yaml
fi

echo "==> flutter pub get"
flutter pub get

echo "==> CocoaPods"
HOMEBREW_NO_AUTO_UPDATE=1 brew install cocoapods
cd ios && pod install

exit 0
