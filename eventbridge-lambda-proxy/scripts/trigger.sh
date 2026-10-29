#!/usr/bin/env bash
# Send an on-demand "Report Requested" event. Usage: trigger.sh <report_type> [region]
set -euo pipefail
type="${1:?usage: trigger.sh <report_type> [region]}"
region="${2:-ap-southeast-1}"
source_name="${EVENT_SOURCE:-poc.reports}"
aws events put-events --region "$region" --entries "$(cat <<JSON
[{"Source":"$source_name","DetailType":"Report Requested","Detail":"{\"report_type\":\"$type\"}"}]
JSON
)"
