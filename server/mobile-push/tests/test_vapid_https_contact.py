"""Regression: RFC 8292 HTTPS contact paths must sign without weakening URL checks."""

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

from mobile_push.config import Policy, Rejected
from mobile_push.transport import _vapid_for_policy


@pytest.fixture
def pem(tmp_path):
    key = ec.generate_private_key(ec.SECP256R1())
    p = tmp_path / "operator-vapid.pem"
    p.write_bytes(
        key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
    )
    p.chmod(0o600)
    return p


def policy(pem, contact):
    return Policy(True, {}, frozenset(), pem, contact)


@pytest.mark.parametrize(
    "contact",
    ["https://github.com/operator/hermes-mobile-contact",
     "https://support.example.net:8443/mobile"],
)
def test_rfc_valid_https_contact_paths_sign(pem, contact):
    signer = _vapid_for_policy(policy(pem, contact))
    assert signer.conf.get("no-strict") is True
    signed = signer.sign({"sub": contact, "aud": "https://fcm.googleapis.com"})
    assert signed["Authorization"].startswith("vapid ")


def test_mailto_stays_strict(pem):
    contact = "mailto:operator@example.com"
    signer = _vapid_for_policy(policy(pem, contact))
    assert signer.conf.get("no-strict") is not True
    assert signer.sign({"sub": contact, "aud": "https://fcm.googleapis.com"})


@pytest.mark.parametrize(
    "contact",
    ["https://user:pass@example.org/support",
     "https://example.org/support#fragment",
     "https://example.org:99999/support",
     "https://example.org/unsafe\\path",
     "https://example.org/unsafe\npath",
     "https:///missing-host"],
)
def test_malformed_https_contact_rejected(pem, contact):
    with pytest.raises(Rejected) as failure:
        _vapid_for_policy(policy(pem, contact))
    assert failure.value.status == 422
