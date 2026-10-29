#!/usr/bin/env bash
# Build both Lambda binaries for provided.al2023 on arm64.
# Terraform zips build/<name>/bootstrap, so run this before every apply.
set -euo pipefail
cd "$(dirname "$0")/../app"
for name in proxy echo; do
  mkdir -p "../build/$name"
  CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
    go build -tags lambda.norpc -trimpath -ldflags="-s -w" \
    -o "../build/$name/bootstrap" "./cmd/$name"
  echo "built build/$name/bootstrap ($(du -h "../build/$name/bootstrap" | cut -f1))"
done
