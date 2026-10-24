#!/usr/bin/env bash
# Sequential full-flow benchmark: for each round and size, upload to src, wait for the file to land in approved.
# Usage: benchmark.sh <suffix> <rounds> <out.csv>
set -u
SUFFIX=$1; ROUNDS=$2; OUT=$3
REGION=ap-southeast-7
SRC=poc-s3-guardduty-src-$SUFFIX
APPROVED=poc-s3-guardduty-approved-$SUFFIX
SIZES="10 30 50 100 150 200 300 500"
DIR=$(mktemp -d)

for s in $SIZES; do dd if=/dev/urandom of="$DIR/f_${s}mb.bin" bs=1m count=$s 2>/dev/null; done

echo "round,size_mb,key,upload_start,upload_done,approved_seen" > "$OUT"
for r in $(seq 1 "$ROUNDS"); do
  for s in $SIZES; do
    key="r${r}_${s}mb.bin"
    t0=$(date +%s)
    aws s3 cp "$DIR/f_${s}mb.bin" "s3://$SRC/$key" --region $REGION --only-show-errors
    t1=$(date +%s)
    until aws s3api head-object --bucket "$APPROVED" --key "$key" --region $REGION >/dev/null 2>&1; do
      sleep 1
      if [ $(( $(date +%s) - t1 )) -gt 900 ]; then echo "TIMEOUT $key" >&2; break; fi
    done
    t2=$(date +%s)
    echo "$r,$s,$key,$t0,$t1,$t2" >> "$OUT"
    echo "r$r ${s}MB: upload $((t1-t0))s, upload->approved $((t2-t1))s"
  done
done
rm -rf "$DIR"
echo DONE
