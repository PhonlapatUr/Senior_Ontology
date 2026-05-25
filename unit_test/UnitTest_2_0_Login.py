"""
DFD 2.0 Login (sub-processes 2.1–2.2 and process 2.0 completion).

2.1 Get user information — email + password as LoginRequest.
2.2 Check existing user — match email (case-insensitive) and exact password against User Info.
2.0 Login — return user subset to client on success.
"""

from __future__ import annotations

import unittest
from unittest.mock import patch

try:
    import server as api  # type: ignore
except Exception as exc:  # pragma: no cover
    api = None
    _import_exc = exc


class UnitTest_2_0_Login(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        if api is None:  # pragma: no cover
            raise unittest.SkipTest(f"Real code import failed: {_import_exc}")

    async def test_dfd_2_0_login_success_returns_user_info(self) -> None:
        users = [
            {
                "firstname": "Ada",
                "lastname": "Lovelace",
                "email": "ada@example.com",
                "phonenum": "555",
                "password": "compute",
            }
        ]

        def _read_users():
            return users

        req = api.LoginRequest(email="ada@example.com", password="compute")
        with patch.object(api, "read_users", new=_read_users):
            out = await api.login(req)
        self.assertEqual(out["message"], "Success")
        self.assertEqual(out["user"]["firstname"], "Ada")
        self.assertEqual(out["user"]["email"], "ada@example.com")

    async def test_dfd_2_2_case_insensitive_email(self) -> None:
        users = [
            {
                "firstname": "Bob",
                "lastname": "Smith",
                "email": "Bob.Case@Example.COM",
                "phonenum": "999",
                "password": "sekret",
            }
        ]

        def _read_users():
            return users

        req = api.LoginRequest(email="bob.case@example.com", password="sekret")
        with patch.object(api, "read_users", new=_read_users):
            out = await api.login(req)
        self.assertEqual(out["message"], "Success")
        self.assertEqual(out["user"]["email"], "Bob.Case@Example.COM")

    async def test_dfd_2_2_wrong_password(self) -> None:
        users = [
            {
                "firstname": "Login",
                "lastname": "User",
                "email": "login@example.com",
                "phonenum": "123",
                "password": "secretpw",
            }
        ]

        def _read_users():
            return users

        bad_req = api.LoginRequest(email="login@example.com", password="wrong")
        with patch.object(api, "read_users", new=_read_users):
            with self.assertRaises(api.HTTPException) as ctx:
                await api.login(bad_req)
        self.assertEqual(ctx.exception.status_code, 401)
        self.assertIn("Invalid credentials", str(ctx.exception.detail))

    async def test_dfd_2_2_unknown_email(self) -> None:
        users = [
            {
                "firstname": "Only",
                "lastname": "One",
                "email": "one@example.com",
                "phonenum": "1",
                "password": "pw",
            }
        ]

        def _read_users():
            return users

        req = api.LoginRequest(email="nobody@example.com", password="pw")
        with patch.object(api, "read_users", new=_read_users):
            with self.assertRaises(api.HTTPException) as ctx:
                await api.login(req)
        self.assertEqual(ctx.exception.status_code, 401)
        self.assertIn("Invalid credentials", str(ctx.exception.detail))

    def test_api_health_root_available(self) -> None:
        """Supporting: service up before client login."""
        self.assertIn("message", api.root())
        self.assertEqual(api.health(), {"ok": True})


if __name__ == "__main__":  # pragma: no cover
    unittest.main(verbosity=2)
