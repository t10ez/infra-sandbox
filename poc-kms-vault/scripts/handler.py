"""kms-vault: envelope encryption + signing on top of KMS, behind an API Gateway HTTP API (payload v2)."""
import base64
import json
import os
import time

import boto3
from botocore.exceptions import ClientError
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

TABLE = os.environ["TABLE"]
SIGN_KEY = os.environ["SIGN_KEY"]
DEFAULT_KEY = os.environ["DEFAULT_KEY"]
TENANT_PREFIX = os.environ["TENANT_PREFIX"]

kms = boto3.client("kms")
table = boto3.resource("dynamodb").Table(TABLE)

b64 = lambda b: base64.b64encode(b).decode()
unb64 = lambda s: base64.b64decode(s)


class BadRequest(Exception):
    pass


def tenant_key(tenant):
    if tenant == "default":
        return DEFAULT_KEY
    if tenant in ("a", "b"):
        return TENANT_PREFIX + tenant
    raise BadRequest(f"unknown tenant {tenant!r}")


def ctx(tenant, record_id):
    return {"tenant": tenant, "record_id": record_id}


def timed(fn, *a, **kw):
    t = time.perf_counter()
    out = fn(*a, **kw)
    return out, (time.perf_counter() - t) * 1000


def encrypt(body):
    tenant, rid, plaintext = body["tenant"], body["record_id"], body["plaintext"].encode()
    dk, kms_ms = timed(
        kms.generate_data_key,
        KeyId=tenant_key(tenant), KeySpec="AES_256", EncryptionContext=ctx(tenant, rid),
    )
    nonce = os.urandom(12)
    ct, aes_ms = timed(AESGCM(dk["Plaintext"]).encrypt, nonce, plaintext, f"{tenant}:{rid}".encode())
    table.put_item(Item={
        "id": rid, "tenant": tenant, "edk": b64(dk["CiphertextBlob"]),
        "nonce": b64(nonce), "ciphertext": b64(ct), "key_id": dk["KeyId"],
    })
    return 200, {"id": rid, "key_id": dk["KeyId"], "kms_ms": kms_ms, "aes_ms": aes_ms}


def decrypt(body):
    tenant, rid = body["tenant"], body["id"]
    item = table.get_item(Key={"id": rid}).get("Item")
    if not item:
        return 404, {"error": "NotFound"}
    # tenant comes from the caller: a wrong tenant changes the encryption context and KMS refuses.
    dk, kms_ms = timed(kms.decrypt, CiphertextBlob=unb64(item["edk"]), EncryptionContext=ctx(tenant, rid))
    pt, aes_ms = timed(
        AESGCM(dk["Plaintext"]).decrypt, unb64(item["nonce"]), unb64(item["ciphertext"]), f"{tenant}:{rid}".encode()
    )
    return 200, {"plaintext": pt.decode(), "kms_ms": kms_ms, "aes_ms": aes_ms}


def rotate(rid, body):
    tenant = body["tenant"]
    item = table.get_item(Key={"id": rid}).get("Item")
    if not item:
        return 404, {"error": "NotFound"}
    out, kms_ms = timed(
        kms.re_encrypt,
        CiphertextBlob=unb64(item["edk"]),
        SourceEncryptionContext=ctx(tenant, rid),
        DestinationKeyId=tenant_key(tenant),
        DestinationEncryptionContext=ctx(tenant, rid),
    )
    table.update_item(
        Key={"id": rid}, UpdateExpression="SET edk = :e, key_id = :k",
        ExpressionAttributeValues={":e": b64(out["CiphertextBlob"]), ":k": out["KeyId"]},
    )
    return 200, {"id": rid, "key_id": out["KeyId"], "kms_ms": kms_ms}


def sign(body):
    out = kms.sign(
        KeyId=SIGN_KEY, Message=body["message"].encode(), MessageType="RAW", SigningAlgorithm="ECDSA_SHA_256"
    )
    return 200, {"signature": b64(out["Signature"])}


def verify(body):
    out = kms.verify(
        KeyId=SIGN_KEY, Message=body["message"].encode(), MessageType="RAW",
        Signature=unb64(body["signature"]), SigningAlgorithm="ECDSA_SHA_256",
    )
    return 200, {"valid": out["SignatureValid"]}


def handler(event, _context):
    route = event["routeKey"]
    try:
        body = json.loads(event.get("body") or "{}")
        if route == "POST /encrypt":
            status, out = encrypt(body)
        elif route == "POST /decrypt":
            status, out = decrypt(body)
        elif route == "POST /rotate/{id}":
            status, out = rotate(event["pathParameters"]["id"], body)
        elif route == "POST /sign":
            status, out = sign(body)
        elif route == "POST /verify":
            status, out = verify(body)
        else:
            status, out = 404, {"error": "NoRoute"}
    except BadRequest as e:
        status, out = 400, {"error": "BadRequest", "message": str(e)}
    except KeyError as e:
        status, out = 400, {"error": "BadRequest", "message": f"missing field {e}"}
    except ClientError as e:
        code = e.response["Error"]["Code"]
        status = 403 if code in ("AccessDeniedException", "AccessDenied") else 400
        out = {"error": code, "message": e.response["Error"].get("Message", "")}
    except Exception as e:  # AES-GCM tag mismatch and similar
        status, out = 400, {"error": type(e).__name__}
    print(json.dumps({"route": route, "status": status, "error": out.get("error")}))
    return {"statusCode": status, "headers": {"content-type": "application/json"}, "body": json.dumps(out)}
