#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
app_path="$project_root/build/macos/DerivedData/Build/Products/Debug/Biblical Heritage.app"
executable="$app_path/Contents/MacOS/Biblical Heritage"

"$script_dir/build_macos_debug_xcode27.sh"

if [[ ! -x "$executable" ]]; then
  print -u2 "Debug executable was not found at: $executable"
  exit 1
fi

# Start the just-built debug executable from this terminal so its stdout and
# VM-service announcement remain visible, then attach Flutter for hot reload.
# This uses the app's normal bundle/container, exactly like `flutter run`.
"$executable" &
app_pid=$!

cleanup() {
  if kill -0 "$app_pid" 2>/dev/null; then
    kill "$app_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

sleep 2
cd "$project_root"
flutter attach -d macos
