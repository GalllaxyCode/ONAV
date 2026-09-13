#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/hollow-signal-audio-save.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
swiftc -O -D DEBUG -swift-version 5 -target "$(uname -m)-apple-macosx12.0" \
    "$project_dir/Sources/Shared.swift" \
    "$project_dir/Sources/AudioSystem.swift" \
    "$project_dir/Sources/SaveStore.swift" \
    "$project_dir/Sources/LoreCatalog.swift" \
    "$project_dir/Tests/AudioSaveTests.swift" \
    -o "$build_dir/AudioSaveTests"
"$build_dir/AudioSaveTests" "$@"
