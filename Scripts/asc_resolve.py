# Copied from ForITLLC/for-Notes apps/ios/Scripts/asc_resolve.py at f77e50a335343b0bcea4587fabd2614513595519
"""Resolve the App Store Connect values a TestFlight upload of ForIT Glasses needs, from the bundle id.

Adapted to OpenGlasses (bundle com.forit.openglasses.dolores, App Store Connect app 6761319043).
Scripts/mini-testflight.sh runs this with `--require` before it archives, and reads three values
back from the file named by $GITHUB_OUTPUT:

  app_id      the app record found by bundle id (the script checks it is 6761319043)
  group_id    the INTERNAL TestFlight group named $BETA_GROUP_NAME (default "ForIT Internal")
  next_build  the highest numeric build number App Store Connect has for the app, plus one: the
              rule .github/workflows/build-and-upload.yml used ("ASC latest + 1")

What changed from for-Notes, and why:
  - The group is picked by name among the app's internal groups only. The app has more than one
    group, and an external one among them; an external group is never picked, whatever its name.
  - Nothing here writes. for-Notes creates a group when the app has none and turns the group's
    Mac and Vision Pro availability off on every run; both are dropped. A missing group is a
    failed run whose reason says so (docs/access-control.md: staff are added only to
    "ForIT Internal", no external group, no public link).
  - next_build is new; it replaces the workflow's inline step.

metered-call-guard: not-metered the App Store Connect API is part of the Apple Developer membership;
Apple rate-limits it per hour and bills nothing per call.

The app record is made once, by hand, in App Store Connect; the API cannot create it. Without
`--require` a missing record is a notice and exit 0, for a caller that only wants to know.

Pure logic lives in `resolve(api, bundle_id, group_name)` and takes an injected `api` callable.
Key material is read only in `main()`.

Usage (env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_BASE64, BUNDLE_ID, optional BETA_GROUP_NAME, GITHUB_OUTPUT):
  asc_resolve.py [--require]
"""
from __future__ import annotations

import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Callable, Optional

ASC_BASE = "https://api.appstoreconnect.apple.com/v1"

# The App Store Connect record's name, and the word that marks a record named like it.
APP_NAME = "ForIT Glasses"
LOOKALIKE_WORD = "glasses"
DEFAULT_GROUP = "ForIT Internal"

Api = Callable[..., dict]


class AscError(SystemExit):
    """An App Store Connect HTTP error raised by the `api` callable `make_api` returns.

    A SystemExit, so a script that does not catch it still ends with the message on
    stderr and exit status 1; a caller that expects a specific status (asc_attach.py and
    the 422 an internal all-builds group answers the attach with) catches it and reads `.status`."""

    def __init__(self, message: str, *, status: int, detail: str):
        super().__init__(message)
        self.status = status
        self.detail = detail


@dataclass
class Resolved:
    ready: bool
    app_id: Optional[str]
    group_id: Optional[str]
    next_build: Optional[int]
    reason: str


def resolve(api: Api, bundle_id: str, group_name: str) -> Resolved:
    apps = [a for a in api("GET", f"/apps?filter[bundleId]={bundle_id}").get("data", [])
            if (a.get("attributes") or {}).get("bundleId", bundle_id) == bundle_id]
    if not apps:
        return Resolved(
            ready=False, app_id=None, group_id=None, next_build=None,
            reason=(
                f"no App Store Connect app record for bundle id {bundle_id}; it is made once, by hand, in "
                f"App Store Connect (the \"{APP_NAME}\" record) and the upload cannot create it. "
                + what_the_key_sees(api, bundle_id)
            ),
        )
    app_id = apps[0]["id"]
    group = internal_group(api, app_id, group_name)
    if group is None:
        return Resolved(
            ready=False, app_id=app_id, group_id=None, next_build=None,
            reason=(
                f"app {app_id} has no INTERNAL TestFlight group named \"{group_name}\". Nothing here makes one "
                "and no other group is used (docs/access-control.md); fix the group in App Store Connect."
            ),
        )
    return Resolved(ready=True, app_id=app_id, group_id=group["id"],
                    next_build=next_build_number(api, app_id), reason="")


