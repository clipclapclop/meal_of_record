# meal_of_record

Fast, private, convenient macro tracking.

## Repository

The canonical source and issue tracker are hosted on [Forgejo](https://git.oorangy.com/chad/meal_of_record).

## Documentation

You can view the full project documentation here:  
👉 [Meal of Record Documentation](https://clipclapclop.github.io/meal_of_record/)

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

Updates:
v0.2.0
 Features:
 - Added ability to work in Net Carbs
 - Added portion sharing
 - Added Dumpable Recipe portioning
 - Added Recipe links
 - Better weight smoothing/estimating
 Bugs:
 - Fixed Overview Macro issue
 - Fixed TDEE window inconsistancies
 - Fixed Mananance Calorie drift bug
 - Log multiselect wasn't properly unselecting in screen change
 - 6 months weight graph didn't show data points
 - OFF Log Queue replacing each other
 - Fill to Target not working if queue isn't empty
v0.1.1
- various little bugs
v0.1.0
- initial release

## Install to phone
# 1. Build the release APK
flutter build apk --release

# 2. Get the device list
> adb devices

List of devices attached
emulator-5554   device
R58M123ABC      device

# 3. Install the release APK to your connected device
adb -s R58M123ABC install -r build/app/outputs/flutter-apk/app-release.apk