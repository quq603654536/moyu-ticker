#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUILD="$ROOT/.build/checks"
mkdir -p "$BUILD"
xcrun swiftc -swift-version 5 -parse-as-library -emit-module -emit-library -static \
    -module-name MarketCore Sources/MarketCore/*.swift \
    -emit-module-path "$BUILD/MarketCore.swiftmodule" -o "$BUILD/libMarketCore.a" \
    -module-cache-path "$BUILD/cache"
xcrun swiftc -swift-version 5 -parse-as-library -I "$BUILD" \
    Tests/MarketCoreTests/MarketParserTests.swift "$BUILD/libMarketCore.a" \
    -o "$BUILD/MarketCoreTests" -module-cache-path "$BUILD/cache"
"$BUILD/MarketCoreTests" "$ROOT/Tests/MarketCoreTests/Fixtures" "${@}"

xcrun swiftc -swift-version 5 -parse-as-library -I "$BUILD" \
    Tests/MarketCoreTests/RequestLogTests.swift "$BUILD/libMarketCore.a" \
    -o "$BUILD/RequestLogTests" -module-cache-path "$BUILD/cache"
"$BUILD/RequestLogTests" "$ROOT/Tests/MarketCoreTests/Fixtures"
