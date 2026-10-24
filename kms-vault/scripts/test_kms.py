"""Functional tests against floci (or AWS). Usage: AWS_ENDPOINT_URL=http://localhost:4566 python3 test_kms.py"""
import os
import sys

os.environ.setdefault("AWS_ACCESS_KEY_ID", "test")
os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "test")

from botocore.exceptions import ClientError
from cryptography.exceptions import InvalidTag

import kms_vault as v

results = []


def case(name):
    def wrap(fn):
        try:
            detail = fn()
            results.append((name, True, detail or ""))
        except Exception as e:  # noqa: BLE001 - report any failure
            results.append((name, False, f"{type(e).__name__}: {e}"))
        return fn
    return wrap


def error_code(fn):
    try:
        fn()
    except ClientError as e:
        return e.response["Error"]["Code"]
    return None


CTX = {"tenant": "a", "record_id": "t1"}


@case("1  round trip returns the original plaintext")
def _():
    rec = v.encrypt("a", b"secret-123", CTX)
    assert v.decrypt(rec, CTX) == b"secret-123"


@case("1  10 MB payload round trip")
def _():
    data = os.urandom(10 * 1024 * 1024)
    assert v.decrypt(v.encrypt("a", data, CTX), CTX) == data


@case("2  wrong encryption context is refused")
def _():
    rec = v.encrypt("a", b"x", CTX)
    code = error_code(lambda: v.decrypt(rec, {"tenant": "b", "record_id": "t1"}))
    assert code == "InvalidCiphertextException", code
    return code


@case("3  tampered ciphertext is rejected by AES-GCM")
def _():
    rec = v.encrypt("a", b"hello world", CTX)
    bad = {**rec, "ciphertext": bytes([rec["ciphertext"][0] ^ 1]) + rec["ciphertext"][1:]}
    try:
        v.decrypt(bad, CTX)
    except InvalidTag:
        return "InvalidTag"
    raise AssertionError("tampered ciphertext decrypted")


@case("4  rotate re-wraps the key and the record still decrypts")
def _():
    rec = v.encrypt("a", b"before-rotate", CTX)
    new = v.rotate("a", rec, CTX)
    assert new["edk"] != rec["edk"]
    assert new["ciphertext"] == rec["ciphertext"]
    assert v.decrypt(new, CTX) == b"before-rotate"


@case("5  disabled key refuses decrypt, enable restores it")
def _():
    rec = v.encrypt("a", b"x", CTX)
    key = v.kms.describe_key(KeyId=v.TENANT_KEYS["a"])["KeyMetadata"]["KeyId"]
    v.kms.disable_key(KeyId=key)
    try:
        code = error_code(lambda: v.decrypt(rec, CTX))
    finally:
        v.kms.enable_key(KeyId=key)
    assert code == "DisabledException", code
    assert v.decrypt(rec, CTX) == b"x"
    return code


@case("6  sign then verify")
def _():
    sig = v.sign(b"pay 100 to bob")
    assert v.verify(b"pay 100 to bob", sig) is True


@case("6  tampered message fails verify")
def _():
    sig = v.sign(b"pay 100 to bob")
    assert v.verify(b"pay 900 to bob", sig) is False


for name, ok, detail in results:
    print(f"{'PASS' if ok else 'FAIL'}  {name}" + (f"  -> {detail}" if detail else ""))
failed = sum(1 for _, ok, _ in results if not ok)
print(f"\npassed {len(results) - failed}, failed {failed}")
sys.exit(1 if failed else 0)