def internal_group(api: Api, app_id: str, group_name: str) -> Optional[dict]:
    """The app's internal beta group with exactly this name, or None. External groups are never returned."""
    groups = api("GET", f"/betaGroups?filter[app]={app_id}&limit=200").get("data", [])
    for g in groups:
        attrs = g.get("attributes") or {}
        if attrs.get("isInternalGroup") is True and attrs.get("name") == group_name:
            return g
    return None


def next_build_number(api: Api, app_id: str) -> int:
    """The highest numeric CFBundleVersion of any build of the app, plus one (1 for an app with none).
    Every page is read, so an app with more than 200 builds still gets the true maximum."""
    path: Optional[str] = f"/builds?filter[app]={app_id}&limit=200&fields[builds]=version"
    highest = 0
    while path:
        page = api("GET", path)
        for b in page.get("data", []):
            version = str((b.get("attributes") or {}).get("version", ""))
            if version.isdigit():
                highest = max(highest, int(version))
        nxt = (page.get("links") or {}).get("next")
        path = nxt[len(ASC_BASE):] if nxt and nxt.startswith(ASC_BASE) else None
    return highest + 1


def what_the_key_sees(api: Api, bundle_id: str) -> str:
    """Why the record was not found: every app this API key can see, by name and bundle id, and any "glasses" app
    filed under another bundle id. Read-only; a refused listing is reported, never raised."""
    try:
        data = api("GET", "/apps?fields[apps]=name,bundleId&limit=200").get("data", [])
    except AscError as e:
        return f"Listing the apps this key sees failed too (HTTP {e.status})."
    seen = [((a.get("attributes") or {}).get("name") or "?", (a.get("attributes") or {}).get("bundleId") or "?")
            for a in data]
    line = f"This API key sees {len(seen)} app(s): " + (", ".join(f"{n} ({b})" for n, b in seen) or "none") + "."
    lookalikes = [f"{n} ({b})" for n, b in seen if LOOKALIKE_WORD in n.lower() and b != bundle_id]
    if lookalikes:
        line += f" Named like this app but with another bundle id: {', '.join(lookalikes)}."
    return line


def github_output_lines(out: Resolved) -> list[str]:
    return [
        f"ready={'true' if out.ready else 'false'}",
        f"app_id={out.app_id or ''}",
        f"group_id={out.group_id or ''}",
        f"next_build={out.next_build or ''}",
    ]


def report(out: Resolved, require: bool) -> tuple[str, int]:
    """The one line to print and the exit code."""
    if out.ready:
        return (f"App Store Connect app {out.app_id}; TestFlight group {out.group_id}; "
                f"next build number {out.next_build}."), 0
    if require:
        return f"::error title=App Store Connect not ready::{out.reason}", 1
    return f"::notice title=App Store Connect not ready::{out.reason}", 0


def make_api(key_id: str, issuer_id: str, private_key: str) -> Api:
    import jwt  # pyjwt, on the Mini's python3 (pip3 install --user pyjwt cryptography)

    def mint_token() -> str:
        now = int(time.time())
        return jwt.encode(
            {"iss": issuer_id, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
            private_key, algorithm="ES256", headers={"kid": key_id, "typ": "JWT"},
        )

    def api(method: str, path: str, body: Optional[dict] = None) -> dict:
        headers = {"Authorization": f"Bearer {mint_token()}"}
        data = None
        if body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(ASC_BASE + path, method=method, data=data, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")[:500]
            raise AscError(f"App Store Connect {method} {path} -> HTTP {e.code}: {detail}",
                           status=e.code, detail=detail)

    return api


def main(argv: Optional[list[str]] = None) -> int:
    import argparse
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--require", action="store_true",
                    help="fail when the app record or its internal group is missing")
    args = ap.parse_args(argv)
    key_id = os.environ["ASC_KEY_ID"]
    issuer_id = os.environ["ASC_ISSUER_ID"]
    private_key = base64.b64decode(os.environ["ASC_KEY_BASE64"]).decode()
    bundle_id = os.environ["BUNDLE_ID"]
    group_name = os.environ.get("BETA_GROUP_NAME") or DEFAULT_GROUP
    out = resolve(make_api(key_id, issuer_id, private_key), bundle_id, group_name)
    line, code = report(out, require=args.require)
    print(line)
    gh_out = os.environ.get("GITHUB_OUTPUT")
    if gh_out:
        with open(gh_out, "a") as f:
            f.write("\n".join(github_output_lines(out)) + "\n")
    return code


if __name__ == "__main__":
    sys.exit(main())
