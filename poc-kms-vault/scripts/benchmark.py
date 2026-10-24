"""Latency of encrypt/decrypt by payload size. Usage: benchmark.py <api_id> [n]
Reports client round trip plus the KMS and AES-GCM time measured inside the Lambda.
Against floci the KMS numbers measure the emulator, not real AWS KMS."""
import json, statistics as st, sys, time, urllib.request

api, n = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 30
url = f"http://{api}.execute-api.localhost.floci.io:4566"


def post(path, body):
    req = urllib.request.Request(url + path, json.dumps(body).encode(), {"content-type": "application/json"})
    t = time.perf_counter()
    out = json.load(urllib.request.urlopen(req, timeout=60))
    return out, (time.perf_counter() - t) * 1000


def med(xs):
    return st.median(xs)


print("size,op,n,rtt_med_ms,rtt_p95_ms,kms_med_ms,aes_med_ms")
for label, size in (("1KB", 1024), ("100KB", 100 * 1024), ("250KB", 250 * 1024)):
    pt = "x" * size
    post("/encrypt", {"tenant": "a", "record_id": f"warm-{label}", "plaintext": pt})  # warm Lambda
    for op in ("encrypt", "decrypt"):
        rtt, kms, aes = [], [], []
        for i in range(n):
            rid = f"b-{label}-{op}-{i}"
            if op == "encrypt":
                out, ms = post("/encrypt", {"tenant": "a", "record_id": rid, "plaintext": pt})
            else:
                post("/encrypt", {"tenant": "a", "record_id": rid, "plaintext": pt})
                out, ms = post("/decrypt", {"tenant": "a", "id": rid})
            rtt.append(ms); kms.append(out["kms_ms"]); aes.append(out["aes_ms"])
        p95 = sorted(rtt)[int(0.95 * (n - 1))]
        print(f"{label},{op},{n},{med(rtt):.1f},{p95:.1f},{med(kms):.1f},{med(aes):.2f}")
