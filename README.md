# infra-sandbox

Infrastructure and cloud POC series: AWS, security, cloud-native experiments.

## POCs

| Directory | Question | Tested on |
|---|---|---|
| [poc-s3-guard-duty](./poc-s3-guard-duty) | How long does a file take from upload to quarantine or approved, and what dominates? | AWS |
| [poc-kms-vault](./poc-kms-vault) | Can one small service do per-tenant envelope encryption, rotation and signing on KMS? | floci |

## Conventions

- Every POC README follows [docs/POC_README_TEMPLATE.md](./docs/POC_README_TEMPLATE.md), so POCs compare side by side.
- Every POC ends with a teardown step. Nothing billable stays up.
- Numbers are measured. Estimates are labelled as estimates.
- No state files, secrets or build output in git.
