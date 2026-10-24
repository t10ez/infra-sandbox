import json
import logging
import os
from urllib.parse import unquote_plus
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")

QUARANTINE_BUCKET = os.environ["QUARANTINE_BUCKET"]
APPROVED_BUCKET = os.environ["APPROVED_BUCKET"]


def handler(event, context):
    detail = event.get("detail", {})
    bucket = detail.get("bucket", {}).get("name")
    obj = detail.get("object", {})
    key = unquote_plus(obj.get("key", ""))
    version_id = obj.get("version-id")

    filename = key.split("/")[-1]
    path = "/".join(key.split("/")[:-1]) if "/" in key else "/"

    # read scan status tag
    scan_status = "UNKNOWN"
    threat_detail = None
    try:
        kwargs = {"Bucket": bucket, "Key": key}
        if version_id:
            kwargs["VersionId"] = version_id
        tag_resp = s3.get_object_tagging(**kwargs)
        tags = {t["Key"]: t["Value"] for t in tag_resp.get("TagSet", [])}
        scan_status = tags.get("GuardDutyMalwareScanStatus", "NOT_TAGGED")
        threat_detail = tags.get("GuardDutyMalwareScanThreatName")
    except Exception as e:
        logger.error(f"get_object_tagging failed: {e}")
        scan_status = "TAG_FETCH_ERROR"

    # route file
    dest_bucket = QUARANTINE_BUCKET if scan_status == "THREATS_FOUND" else APPROVED_BUCKET
    action = "quarantined" if scan_status == "THREATS_FOUND" else "approved"

    copy_error = None
    try:
        copy_source = {"Bucket": bucket, "Key": key}
        if version_id:
            copy_source["VersionId"] = version_id
        s3.copy_object(
            CopySource=copy_source,
            Bucket=dest_bucket,
            Key=key,
            TaggingDirective="COPY",
        )
        # delete from scan bucket after successful copy
        del_kwargs = {"Bucket": bucket, "Key": key}
        if version_id:
            del_kwargs["VersionId"] = version_id
        s3.delete_object(**del_kwargs)
    except Exception as e:
        copy_error = str(e)
        logger.error(f"move failed: {e}")

    log_entry = {
        "action": action,
        "scan_status": scan_status,
        "filename": filename,
        "path": path,
        "source_bucket": bucket,
        "dest_bucket": dest_bucket,
        "version_id": version_id,
        "threat_detail": threat_detail,
        "error": copy_error,
        "time": event.get("time"),
        "region": event.get("region"),
    }

    logger.info(json.dumps(log_entry))
    return {"statusCode": 200, "body": log_entry}
