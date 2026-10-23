#!/usr/bin/env bash
# Upload EICAR test file + clean file to S3 to test GuardDuty Malware Protection
# Usage: ./upload_test.sh <bucket-name>

set -euo pipefail

BUCKET="${1:?Usage: $0 <bucket-name>}"
REGION="${AWS_REGION:-ap-southeast-1}"

# EICAR Anti-Malware Test File (standard, harmless, universally detected by AV)
EICAR='X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*'

echo "=== GuardDuty S3 Malware Protection POC ==="
echo "Bucket: $BUCKET"
echo ""

# ── 1. Upload EICAR test file ──────────────────────────────────────────────────
echo "[1] Uploading EICAR test file..."
echo "$EICAR" > /tmp/eicar_test.txt
aws s3 cp /tmp/eicar_test.txt "s3://$BUCKET/eicar_test.txt" \
  --region "$REGION" \
  --metadata "uploaded-by=guardduty-poc,purpose=malware-test"
echo "    Uploaded: s3://$BUCKET/eicar_test.txt"

# ── 2. Upload clean file ───────────────────────────────────────────────────────
echo ""
echo "[2] Uploading clean file..."
echo "This is a clean file - no malware here." > /tmp/clean_file.txt
aws s3 cp /tmp/clean_file.txt "s3://$BUCKET/clean_file.txt" \
  --region "$REGION" \
  --metadata "uploaded-by=guardduty-poc,purpose=clean-test"
echo "    Uploaded: s3://$BUCKET/clean_file.txt"

# ── 3. Upload a fake .exe (test unsupported/executable handling) ───────────────
echo ""
echo "[3] Uploading fake .exe file (test executable detection)..."
printf '\x4D\x5A' > /tmp/fake.exe  # MZ header (Windows PE signature)
echo " fake exe content for poc" >> /tmp/fake.exe
aws s3 cp /tmp/fake.exe "s3://$BUCKET/fake.exe" \
  --region "$REGION" \
  --metadata "uploaded-by=guardduty-poc,purpose=exe-test"
echo "    Uploaded: s3://$BUCKET/fake.exe"

echo ""
echo "=== Files uploaded. GuardDuty will scan within ~1-2 minutes ==="
echo ""
echo "Run this script to check scan tags:"
echo ""
echo "  ./check_scan_status.sh $BUCKET"
