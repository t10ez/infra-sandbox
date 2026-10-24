# poc-kms-vault

Envelope-encryption and signing service on AWS KMS. API Gateway (HTTP API) -> Lambda (python3.12) -> KMS + DynamoDB.
Tested locally against [floci](https://github.com/floci-io/floci); the same Terraform targets real AWS with `-var endpoint= -var lambda_kms_endpoint=`.

## API

| Route | KMS call | Notes |
|---|---|---|
| `POST /encrypt` `{tenant, record_id, plaintext}` | `GenerateDataKey` | AES-256-GCM locally, encrypted data key stored with the ciphertext |
| `POST /decrypt` `{tenant, id}` | `Decrypt` | tenant is part of the encryption context, a wrong tenant is refused |
| `POST /rotate/{id}` `{tenant}` | `ReEncrypt` | data key re-wrapped without exposing plaintext |
| `POST /sign` `{message}`, `POST /verify` `{message, signature}` | `Sign` / `Verify` | `ECC_NIST_P256`, ECDSA_SHA_256 |

Keys: `alias/vault-data` (tenant `default`), `alias/vault-tenant-a`, `alias/vault-tenant-b`, `alias/vault-sign`.
Rotation is on for symmetric keys, `deletion_window_in_days = 7`. The Lambda role gets only the actions it needs per key.

## Run

```bash
floci start && floci wait
scripts/build.sh arm64                       # handler + cryptography wheel (match the Docker host arch)
terraform -chdir=terraform init && terraform -chdir=terraform apply
scripts/test_suite.sh
python3 scripts/benchmark.py "$(terraform -chdir=terraform output -raw api_id)" 30
terraform -chdir=terraform destroy && floci stop
```

Invoke URL on floci: `http://<api_id>.execute-api.localhost.floci.io:4566/<route>`.

## Results (floci 1.7.0, Apple Silicon, n=30)

`scripts/test_suite.sh`: 10/10 pass (round trip, wrong encryption context, rotate then decrypt, disabled key, sign/verify/tamper).

| Payload | Op | Round trip median / p95 (ms) | KMS call (ms) | AES-GCM (ms) |
|---|---|---|---|---|
| 1 KB | encrypt | 8.3 / 10.3 | 1.9 | 0.00 |
| 1 KB | decrypt | 9.2 / 13.3 | 1.7 | 0.00 |
| 100 KB | encrypt | 12.8 / 22.8 | 2.0 | 0.02 |
| 100 KB | decrypt | 12.1 / 17.4 | 1.8 | 0.03 |
| 250 KB | encrypt | 18.2 / 24.6 | 2.2 | 0.06 |
| 250 KB | decrypt | 16.8 / 21.2 | 2.0 | 0.05 |

## Caveats

- **Latency numbers measure the emulator, not AWS KMS.** Real KMS calls over the network are typically tens of ms, so re-measure on AWS before drawing conclusions. The shape (one KMS call per operation, size only affects the local AES step) is what carries over.
- **Payload limit about 290 KB:** a 1 MB payload failed with `ValidationException: Item size has exceeded the maximum allowed size` because DynamoDB items are capped at 400 KB (base64 adds a third). Larger payloads need the ciphertext in S3 with only the encrypted data key in DynamoDB.
- **Not tested:** IAM and key-policy enforcement (tenant A role denied on tenant B key) and CloudTrail auditing. Isolation here comes from the encryption context only. Verify the role policy on real AWS.
- Pricing for ap-southeast-7 was not checked. Keys cost about $1 per month each and stay billable during the 7-day deletion window.
