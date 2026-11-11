#!/usr/bin/env python3
"""Keep only some identities from a keychain .p12 export.

    certs.py split <all.p12> <password> <out-dir> <issuer-regex>

Writes one <out-dir>/<n>-<name>.p12 per identity (certificate + its private key) whose issuer
matches <issuer-regex>, with the same password, in the 3DES/SHA-1 format `security import`
reads. Prints one line per kept identity; exits 1 when an identity has no private key.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unicodedata

OPENSSL = shutil.which("openssl", path="/opt/homebrew/bin:/usr/local/bin") or "openssl"
BLOCK = re.compile(r"Bag Attributes(?P<attrs>.*?)(?P<pem>-----BEGIN (?P<kind>[A-Z ]+)-----.*?-----END (?P=kind)-----)", re.S)


def run(*args, data=None):
    return subprocess.run([OPENSSL, *args], input=data, capture_output=True, check=True).stdout


def split(p12, password, out_dir, issuer_re):
    pw = f"pass:{password}"
    text = run("pkcs12", "-in", p12, "-passin", pw, "-nodes", "-legacy").decode("utf-8", "replace")
    keys, certs = {}, []
    for m in BLOCK.finditer(text):
        attrs = m["attrs"]
        kid = re.search(r"localKeyID:\s*([0-9A-F ]+)", attrs)
        kid = kid[1].strip() if kid else None
        if "PRIVATE KEY" in m["kind"]:
            if kid:
                keys[kid] = m["pem"]
        elif m["kind"] == "CERTIFICATE":
            certs.append((kid, m["pem"]))
    os.makedirs(out_dir, exist_ok=True)
    kept, missing, seen = 0, 0, set()
    for kid, cert in certs:
        if cert in seen:
            continue
        seen.add(cert)
        info = run("x509", "-noout", "-subject", "-issuer", "-nameopt", "utf8,sep_comma_plus,space_eq", data=cert.encode()).decode()
        issuer = re.search(r"^issuer=(.*)$", info, re.M)[1]
        if not re.search(issuer_re, issuer):
            continue
        name = re.search(r"CN = ([^,+]*)", info)
        name = name[1].strip() if name else f"identity-{kept + 1}"
        if kid not in keys:
            print(f"no private key: {name}", file=sys.stderr)
            missing += 1
            continue
        kept += 1
        with tempfile.TemporaryDirectory() as tmp:
            k, c = os.path.join(tmp, "k.pem"), os.path.join(tmp, "c.pem")
            with open(k, "w") as f:
                f.write(keys[kid])
            with open(c, "w") as f:
                f.write(cert)
            slug = re.sub(r"[^A-Za-z0-9]+", "-", unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()).strip("-") or "identity"
            out = os.path.join(out_dir, f"{kept:02d}-{slug}.p12")
            run("pkcs12", "-export", "-inkey", k, "-in", c, "-name", name, "-passout", pw,
                "-certpbe", "PBE-SHA1-3DES", "-keypbe", "PBE-SHA1-3DES", "-macalg", "sha1", "-out", out)
            os.chmod(out, 0o600)
        print(name)
    return 1 if missing else 0


if __name__ == "__main__":
    if len(sys.argv) != 6 or sys.argv[1] != "split":
        sys.exit(__doc__)
    sys.exit(split(*sys.argv[2:]))
