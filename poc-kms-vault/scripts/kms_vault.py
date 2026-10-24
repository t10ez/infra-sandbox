"""Envelope encryption and signing on KMS. Endpoint comes from AWS_ENDPOINT_URL (floci) or the default AWS config."""
import json
import os

import boto3
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

kms = boto3.client("kms", region_name=os.environ.get("AWS_DEFAULT_REGION", "ap-southeast-7"))

TENANT_KEYS = {"default": "alias/vault-data", "a": "alias/vault-tenant-a", "b": "alias/vault-tenant-b"}
SIGN_KEY = "alias/vault-sign"


def _aad(context):
    return json.dumps(context, sort_keys=True).encode()


def encrypt(tenant, plaintext, context):
    """One KMS call for a fresh data key, then AES-256-GCM locally. Store the returned dict anywhere."""
    dk = kms.generate_data_key(KeyId=TENANT_KEYS[tenant], KeySpec="AES_256", EncryptionContext=context)
    nonce = os.urandom(12)
    ciphertext = AESGCM(dk["Plaintext"]).encrypt(nonce, plaintext, _aad(context))
    return {"edk": dk["CiphertextBlob"], "nonce": nonce, "ciphertext": ciphertext}


def decrypt(record, context):
    """KMS unwraps the data key only if the encryption context matches the one used at encrypt time."""
    dk = kms.decrypt(CiphertextBlob=record["edk"], EncryptionContext=context)
    return AESGCM(dk["Plaintext"]).decrypt(record["nonce"], record["ciphertext"], _aad(context))


def rotate(tenant, record, context):
    """Re-wrap the data key under the tenant's current key. The data key never leaves KMS."""
    out = kms.re_encrypt(
        CiphertextBlob=record["edk"], SourceEncryptionContext=context,
        DestinationKeyId=TENANT_KEYS[tenant], DestinationEncryptionContext=context,
    )
    return {**record, "edk": out["CiphertextBlob"]}


def sign(message):
    return kms.sign(KeyId=SIGN_KEY, Message=message, MessageType="RAW", SigningAlgorithm="ECDSA_SHA_256")["Signature"]


def verify(message, signature):
    try:
        return kms.verify(
            KeyId=SIGN_KEY, Message=message, MessageType="RAW", Signature=signature, SigningAlgorithm="ECDSA_SHA_256"
        )["SignatureValid"]
    except kms.exceptions.KMSInvalidSignatureException:
        return False
