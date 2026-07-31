#!/bin/bash

set -euo pipefail

app_path=${1:-}
if [[ -z "$app_path" || ! -d "$app_path" ]]; then
  echo "Usage: $0 /path/to/Runner.app" >&2
  exit 2
fi

plist_buddy=/usr/libexec/PlistBuddy
app_plist="$app_path/Info.plist"
app_id=$($plist_buddy -c 'Print :CFBundleIdentifier' "$app_plist")
failed=0
records=$(mktemp)
trap 'rm -f "$records"' EXIT

print_bundle() {
  local bundle=$1
  local plist="$bundle/Info.plist"
  local identifier executable package_type

  if [[ ! -f "$plist" ]]; then
    echo "ERROR: missing Info.plist: $bundle" >&2
    failed=1
    return
  fi

  identifier=$($plist_buddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || true)
  executable=$($plist_buddy -c 'Print :CFBundleExecutable' "$plist" 2>/dev/null || true)
  package_type=$($plist_buddy -c 'Print :CFBundlePackageType' "$plist" 2>/dev/null || true)

  printf '%s\t%s\t%s\t%s\n' "$bundle" "$identifier" "$executable" "$package_type"

  if [[ -z "$identifier" ]]; then
    echo "ERROR: empty CFBundleIdentifier: $bundle" >&2
    failed=1
    return
  fi

  printf '%s\t%s\n' "$identifier" "$bundle" >> "$records"

  if [[ "$bundle" == *.framework && "$identifier" == "$app_id" ]]; then
    echo "ERROR: framework reuses app identifier $app_id: $bundle" >&2
    failed=1
  fi
}

echo -e 'Bundle path\tCFBundleIdentifier\tCFBundleExecutable\tCFBundlePackageType'
print_bundle "$app_path"

while IFS= read -r bundle; do
  print_bundle "$bundle"
done < <(find "$app_path" -mindepth 1 -type d \( -name '*.framework' -o -name '*.appex' -o -name '*.bundle' \) -print | sort)

while IFS=$'\t' read -r count identifier; do
  if (( count > 1 )); then
    echo "ERROR: duplicate CFBundleIdentifier $identifier:" >&2
    awk -F '\t' -v id="$identifier" '$1 == id { print "  " $2 }' "$records" >&2
    failed=1
  fi
done < <(cut -f1 "$records" | sort | uniq -c | awk '{ count=$1; $1=""; sub(/^ /, ""); print count "\t" $0 }')

if (( failed != 0 )); then
  exit 1
fi

echo "PASS: all embedded bundle identifiers are nonempty and unique."
