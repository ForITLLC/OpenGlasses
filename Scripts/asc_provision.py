# Copied from ForITLLC/for-Notes apps/ios/Scripts/asc_provision.py at f77e50a335343b0bcea4587fabd2614513595519
"""App Store profiles that match the entitlements, provisioned at build time.

Adapted to OpenGlasses. The archive holds two bundles, each signed with its own App Store
profile, and Scripts/mini-testflight.sh runs this once per bundle before archiving:

  com.forit.openglasses.dolores                  "OpenGlasses App Store"          the app
  com.forit.openglasses.dolores.activity-widget  "OpenGlasses Widget App Store"   the Live Activity widget

The names are the ones project.yml gives each target's Release configuration
(PROVISIONING_PROFILE_SPECIFIER), so Xcode finds the profile this writes by name. DoloresWatch
is not embedded in the app and gets no profile here. What changed from for-Notes: the Mac App
Store profile type (MAC_APP_STORE, for-Notes' native Mac app) is dropped; the logic is unchanged.

An entitlements file can ask for capabilities (for-Calendar: Push Notifications,
`aps-environment`). OpenGlasses asks for none today (OpenGlasses/OpenGlasses.entitlements is
empty), so mini-testflight.sh passes no --capability and no --entitlement. The rule still holds
the day one is added. Two things have to be true before `xcodebuild archive` will sign an app
that asks for a capability:

  1. the capability is ON the bundle id (Apple Developer, Identifiers);
  2. the App Store profile was minted AFTER the capability was added: a profile from before
     it lacks the entitlement and codesign refuses the archive ("provisioning profile doesn't
     support the Push Notifications capability").

A profile is reused only when App Store Connect reports it ACTIVE and its embedded
entitlements carry every key the archive needs; otherwise it is replaced under the same name.
Profiles of any other name are never touched.

The Apple Distribution certificate is chosen by PUBLIC KEY, the one whose key is the key we
sign with (the Mini's ~/AppleCerts/distribution.der), never by position, and another team
member's certificate is never used or revoked.

`--bundle-id` names the bundle identifier the profile is for (default: $BUNDLE_ID) and
`--register-as "<name>"` registers it on the team when it is not there yet. Both OpenGlasses
bundle ids are registered already, so mini-testflight.sh does not pass --register-as: a missing
bundle id is a failed step, never a new registration.

Pure logic takes an injected `api` callable. Key material is read only in `main()`.
Every failure ends in one `::error title=<--error-title>::<why>` line, so a failed step says
which profile could not be made and what App Store Connect answered.

Usage (env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_BASE64, BUNDLE_ID):
  asc_provision.py profile --type IOS_APP_STORE --name <profile name>
                           [--bundle-id <bundle id>] [--register-as "<name>"]
                           [--capability PUSH_NOTIFICATIONS]...
                           [--entitlement aps-environment]...
                           [--cert-der <path>] [--error-title <title>] --out <path>
"""

from __future__ import annotations

import argparse
import base64
import binascii
import os
import plistlib
import subprocess
import sys
from dataclasses import dataclass
from typing import Callable, Iterable, Optional

import asc_resolve  # make_api: one JWT/HTTP path for every script

# The platform a bundle id is registered on, for each profile type `profile --type` takes.
REGISTER_PLATFORM = {
    "IOS_APP_STORE": "IOS",
}

Api = Callable[..., dict]

DISTRIBUTION_CERTS = "/certificates?filter[certificateType]=DISTRIBUTION"


@dataclass
class Profile:
    id: str
    content: str  # base64 .mobileprovision bytes
    created: bool


# --- the bundle id -------------------------------------------------------------------

def cert_public_key(cert_der_b64: str) -> str:
    """The public key (PEM) of a certificate as App Store Connect returns it: base64 DER."""
    out = subprocess.run(["openssl", "x509", "-inform", "DER", "-noout", "-pubkey"],
                         input=base64.b64decode(cert_der_b64), capture_output=True, check=True)
    return out.stdout.decode().strip()


def bundle_id_resource(api: Api, identifier: str) -> str:
    """The App Store Connect resource id of exactly this bundle identifier.

    `filter[identifier]` is a contains-match on Apple's side (com.forit.openglasses.dolores would
    also return the .activity-widget and .watchkitapp ids), so the record is picked by its
    exact identifier."""
    bundles = api("GET", f"/bundleIds?filter[identifier]={identifier}").get("data", [])
    for b in bundles:
        if b.get("attributes", {}).get("identifier") == identifier:
            return b["id"]
    raise SystemExit(f"no bundle id {identifier} on the team (Apple Developer, Identifiers)")


