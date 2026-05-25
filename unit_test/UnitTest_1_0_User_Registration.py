"""
DFD 1.0 User Registration (sub-processes 1.1–1.3).

1.1 Get user information — five fields via UserRegister / POST /signup.
1.2 Check existing user — duplicate blocked; GET /check-email for UI.
1.3 Record user information — save_users on successful signup.

Change-password flows are post-registration account maintenance (same data store).
"""

from __future__ import annotations

import unittest
from unittest.mock import Mock, patch

try:
    import server as api  # type: ignore
except Exception as exc:  # pragma: no cover
    api = None
    _import_exc = exc


class UnitTest_1_0_User_Registration(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        if api is None:  # pragma: no cover
            raise unittest.SkipTest(f"Real code import failed: {_import_exc}")

    async def test_dfd_1_1_get_user_info_signup_payload(self) -> None:
        """1.1 — All registration fields accepted by signup."""
        store: dict[str, list[dict]] = {"users": []}

        def _read():
            return store["users"]

        def _save(new):
            store["users"] = list(new)

        u = api.UserRegister(
            firstname="F",
            lastname="L",
            email="reg1@example.com",
            phonenum="081",
            password="secret",
        )
        with patch.object(api, "read_users", new=_read), patch.object(api, "save_users", new=_save):
            out = await api.signup(u)
        self.assertEqual(out["message"], "User created")
        row = store["users"][0]
        self.assertEqual(row["firstname"], "F")
        self.assertEqual(row["lastname"], "L")
        self.assertEqual(row["email"], "reg1@example.com")
        self.assertEqual(row["phonenum"], "081")
        self.assertTrue(row["password"].startswith("$2"))
        self.assertTrue(api.verify_stored_password("secret", row["password"]))

    async def test_dfd_1_2_check_existing_user_duplicate(self) -> None:
        """1.2 — Duplicate email rejected before persist."""
        users = [
            {
                "firstname": "Existing",
                "lastname": "User",
                "email": "dup@example.com",
                "phonenum": "111",
                "password": "pw",
            }
        ]

        def _read_users():
            return users

        save_mock = Mock()
        duplicate = api.UserRegister(
            firstname="X",
            lastname="Y",
            email="DUP@example.com",
            phonenum="222",
            password="pw2",
        )
        with patch.object(api, "read_users", new=_read_users), patch.object(api, "save_users", new=save_mock):
            with self.assertRaises(api.HTTPException) as ctx:
                await api.signup(duplicate)
        self.assertEqual(ctx.exception.status_code, 400)
        self.assertIn("Email already registered", str(ctx.exception.detail))
        save_mock.assert_not_called()

    async def test_dfd_1_2_check_email_endpoint(self) -> None:
        """1.2 — Existence check for registration UI."""

        def _read_users():
            return [{"email": "a@example.com"}]

        with patch.object(api, "read_users", new=_read_users):
            out1 = await api.check_email("A@EXAMPLE.COM")
            out2 = await api.check_email("missing@example.com")
        self.assertEqual(out1, {"exists": True})
        self.assertEqual(out2, {"exists": False})

    async def test_dfd_1_3_record_and_post_registration_password(self) -> None:
        """1.3 — Persist user; optional password update (same User Info store)."""
        
        store: dict[str, list[dict]] = {"users": []}

        def _read_users():
            return store["users"]

        def _save_users(new_users):
            store["users"] = list(new_users)

        u = api.UserRegister(
            firstname="F",
            lastname="L",
            email="new@example.com",
            phonenum="000",
            password="oldpw",
        )
        with patch.object(api, "read_users", new=_read_users), patch.object(api, "save_users", new=_save_users):
            await api.signup(u)
        self.assertEqual(len(store["users"]), 1)

        bad = api.ChangePasswordRequest(email="new@example.com", old_password="wrong", new_password="npw")
        with patch.object(api, "read_users", new=_read_users), patch.object(api, "save_users", new=_save_users):
            with self.assertRaises(api.HTTPException) as ctx1:
                await api.change_password(bad)
        self.assertEqual(ctx1.exception.status_code, 401)

        nf = api.ChangePasswordRequest(email="none@example.com", old_password="x", new_password="y")
        with patch.object(api, "read_users", new=_read_users), patch.object(api, "save_users", new=_save_users):
            with self.assertRaises(api.HTTPException) as ctx2:
                await api.change_password(nf)
        self.assertEqual(ctx2.exception.status_code, 404)

        ok = api.ChangePasswordRequest(email="new@example.com", old_password="oldpw", new_password="newpw")
        with patch.object(api, "read_users", new=_read_users), patch.object(api, "save_users", new=_save_users):
            out2 = await api.change_password(ok)
        self.assertIn("Password updated", out2["message"])
        self.assertTrue(api.verify_stored_password("newpw", store["users"][0]["password"]))


if __name__ == "__main__":  # pragma: no cover
    unittest.main(verbosity=2)
