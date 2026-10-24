#!/usr/bin/env bash
# One round, per-stage timing. Usage: benchmark_stages.sh <suffix> <out.csv>
# Stages (client clock, epoch seconds with decimals):
#   t_start  before upload     t_up   upload to src done
#   t_rep    object visible in scan bucket (SRR done)
#   t_tag    GuardDutyMalwareScanStatus tag present (scan done)
#   t_app    object visible in approved bucket (Lambda move done)
set -u
SUFFIX=$1; OUT=$2
REGION=ap-southeast-7
SRC=poc-s3-guardduty-src-$SUFFIX
SCAN=poc-s3-guardduty-scan-$SUFFIX
APPROVED=poc-s3-guardduty-approved-$SUFFIX
SIZES="10 30 50 100 150 200 300 500"
DIR=$(mktemp -d)
now() { python3 -c 'import time;print("%.2f"%time.time())'; }

wait_head() { # bucket key
  local n=0
  until aws s3api head-object --bucket "$1" --key "$2" --region $REGION >/dev/null 2>&1; do
    sleep 0.2; n=$((n+1)); [ $n -gt 4500 ] && return 1
  done
}
wait_tag() { # returns 0 when tag seen, 1 when object vanished first
  local n=0 out rc
  while true; do
    out=$(aws s3api get-object-tagging --bucket "$SCAN" --key "$1" --region $REGION \
      --query "TagSet[?Key=='GuardDutyMalwareScanStatus'].Value" --output text 2>/dev/null); rc=$?
    [ $rc -ne 0 ] && return 1
    [ -n "$out" ] && [ "$out" != "None" ] && return 0
    sleep 0.2; n=$((n+1)); [ $n -gt 4500 ] && return 1
  done
}

for s in $SIZES; do dd if=/dev/urandom of="$DIR/f_${s}mb.bin" bs=1m count=$s 2>/dev/null; done

WKEY="warmup_$(date +%s).bin"; echo "warm-up..."
dd if=/dev/urandom of="$DIR/warm.bin" bs=1m count=2 2>/dev/null
aws s3 cp "$DIR/warm.bin" "s3://$SRC/$WKEY" --region $REGION --only-show-errors
wait_head "$APPROVED" "$WKEY" && echo "warm-up ok"

echo "size_mb,key,t_start,t_up,t_rep,t_tag,t_app" > "$OUT"
for s in $SIZES; do
  key="s_${s}mb.bin"
  t_start=$(now)
  aws s3 cp "$DIR/f_${s}mb.bin" "s3://$SRC/$key" --region $REGION --only-show-errors
  t_up=$(now)
  wait_head "$SCAN" "$key"; t_rep=$(now)
  if wait_tag "$key"; then t_tag=$(now); else t_tag=""; fi
  wait_head "$APPROVED" "$key"; t_app=$(now)
  echo "$s,$key,$t_start,$t_up,$t_rep,$t_tag,$t_app" >> "$OUT"
  echo "${s}MB done: total $(python3 -c "print(round($t_app-$t_up,1))")s"
done
rm -rf "$DIR"
echo DONE
