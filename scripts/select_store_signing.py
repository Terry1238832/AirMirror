#!/usr/bin/env python3
"""Select an existing local development identity without exporting private keys."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def select():
    identities = subprocess.check_output(["security", "find-identity", "-v", "-p", "codesigning"], text=True)
    rows = []
    for sha, cn in re.findall(r'([A-F0-9]{40}) "((?:Apple Development|Developer ID Application):[^\n]+)"', identities):
        certificates = subprocess.check_output(["security", "find-certificate", "-a", "-c", cn, "-p"], text=True)
        for pem in re.findall(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", certificates, re.S):
            raw = base64.b64decode("".join(pem.splitlines()[1:-1]))
            if hashlib.sha1(raw).hexdigest().upper() != sha:
                continue
            subject = subprocess.run(["openssl", "x509", "-noout", "-subject", "-nameopt", "RFC2253"],
                                     input=pem, text=True, capture_output=True, check=True).stdout
            match = re.search(r"(?:^|,)OU=([A-Z0-9]{10})(?:,|$)", subject)
            if match:
                rows.append({"sha": sha, "kind": cn.split(":")[0], "team": match.group(1)})
    dev = [row for row in rows if row["kind"] == "Apple Development"]
    requested = os.environ.get("AIRMIRROR_DEVELOPMENT_TEAM")
    identity = os.environ.get("AIRMIRROR_SIGN_IDENTITY")
    if requested:
        dev = [row for row in dev if row["team"] == requested]
    elif not identity:
        paid = {row["team"] for row in rows if row["kind"] == "Developer ID Application"}
        matching = [row for row in dev if row["team"] in paid]
        if matching:
            dev = matching
    if identity:
        dev = [row for row in dev if row["sha"].casefold() == identity.casefold()]
    if not dev:
        raise SystemExit("No matching Apple Development identity. Configure one in Xcode first.")
    if len({row["team"] for row in dev}) != 1:
        raise SystemExit("Multiple development teams. Set AIRMIRROR_DEVELOPMENT_TEAM explicitly.")
    return dev[0]


if __name__ == "__main__":
    destination = Path(sys.argv[1])
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(select()) + "\n")
    print("Selected an existing development identity for local Store validation.")
