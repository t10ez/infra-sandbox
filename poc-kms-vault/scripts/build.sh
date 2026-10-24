#!/usr/bin/env bash
# Build the Lambda bundle: handler.py + cryptography wheel for the Lambda architecture.
# Usage: build.sh [arm64|x86_64]   (default arm64; boto3 ships with the Lambda runtime)
set -euo pipefail
ARCH=${1:-arm64}
case "$ARCH" in
  arm64)  PLAT=manylinux2014_aarch64 ;;
  x86_64) PLAT=manylinux2014_x86_64 ;;
  *) echo "unknown arch $ARCH" >&2; exit 1 ;;
esac
ROOT=$(cd "$(dirname "$0")/.." && pwd)
rm -rf "$ROOT/build"; mkdir -p "$ROOT/build"
python3 -m pip install --quiet --target "$ROOT/build" --platform "$PLAT" \
  --python-version 3.12 --implementation cp --only-binary=:all: cryptography
cp "$ROOT/scripts/handler.py" "$ROOT/build/"
echo "built $ROOT/build ($ARCH)"
