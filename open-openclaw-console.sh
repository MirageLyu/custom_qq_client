#!/bin/bash
set -e

URL="http://localhost:18789"

if command -v open >/dev/null 2>&1; then
  open "$URL"
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$URL"
else
  echo "请手动打开: $URL"
fi
