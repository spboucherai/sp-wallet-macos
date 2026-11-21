#!/usr/bin/env python3
# =============================================================================
#                  SP BOUCHER | SOFTWARE & RESEARCH
#             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
# =============================================================================
#
# PROJECT METADATA
# -----------------------------------------------------------------------------
# Project          : SP Wallet for macOS
# File             : Scripts/asc.py
# Module           : Scripts
# Repository       : https://git.spboucher.ai/sp-wallet-macos
# Created          : 2026-11-18
# Last Modified    : 2026-11-18
#
# =============================================================================
# AUTHOR & PROFESSIONAL AFFILIATION
# =============================================================================
#
# Author           : Simon-Pierre Boucher
# Position         : Professor of Finance
# Institution      : Université du Québec en Outaouais (UQO)
# Department       : Département des sciences administratives
# Organization     : SP Boucher
#
# Website          : https://spboucher.ai
# Git              : https://git.spboucher.ai
#
# =============================================================================
# OFFICIAL CONTACT DIRECTORY
# =============================================================================
#
# General          : info@spboucher.ai
# Professional     : contact@spboucher.ai
# Direct           : simon@spboucher.ai
# Research         : research@spboucher.ai
# Development      : dev@spboucher.ai
# Support          : support@spboucher.ai
# Security/Admin   : admin@spboucher.ai
# Notifications    : notifications@spboucher.ai
#
# Preferred Contact: support@spboucher.ai
#
# =============================================================================
# COPYRIGHT & INTELLECTUAL PROPERTY
# =============================================================================
#
# Copyright (c) 2026
# Simon-Pierre Boucher
#
# All rights reserved where applicable.
#
# This file is governed by the applicable project license,
# copyright notices, institutional agreements and relevant law.
#
# Unless expressly authorized by the applicable license or
# rights holder, copying, redistribution, sublicensing,
# publication and commercial exploitation are not permitted.
#
# Existing third-party rights and notices remain unaffected.
#
# =============================================================================
# CONFIDENTIALITY & SECURITY
# =============================================================================
#
# Classification   : Public
# Distribution     : Public repository; use is governed by the project license
# Security Contact : admin@spboucher.ai
#
# Access to this source does not independently grant permission
# to redistribute or disclose confidential materials.
#
# Do not embed credentials, private keys, access tokens,
# certificates or confidential personal information.
#
# =============================================================================
# LICENSE & MAINTENANCE
# =============================================================================
#
# License          : None specified (no license file in this repository)
# Maintainer       : Simon-Pierre Boucher
# Technical Contact: dev@spboucher.ai
#
# =============================================================================
# END OF SP BOUCHER SOURCE HEADER
# =============================================================================

# Author: Simon-Pierre Boucher — contact@spboucher.ai
# File: Scripts/asc.py
# Description: Minimal App Store Connect API client (existing API key) used to register the bundle id, its Associated Domains capability and the Developer ID profile.
#
# The key id / issuer id / .p8 path are read from the environment or from the existing release tooling of the Mac;
# nothing secret is printed.
import base64, json, os, re, subprocess, sys, time, urllib.request, urllib.error, glob

def creds():
    kid, iss, path = os.environ.get("ASC_KEY_ID"), os.environ.get("ASC_ISSUER_ID"), os.environ.get("ASC_KEY_PATH")
    if not (kid and iss):
        ref = os.path.expanduser("~/Desktop/Cluster/apple/maclustr-ios-v2/app/scripts/testflight-archive-upload.sh")
        if os.path.exists(ref):
            s = open(ref).read()
            m1, m2 = re.search(r"-authenticationKeyID\s+(\S+)", s), re.search(r"-authenticationKeyIssuerID\s+([0-9a-fA-F-]{36})", s)
            if m1 and m2: kid, iss = m1.group(1).strip('"'), m2.group(1)
    if not path and kid:
        for d in ("~/.appstoreconnect/private_keys", "~/.private_keys", "~/private_keys"):
            p = os.path.expanduser(f"{d}/AuthKey_{kid}.p8")
            if os.path.exists(p): path = p; break
    if not (kid and iss and path): sys.exit("ERROR: App Store Connect API key not found (set ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH).")
    return kid, iss, path

def b64(b): return base64.urlsafe_b64encode(b).rstrip(b"=")

def token():
    kid, iss, path = creds()
    head = b64(json.dumps({"alg": "ES256", "kid": kid, "typ": "JWT"}).encode())
    body = b64(json.dumps({"iss": iss, "iat": int(time.time()), "exp": int(time.time()) + 900, "aud": "appstoreconnect-v1"}).encode())
    msg = head + b"." + body
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", path], input=msg, capture_output=True, check=True).stdout
    # DER ECDSA signature → raw r||s (JOSE)
    i = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7f)
    rl = der[i + 1]; r = der[i + 2:i + 2 + rl]; j = i + 2 + rl; sl = der[j + 1]; s = der[j + 2:j + 2 + sl]
    raw = r[-32:].rjust(32, b"\0") + s[-32:].rjust(32, b"\0")
    return (msg + b"." + b64(raw)).decode()

def call(method, path, body=None):
    req = urllib.request.Request("https://api.appstoreconnect.apple.com" + path, method=method, data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            t = r.read(); return r.status, (json.loads(t) if t else {})
    except urllib.error.HTTPError as e:
        t = e.read()
        try: return e.code, json.loads(t)
        except Exception: return e.code, {"raw": t.decode(errors="replace")[:500]}

if __name__ == "__main__":
    method, path = sys.argv[1], sys.argv[2]
    body = json.loads(sys.argv[3]) if len(sys.argv) > 3 else None
    status, data = call(method, path, body)
    print(status); print(json.dumps(data, indent=1)[:6000])
