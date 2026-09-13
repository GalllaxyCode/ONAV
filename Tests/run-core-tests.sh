#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/tests
swiftc -swift-version 5 -D DEBUG Sources/Shared.swift Sources/GameCore.swift Tests/CoreTests.swift -o build/tests/CoreTests
build/tests/CoreTests
