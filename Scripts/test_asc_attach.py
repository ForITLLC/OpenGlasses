import copy
import unittest
from unittest import mock

import asc_attach


class GroupApi:
    def __init__(self, attributes, ignore_update=False):
        self.attributes = dict(attributes)
        self.ignore_update = ignore_update
        self.calls = []

    def __call__(self, method, path, **kwargs):
        self.calls.append((method, path, copy.deepcopy(kwargs)))
        if path != "/betaGroups/group":
            raise AssertionError("Unexpected endpoint: " + path)
        if method == "PATCH":
            if not self.ignore_update:
                self.attributes.update(kwargs["body"]["data"]["attributes"])
        elif method != "GET":
            raise AssertionError("Unexpected method: " + method)
        return {"data": {"type": "betaGroups", "id": "group",
                         "attributes": dict(self.attributes)}}


class PhoneOnlyGroupTests(unittest.TestCase):
    def test_existing_phone_only_group_needs_no_write(self):
        api = GroupApi({"isInternalGroup": True,
                        "iosBuildsAvailableForAppleSiliconMac": False,
                        "iosBuildsAvailableForAppleVision": False})
        asc_attach.ensure_phone_only_group(api, "group")
        self.assertEqual([m for m, _, _ in api.calls], ["GET"])

    def test_turns_off_both_flags_without_changing_group_access(self):
        api = GroupApi({"isInternalGroup": True, "hasAccessToAllBuilds": True,
                        "iosBuildsAvailableForAppleSiliconMac": True,
                        "iosBuildsAvailableForAppleVision": True})
        asc_attach.ensure_phone_only_group(api, "group")
        self.assertEqual([m for m, _, _ in api.calls], ["GET", "PATCH", "GET"])
        self.assertEqual(api.calls[1][2]["body"]["data"]["attributes"], {
            "iosBuildsAvailableForAppleSiliconMac": False,
            "iosBuildsAvailableForAppleVision": False})
        self.assertTrue(api.attributes["hasAccessToAllBuilds"])

    def test_missing_flags_are_not_treated_as_verified_disabled(self):
        api = GroupApi({"isInternalGroup": True})
        asc_attach.ensure_phone_only_group(api, "group")
        self.assertIn("PATCH", [m for m, _, _ in api.calls])

    def test_noninternal_group_is_never_changed(self):
        api = GroupApi({"isInternalGroup": False})
        with self.assertRaisesRegex(ValueError, "not confirmed internal"):
            asc_attach.ensure_phone_only_group(api, "group")
        self.assertEqual([m for m, _, _ in api.calls], ["GET"])

    def test_ignored_update_cannot_claim_success(self):
        api = GroupApi({"isInternalGroup": True,
                        "iosBuildsAvailableForAppleSiliconMac": True,
                        "iosBuildsAvailableForAppleVision": True}, ignore_update=True)
        with self.assertRaisesRegex(ValueError, "did not read back"):
            asc_attach.ensure_phone_only_group(api, "group")

    def test_distribution_run_uses_phone_only_group_update(self):
        api = GroupApi({"isInternalGroup": True,
                        "iosBuildsAvailableForAppleSiliconMac": True,
                        "iosBuildsAvailableForAppleVision": True})
        with mock.patch.object(asc_attach, "wait_for_build", return_value="build"), \
             mock.patch.object(asc_attach, "ensure_compliance", return_value="already answered"), \
             mock.patch.object(asc_attach, "attach", return_value="already attached"):
            result = asc_attach.run(api, "app", "group", "36",
                                    now=lambda: 0, sleep=lambda _: None)
        self.assertEqual(result, 0)
        self.assertFalse(api.attributes["iosBuildsAvailableForAppleSiliconMac"])
        self.assertFalse(api.attributes["iosBuildsAvailableForAppleVision"])


if __name__ == "__main__":
    unittest.main()
