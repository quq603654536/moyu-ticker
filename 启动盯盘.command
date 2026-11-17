#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ -d "/Applications/盯盘.app" ]]; then
    open "/Applications/盯盘.app"
    exit 0
fi
if [[ ! -d "dist/盯盘.app" ]]; then
    bash scripts/build.sh --current-arch
fi
open "dist/盯盘.app"
