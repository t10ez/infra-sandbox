"""Envelope encrypt/decrypt latency by payload size. Usage: benchmark.py [n]
Splits each operation into the KMS call and the local AES-GCM step.
Against floci the KMS time measures the emulator, not AWS KMS."""
import os
import statistics as st
import sys
import time

os.environ.setdefault("AWS_ACCESS_KEY_ID", "test")
os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "test")

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

import kms_vault as v

n = int(sys.argv[1]) if len(sys.argv) > 1 else 30
ctx = {"tenant": "a", "record_id": "bench"}


def ms(t0):
    return (time.perf_counter() - t0) * 1000


def p95(xs):
    return sorted(xs)[int(0.95 * (len(xs) - 1))]


print("size,op,n,total_med_ms,total_p95_ms,kms_med_ms,aes_med_ms")
for label, size in (("1KB", 1 << 10), ("100KB", 100 << 10), ("1MB", 1 << 20), ("10MB", 10 << 20)):
    data = os.urandom(size)
    v.decrypt(v.encrypt("a", data, ctx), ctx)  # warm up
    rows = {"encrypt": ([], [], []), "decrypt": ([], [], [])}
    for _ in range(n):
        t0 = time.perf_counter()
        dk = v.kms.generate_data_key(KeyId=v.TENANT_KEYS["a"], KeySpec="AES_256", EncryptionContext=ctx)
        k = ms(t0)
        nonce = os.urandom(12)
        t1 = time.perf_counter()
        ct = AESGCM(dk["Plaintext"]).encrypt(nonce, data, v._aad(ctx))
        a = ms(t1)
        rows["encrypt"][0].append(k + a); rows["encrypt"][1].append(k); rows["encrypt"][2].append(a)

        t0 = time.perf_counter()
        pk = v.kms.decrypt(CiphertextBlob=dk["CiphertextBlob"], EncryptionContext=ctx)
        k = ms(t0)
        t1 = time.perf_counter()
        AESGCM(pk["Plaintext"]).decrypt(nonce, ct, v._aad(ctx))
        a = ms(t1)
        rows["decrypt"][0].append(k + a); rows["decrypt"][1].append(k); rows["decrypt"][2].append(a)
    for op, (tot, kms_t, aes_t) in rows.items():
        print(f"{label},{op},{n},{st.median(tot):.1f},{p95(tot):.1f},{st.median(kms_t):.1f},{st.median(aes_t):.2f}")
