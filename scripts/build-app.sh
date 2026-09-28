#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sdk_path=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk

if [ ! -d "$sdk_path" ]; then
  echo "Missing macOS SDK: $sdk_path" >&2
  exit 1
fi

cd "$project_dir"
SDKROOT="$sdk_path" swift build --sdk "$sdk_path"
"$project_dir/scripts/package-app.sh"
