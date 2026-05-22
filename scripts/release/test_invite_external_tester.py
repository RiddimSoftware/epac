#!/usr/bin/env python3
import io
import json
import sys
import unittest
from contextlib import contextmanager
from pathlib import Path
from unittest.mock import MagicMock, patch

SCRIPT = Path(__file__).parent / "invite_external_tester.py"


def load_module() -> dict:
    module: dict = {}
    exec(compile(SCRIPT.read_text(), SCRIPT, "exec"), module)  # noqa: S102
    return module


def _make_response(status_code: int, data: dict) -> MagicMock:
    r = MagicMock()
    r.status_code = status_code
    r.ok = 200 <= status_code < 300
    r.json.return_value = data
    r.text = json.dumps(data)
    return r


@contextmanager
def _mock_asc(mod: dict, secret: dict, token: str = "mock-token"):
    orig_secret = mod["get_asc_secret"]
    orig_token = mod["get_asc_token"]
    mod["get_asc_secret"] = lambda: secret
    mod["get_asc_token"] = lambda *a, **kw: token
    try:
        yield
    finally:
        mod["get_asc_secret"] = orig_secret
        mod["get_asc_token"] = orig_token


MOCK_SECRET = {
    "key_id": "TESTKEY123",
    "issuer_id": "test-issuer-id",
    "private_key": "dummy-private-key",
}

GROUP_RESP = _make_response(200, {
    "data": [{"id": "grp1", "attributes": {"name": "PublicTesting"}}]
})


