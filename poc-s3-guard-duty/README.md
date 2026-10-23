# poc-s3-guard-duty

AWS S3 + GuardDuty Malware Protection POC with automated quarantine/approval flow.

## Architecture

```
S3(src) --[SRR]--> S3(scan) --> GuardDuty --> EventBridge --> Lambda
                                                                  |
                                             +--------------------+--------------------+
                                             |                                         |
                                        S3(quarantine)                          S3(approved)
                                     (THREATS_FOUND)                        (NO_THREATS_FOUND)
```

## Flow

1. Upload file to **source** bucket
2. S3 Same-Region Replication copies to **scan** bucket (~3s)
3. GuardDuty Malware Protection scans the object
4. GuardDuty tags object with `GuardDutyMalwareScanStatus`
5. S3 `Object Tags Added` event fires to EventBridge
6. Lambda reads the tag, moves file to **quarantine** or **approved** bucket

## Duration (ap-southeast-7)

| File size | Total (upload → move) | GuardDuty scan |
|-----------|----------------------|----------------|
| < 1 KB    | ~23s                 | ~18s           |
| 100 MB    | ~36s                 | ~30s           |
| 150 MB    | ~53s                 | ~46s           |

Bottleneck: GuardDuty scan (~80-90% of total time). Lambda execution is ~275ms.

## Deploy

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars

terraform init
terraform apply
```

## Test

```bash
# upload EICAR + clean files to source bucket
bash scripts/upload_test.sh <source-bucket-name>

# watch Lambda logs
aws logs tail /aws/lambda/poc-s3-guardduty-scan-logger --follow --region ap-southeast-7
```

## Requirements

- AWS account with GuardDuty enabled in target region
- Terraform >= 1.5
- AWS CLI + credentials configured
