#!/bin/bash
set -euo pipefail
R="$(cd "$(dirname "$0")" && pwd)"
rsync -a --delete --exclude .DS_Store --exclude '*.app' --exclude '*.bak*' --exclude .git --exclude README.md --exclude .gitignore --exclude sync-from-desktop.sh "$HOME/Desktop/插件:软件-Google/番茄钟项目/" "$R/"
cd "$R" && git status --short
