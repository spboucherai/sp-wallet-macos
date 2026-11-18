#!/usr/bin/env python3
# Author: Simon-Pierre Boucher — contact@spboucher.ai
# File: Scripts/provision.py
# Description: Registers SP Wallet's bundle identifiers (release and development variants), the Associated Domains capability of the app, and their Developer ID provisioning profiles — with the EXISTING App Store Connect API key and Developer ID certificate.
#
# Idempotent: existing resources are reused; no certificate is ever created. Nothing secret is printed.
import base64, hashlib, os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asc

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Build", "profiles")
# identifier, display name, profile name, file, capabilities
TARGETS = [
    ("ai.spboucher.spwallet", "SP Wallet", "SP Wallet Developer ID", "SPWallet.provisionprofile", ["ASSOCIATED_DOMAINS"]),
    ("ai.spboucher.spwallet.dev", "SP Wallet Dev", "SP Wallet Dev Developer ID", "SPWalletDev.provisionprofile", []),
]

out = subprocess.run(["security", "find-certificate", "-c", "Developer ID Application", "-Z"], capture_output=True, text=True).stdout
local = [l.split(":")[1].strip() for l in out.splitlines() if l.startswith("SHA-1")]
if not local: sys.exit("no Developer ID Application certificate in the keychain")
s, d = asc.call("GET", "/v1/certificates?filter[certificateType]=DEVELOPER_ID_APPLICATION,DEVELOPER_ID_APPLICATION_G2&limit=100")
cert = next((c["id"] for c in d.get("data", []) if hashlib.sha1(base64.b64decode(c["attributes"]["certificateContent"])).hexdigest().upper() in local), None)
if not cert: sys.exit("the keychain's Developer ID certificate is not visible through the API")
s, allp = asc.call("GET", "/v1/profiles?filter[profileType]=MAC_APP_DIRECT&limit=200")
os.makedirs(OUT, exist_ok=True)

for BID, DISPLAY, NAME, FILE, CAPS in TARGETS:
    s, d = asc.call("GET", f"/v1/bundleIds?filter[identifier]={BID}&limit=20")
    ids = [b for b in d.get("data", []) if b["attributes"]["identifier"] == BID]
    if ids: bid = ids[0]["id"]; print("bundle id exists:", BID)
    else:
        s, d = asc.call("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {"identifier": BID, "name": DISPLAY, "platform": "MAC_OS"}}})
        if s >= 300: sys.exit(f"cannot create bundle id {BID}: HTTP {s}")
        bid = d["data"]["id"]; print("bundle id created:", BID)
    s, d = asc.call("GET", f"/v1/bundleIds/{bid}/bundleIdCapabilities")
    have = [c["attributes"]["capabilityType"] for c in d.get("data", [])]
    changed = False
    for cap in CAPS:
        if cap in have: continue
        s, d = asc.call("POST", "/v1/bundleIdCapabilities", {"data": {"type": "bundleIdCapabilities", "attributes": {"capabilityType": cap}, "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}}}}})
        if s >= 300: sys.exit(f"cannot enable {cap} on {BID}: HTTP {s}")
        print("capability enabled:", cap); changed = True
    if changed: s, allp = asc.call("GET", "/v1/profiles?filter[profileType]=MAC_APP_DIRECT&limit=200")
    mine = [p for p in allp.get("data", []) if p["attributes"]["name"] == NAME]
    active = [p for p in mine if p["attributes"]["profileState"] == "ACTIVE"]
    if active: p = active[0]; print("profile exists:", NAME)
    else:
        # a capability change on the App ID invalidates its profiles: the stale one is replaced
        for stale in mine: asc.call("DELETE", f"/v1/profiles/{stale['id']}"); print("stale profile removed:", stale["attributes"]["profileState"])
        s, d = asc.call("POST", "/v1/profiles", {"data": {"type": "profiles", "attributes": {"name": NAME, "profileType": "MAC_APP_DIRECT"}, "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}}, "certificates": {"data": [{"type": "certificates", "id": cert}]}}}})
        if s >= 300: sys.exit(f"cannot create the profile {NAME}: HTTP {s}")
        p = d["data"]; print("profile created:", NAME)
    path = os.path.join(OUT, FILE)
    open(path, "wb").write(base64.b64decode(p["attributes"]["profileContent"]))
    print("  written:", os.path.relpath(path), "| uuid", p["attributes"]["uuid"], "| expires", p["attributes"]["expirationDate"][:10])
    for dest in ("~/Library/Developer/Xcode/UserData/Provisioning Profiles", "~/Library/MobileDevice/Provisioning Profiles"):
        dd = os.path.expanduser(dest); os.makedirs(dd, exist_ok=True)
        open(os.path.join(dd, p["attributes"]["uuid"] + ".provisionprofile"), "wb").write(base64.b64decode(p["attributes"]["profileContent"]))
