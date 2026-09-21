#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_dir="$project_dir/build/PRune.app"
legacy_app_dir="$project_dir/build/Pull Lens.app"
binary_path="$project_dir/.build/debug/PRune"

if [ ! -x "$binary_path" ]; then
  echo "Missing compiled binary: $binary_path" >&2
  echo "Run swift build first." >&2
  exit 1
fi

rm -rf "$app_dir" "$legacy_app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_path" "$app_dir/Contents/MacOS/PRune"
cp "$project_dir/AppBundle/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/AppBundle/PkgInfo" "$app_dir/Contents/PkgInfo"
cp "$project_dir/AppBundle/Resources/PRune.icns" "$app_dir/Contents/Resources/PRune.icns"
chmod +x "$app_dir/Contents/MacOS/PRune"
codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