def ensure_bundle_id(api: Api, identifier: str, name: str, platform: str = "IOS") -> tuple[str, bool]:
    """The resource id of this bundle identifier, registering it when the team lacks it.

    Returns (resource id, created). Only with --register-as, which mini-testflight.sh does not
    pass. Registration is idempotent in effect: a second run finds the record."""
    try:
        return bundle_id_resource(api, identifier), False
    except SystemExit:
        pass
    created = api("POST", "/bundleIds", body={
        "data": {
            "type": "bundleIds",
            "attributes": {"identifier": identifier, "name": name, "platform": platform},
        },
    }).get("data") or {}
    if not created.get("id"):
        raise SystemExit(f"registering bundle id {identifier} answered no id")
    return created["id"], True


# --- capabilities on the bundle id --------------------------------------------------

def ensure_capabilities(api: Api, bundle_id_resource: str, wanted: Iterable[str]) -> list[str]:
    """Add every capability in `wanted` the bundle id does not have yet; returns the added ones."""
    have = {
        c.get("attributes", {}).get("capabilityType")
        for c in api("GET", f"/bundleIds/{bundle_id_resource}/bundleIdCapabilities").get("data", [])
    }
    added: list[str] = []
    for cap in wanted:
        if cap in have:
            continue
        api("POST", "/bundleIdCapabilities", body={
            "data": {
                "type": "bundleIdCapabilities",
                "attributes": {"capabilityType": cap},
                "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle_id_resource}}},
            },
        })
        added.append(cap)
    return added


# --- what a profile carries ----------------------------------------------------------

def profile_entitlements(content_b64: str) -> Optional[dict]:
    """The Entitlements dict embedded in a signed profile, or None when unreadable.

    `profileContent` is a CMS (PKCS#7) blob with the property list inside it verbatim,
    so the plist is cut out between its XML prologue and `</plist>` — no crypto needed
    to read what the profile grants."""
    try:
        raw = base64.b64decode(content_b64, validate=True)
    except (binascii.Error, ValueError):
        return None
    start = raw.find(b"<?xml")
    end = raw.find(b"</plist>")
    if start < 0 or end < 0:
        return None
    try:
        plist = plistlib.loads(raw[start:end + len(b"</plist>")])
    except Exception:  # noqa: BLE001 — any malformed plist is "unreadable", not a crash
        return None
    entitlements = plist.get("Entitlements") if isinstance(plist, dict) else None
    return entitlements if isinstance(entitlements, dict) else None


def profile_is_usable(resource: dict, required_entitlements: Iterable[str]) -> bool:
    attrs = resource.get("attributes", {})
    if attrs.get("profileState") != "ACTIVE":
        return False
    required = list(required_entitlements)
    if not required:
        return True
    entitlements = profile_entitlements(attrs.get("profileContent", ""))
    return entitlements is not None and all(key in entitlements for key in required)


# --- the profile ---------------------------------------------------------------------

def ensure_profile(
    api: Api,
    name: str,
    profile_type: str,
    bundle_id_resource: str,
    cert_ids: list[str],
    required_entitlements: Iterable[str] = (),
    force_recreate: bool = False,
) -> Profile:
    """An ACTIVE profile of this name and type carrying the required entitlements.

    Anything else under that name — INVALID, minted before a capability, or simply
    superseded (`force_recreate`, right after a capability was added and Apple may
    still report the old profile ACTIVE) — is deleted and minted again under the same
    name. Profiles of other names are never touched."""
    required = list(required_entitlements)
    # limit=200: the default page is 20, and a name missed on page two would be minted
    # a second time next to the one that exists.
    profiles = api("GET", f"/profiles?filter[profileType]={profile_type}&limit=200").get("data", [])
    for p in profiles:
        attrs = p.get("attributes", {})
        if attrs.get("name") != name:
            continue
        if not force_recreate and profile_is_usable(p, required):
            return Profile(id=p["id"], content=attrs["profileContent"], created=False)
        api("DELETE", f"/profiles/{p['id']}")
    created = api("POST", "/profiles", body={
        "data": {
            "type": "profiles",
            "attributes": {"name": name, "profileType": profile_type},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_id_resource}},
                "certificates": {"data": [{"type": "certificates", "id": c} for c in cert_ids]},
            },
        },
    })["data"]
    return Profile(id=created["id"], content=created["attributes"]["profileContent"], created=True)


def write_profile(profile: Profile, out_path: str) -> None:
    with open(out_path, "wb") as f:
        f.write(base64.b64decode(profile.content))


# --- the certificate -----------------------------------------------------------------

