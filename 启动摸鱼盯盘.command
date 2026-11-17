#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ -d "/Applications/摸鱼盯盘.app" ]]; then
    open "/Applications/摸鱼盯盘.app"
    exit 0
fi
if [[ ! -d "dist/摸鱼盯盘.app" ]]; then
    bash scripts/build.sh --current-arch
fi
open "dist/摸鱼盯盘.app"
