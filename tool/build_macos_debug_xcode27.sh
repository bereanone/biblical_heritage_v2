#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
derived_data="$project_root/build/macos/DerivedData"
app_path="$derived_data/Build/Products/Debug/Biblical Heritage.app"

cd "$project_root"

# Xcode 27 no longer accepts the project's declared macOS 10.15 floor. Keep
# that product policy intact and raise the floor only for this local build.
# Passing the setting to xcodebuild (rather than exporting it around
# `flutter build`) overrides Runner, Flutter Assemble, and every CocoaPods
# target in the workspace for this invocation.
xcodebuild \
  -workspace macos/Runner.xcworkspace \
  -scheme Runner \
  -configuration Debug \
  -derivedDataPath "$derived_data" \
  MACOSX_DEPLOYMENT_TARGET=12.0 \
  build

if [[ ! -d "$app_path" ]]; then
  print -u2 "Build reported success but the app was not found at: $app_path"
  exit 1
fi

print "Built without launching or changing the project deployment target:"
print "$app_path"
print "This local artifact requires macOS 12 or later."
