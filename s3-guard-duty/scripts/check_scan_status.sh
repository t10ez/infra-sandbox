#!/usr/bin/env bash
# Check GuardDuty Malware Protection scan tags on S3 objects
# Usage: ./check_scan_status.sh <bucket-name>

set -euo pipefail

BUCKET="${1:?Usage: $0 <bucket-name>}"
REGION="${AWS_REGION:-ap-southeast-1}"

TAG_KEY="GuardDutyMalwareScanStatus"

check_object() {
  local key="$1"
  local tags
  tags=$(aws s3api get-object-tagging \
    --bucket "$BUCKET" \
    --key "$key" \
    --region "$REGION" \
    --output json 2>/dev/null || echo '{"TagSet":[]}')

  local status
  status=$(echo "$tags" | python3 -c "
import sys, json
data = json.load(sys.stdin)
tags = {t['Key']: t['Value'] for t in data.get('TagSet', [])}
print(tags.get('GuardDutyMalwareScanStatus', 'NOT_SCANNED_YET'))
")

  case "$status" in
    "THREATS_FOUND")    icon="🚨" ;;
    "NO_THREATS_FOUND") icon="✅" ;;
    "UNSUPPORTED")      icon="⚠️ " ;;
    "ACCESS_DENIED")    icon="🔒" ;;
    "FAILED")           icon="❌" ;;
    "NOT_SCANNED_YET")  icon="⏳" ;;
    *)                  icon="❓" ;;
  esac

  printf "  %s  %-30s  %s\n" "$icon" "$key" "$status"
}

echo ""
echo "=== GuardDuty Malware Scan Status for s3://$BUCKET ==="
echo ""
printf "  %-4s  %-30s  %s\n" "    " "Object Key" "Scan Status"
printf "  %-4s  %-30s  %s\n" "----" "------------------------------" "-----------"

check_object "eicar_test.txt"
check_object "clean_file.txt"
check_object "fake.exe"

echo ""
echo "Tag key:  GuardDutyMalwareScanStatus"
echo "Possible values:"
echo "  THREATS_FOUND    — malware detected"
echo "  NO_THREATS_FOUND — clean"
echo "  UNSUPPORTED      — file type not supported"
echo "  ACCESS_DENIED    — GuardDuty can't read the object"
echo "  FAILED           — scan error"
echo "  NOT_SCANNED_YET  — scan pending (wait 1-2 min)"
echo ""
echo "Check GuardDuty findings:"
echo "  aws guardduty list-findings \\"
echo "    --detector-id \$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text) \\"
echo "    --region $REGION"
echo ""
echo "Watch CloudWatch logs:"
echo "  aws logs tail /guardduty/poc-s3-guardduty/findings --follow --region $REGION"