def distribution_cert_ids(api: Api, cert_der_path: Optional[str] = None) -> list[str]:
    """The Apple Distribution certificate the profile binds to.

    With `cert_der_path` (the DER we sign with), the team certificate whose public key
    is that key; without it, the team's first. A team that holds only other keys'
    certificates is an error that names them — they are not ours to use or revoke."""
    certs = api("GET", DISTRIBUTION_CERTS).get("data", [])
    if not certs:
        raise SystemExit("no Apple Distribution certificate on the team")
    if cert_der_path is None:
        return [certs[0]["id"]]
    with open(cert_der_path, "rb") as f:
        want = cert_public_key(base64.b64encode(f.read()).decode())
    for c in certs:
        if cert_public_key(c["attributes"]["certificateContent"]) == want:
            return [c["id"]]
    others = ", ".join(c["id"] for c in certs)
    raise SystemExit(
        "no Apple Distribution certificate matches the key we sign with "
        f"(team holds: {others} — not ours; never revoke them). Check ~/AppleCerts/distribution.der on the Mini."
    )


# --- CLI -----------------------------------------------------------------------------

def _api_from_env() -> Api:
    private_key = base64.b64decode(os.environ["ASC_KEY_BASE64"]).decode()
    return asc_resolve.make_api(os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], private_key)


def _gh_output(lines: list[str]) -> None:
    gh_out = os.environ.get("GITHUB_OUTPUT")
    if gh_out:
        with open(gh_out, "a") as f:
            f.write("\n".join(lines) + "\n")


def main(argv: Optional[list[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("profile", help="ensure the capabilities and an App Store profile that carries them; write it")
    p.add_argument("--type", required=True, choices=list(REGISTER_PLATFORM))
    p.add_argument("--name", required=True, help="the profile's name in App Store Connect")
    p.add_argument("--capability", action="append", default=[], help="bundle id capability the entitlements need, e.g. ASSOCIATED_DOMAINS")
    p.add_argument("--entitlement", action="append", default=[], help="entitlement key the profile must carry")
    p.add_argument("--cert-der", help="the Apple Distribution certificate (DER) we sign with — chooses the team cert by public key")
    p.add_argument("--bundle-id", help="the bundle identifier the profile is for (default: $BUNDLE_ID)")
    p.add_argument("--register-as", metavar="NAME",
                   help="register the bundle id on the team under this name when it is missing (its first build)")
    p.add_argument("--error-title", default="App Store profile",
                   help="title of the ::error:: line a failure prints")
    p.add_argument("--out", required=True)
    args = ap.parse_args(argv)
    try:
        return _provision(args)
    except SystemExit as e:
        if e.code in (None, 0):
            raise
        print(error_line(args.error_title, args.name, args.bundle_id or os.environ.get("BUNDLE_ID", "?"), e), flush=True)
        return 1
    except Exception as e:  # noqa: BLE001 — any crash is a failed profile, said plainly
        print(error_line(args.error_title, args.name, args.bundle_id or os.environ.get("BUNDLE_ID", "?"), e), flush=True)
        return 1


def error_line(title: str, profile_name: str, bundle_identifier: str, error: BaseException) -> str:
    """One GitHub `::error::` annotation naming the profile, the bundle id and the cause.

    Newlines would end the annotation early, so the cause is folded onto one line."""
    raw = error.code if isinstance(error, SystemExit) and isinstance(error.code, str) else str(error)
    cause = " ".join(raw.split()) or type(error).__name__
    return f"::error title={title}::could not provision '{profile_name}' for {bundle_identifier}: {cause}"


def _provision(args: argparse.Namespace) -> int:
    api = _api_from_env()
    bundle_identifier = args.bundle_id or os.environ["BUNDLE_ID"]
    if args.register_as:
        bundle_resource, registered = ensure_bundle_id(api, bundle_identifier, args.register_as,
                                                       platform=REGISTER_PLATFORM[args.type])
        if registered:
            print(f"bundle id {bundle_identifier} registered on the team as '{args.register_as}' ({bundle_resource})")
    else:
        bundle_resource = bundle_id_resource(api, bundle_identifier)

    added = ensure_capabilities(api, bundle_resource, args.capability)
    for cap in added:
        print(f"capability {cap} added to {bundle_identifier} — the profile is minted again below")
    certs = distribution_cert_ids(api, args.cert_der)
    prof = ensure_profile(
        api, args.name, args.type, bundle_resource, certs,
        required_entitlements=args.entitlement, force_recreate=bool(added),
    )
    write_profile(prof, args.out)
    print(f"{args.type} profile '{args.name}' {prof.id} ({'created' if prof.created else 'reused'}) -> {args.out}")
    _gh_output([
        f"profile_id={prof.id}",
        f"profile_created={'true' if prof.created else 'false'}",
        f"capabilities_added={' '.join(added)}",
    ])
    return 0


if __name__ == "__main__":
    sys.exit(main())