class TestValidateEmail(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()

    def test_valid_email(self):
        self.assertTrue(self.mod["validate_email"]("user@example.com"))
        self.assertTrue(self.mod["validate_email"]("reporter+tag@example.co.uk"))

    def test_invalid_email(self):
        self.assertFalse(self.mod["validate_email"]("notanemail"))
        self.assertFalse(self.mod["validate_email"]("missing@"))
        self.assertFalse(self.mod["validate_email"]("@nodomain.com"))


class TestFirstNameFromEmail(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()

    def test_dot_separated(self):
        self.assertEqual(self.mod["first_name_from_email"]("john.doe@example.com"), "John")

    def test_underscore_separated(self):
        self.assertEqual(self.mod["first_name_from_email"]("jane_smith@example.com"), "Jane")

    def test_plus_tag(self):
        self.assertEqual(self.mod["first_name_from_email"]("reporter+epac@example.com"), "Reporter")

    def test_plain_username(self):
        self.assertEqual(self.mod["first_name_from_email"]("user@example.com"), "User")


class TestInvalidEmailExits2(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()

    def test_exits_2_before_asc_contact(self):
        sys.argv = ["invite_external_tester.py", "--email", "notanemail", "--group-name", "PublicTesting"]
        with self.assertRaises(SystemExit) as ctx:
            self.mod["main"]()
        self.assertEqual(ctx.exception.code, 2)


class TestNewTesterAdded(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()

    def test_new_email_posts_betaTesters_and_exits_0(self):
        create_resp = _make_response(201, {"data": {"id": "tester1", "type": "betaTesters"}})

        with _mock_asc(self.mod, MOCK_SECRET), \
             patch("requests.get", return_value=GROUP_RESP), \
             patch("requests.post", return_value=create_resp):

            sys.argv = [
                "invite_external_tester.py",
                "--email", "new@example.com",
                "--group-name", "PublicTesting",
            ]
            captured = io.StringIO()
            with self.assertRaises(SystemExit) as ctx:
                sys.stdout = captured
                try:
                    self.mod["main"]()
                finally:
                    sys.stdout = sys.__stdout__

        self.assertEqual(ctx.exception.code, 0)
        output = json.loads(captured.getvalue().strip())
        self.assertTrue(output["added"])
        self.assertEqual(output["tester_id"], "tester1")

    def test_group_relationship_included_in_post_payload(self):
        captured_payload = {}
        create_resp = _make_response(201, {"data": {"id": "tester2", "type": "betaTesters"}})

        def fake_post(url, headers=None, json=None, timeout=30):
            captured_payload.update(json or {})
            return create_resp

        with _mock_asc(self.mod, MOCK_SECRET), \
             patch("requests.get", return_value=GROUP_RESP), \
             patch("requests.post", side_effect=fake_post):

            sys.argv = [
                "invite_external_tester.py",
                "--email", "new2@example.com",
                "--group-name", "PublicTesting",
            ]
            with self.assertRaises(SystemExit):
                sys.stdout = io.StringIO()
                try:
                    self.mod["main"]()
                finally:
                    sys.stdout = sys.__stdout__

        relationships = captured_payload["data"]["relationships"]
        group_ids = [r["id"] for r in relationships["betaGroups"]["data"]]
        self.assertIn("grp1", group_ids)


class TestExistingTesterNotInGroup(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()

    def test_patches_group_relationship_and_exits_0(self):
        conflict_resp = _make_response(409, {"errors": []})
        existing_resp = _make_response(200, {"data": [{"id": "tester1", "type": "betaTesters"}]})
        tester_groups_resp = _make_response(200, {"data": []})  # not yet in PublicTesting
        patch_resp = _make_response(204, {})

        get_responses = [GROUP_RESP, existing_resp, tester_groups_resp]

        with _mock_asc(self.mod, MOCK_SECRET), \
             patch("requests.get", side_effect=get_responses), \
             patch("requests.post", return_value=conflict_resp), \
             patch("requests.patch", return_value=patch_resp):

            sys.argv = [
                "invite_external_tester.py",
                "--email", "existing@example.com",
                "--group-name", "PublicTesting",
            ]
            captured = io.StringIO()
            with self.assertRaises(SystemExit) as ctx:
                sys.stdout = captured
                try:
                    self.mod["main"]()
                finally:
                    sys.stdout = sys.__stdout__

        self.assertEqual(ctx.exception.code, 0)
        output = json.loads(captured.getvalue().strip())
        self.assertFalse(output["added"])
        self.assertEqual(output["reason"], "added_to_group")


class TestExistingTesterAlreadyInGroup(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()

    def test_exits_0_with_already_member(self):
        conflict_resp = _make_response(409, {"errors": []})
        existing_resp = _make_response(200, {"data": [{"id": "tester1", "type": "betaTesters"}]})
        tester_groups_resp = _make_response(200, {"data": [{"id": "grp1"}]})  # already in PublicTesting

        get_responses = [GROUP_RESP, existing_resp, tester_groups_resp]

        with _mock_asc(self.mod, MOCK_SECRET), \
             patch("requests.get", side_effect=get_responses), \
             patch("requests.post", return_value=conflict_resp):

            sys.argv = [
                "invite_external_tester.py",
                "--email", "member@example.com",
                "--group-name", "PublicTesting",
            ]
            captured = io.StringIO()
            with self.assertRaises(SystemExit) as ctx:
                sys.stdout = captured
                try:
                    self.mod["main"]()
                finally:
                    sys.stdout = sys.__stdout__

        self.assertEqual(ctx.exception.code, 0)
        output = json.loads(captured.getvalue().strip())
        self.assertFalse(output["added"])
        self.assertEqual(output["reason"], "already_member")


class TestGhIssueComment(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()

    def test_comment_posted_on_new_tester(self):
        create_resp = _make_response(201, {"data": {"id": "tester1", "type": "betaTesters"}})

        with _mock_asc(self.mod, MOCK_SECRET), \
             patch("requests.get", return_value=GROUP_RESP), \
             patch("requests.post", return_value=create_resp), \
             patch("subprocess.run") as mock_run:

            mock_run.return_value = MagicMock(returncode=0)

            sys.argv = [
                "invite_external_tester.py",
                "--email", "new@example.com",
                "--group-name", "PublicTesting",
                "--gh-issue", "123",
                "--gh-repo", "RiddimSoftware/epac",
            ]
            with self.assertRaises(SystemExit) as ctx:
                sys.stdout = io.StringIO()
                try:
                    self.mod["main"]()
                finally:
                    sys.stdout = sys.__stdout__

        self.assertEqual(ctx.exception.code, 0)
        call_args = mock_run.call_args[0][0]
        self.assertEqual(call_args[0], "gh")
        self.assertIn("123", call_args)
        self.assertIn("RiddimSoftware/epac", call_args)

    def test_no_comment_when_gh_issue_omitted(self):
        create_resp = _make_response(201, {"data": {"id": "tester1", "type": "betaTesters"}})

        with _mock_asc(self.mod, MOCK_SECRET), \
             patch("requests.get", return_value=GROUP_RESP), \
             patch("requests.post", return_value=create_resp), \
             patch("subprocess.run") as mock_run:

            sys.argv = [
                "invite_external_tester.py",
                "--email", "new@example.com",
                "--group-name", "PublicTesting",
            ]
            with self.assertRaises(SystemExit):
                sys.stdout = io.StringIO()
                try:
                    self.mod["main"]()
                finally:
                    sys.stdout = sys.__stdout__

        mock_run.assert_not_called()


class TestAscErrorExitsNonZero(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()

    def test_500_exits_nonzero(self):
        error_resp = _make_response(500, {"errors": [{"detail": "Internal Server Error"}]})

        with _mock_asc(self.mod, MOCK_SECRET), \
             patch("requests.get", return_value=GROUP_RESP), \
             patch("requests.post", return_value=error_resp):

            sys.argv = [
                "invite_external_tester.py",
                "--email", "test@example.com",
                "--group-name", "PublicTesting",
            ]
            with self.assertRaises(SystemExit) as ctx:
                sys.stdout = io.StringIO()
                try:
                    self.mod["main"]()
                finally:
                    sys.stdout = sys.__stdout__

        self.assertNotEqual(ctx.exception.code, 0)


if __name__ == "__main__":
    unittest.main()
