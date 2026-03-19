from __future__ import annotations

import unittest
from unittest.mock import patch

try:
    import server as api  # type: ignore
except Exception as exc:  # pragma: no cover
    api = None
    _import_exc = exc


class RealAuthSignupLoginCasesTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        if api is None:  # pragma: no cover
            raise unittest.SkipTest(f"Real code import failed: {_import_exc}")

    async def test_signup_duplicate_email_returns_400(self) -> None:
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

        def _save_users(_new_users):
            raise AssertionError("save_users should not run on duplicate email")

        duplicate = api.UserRegister(
            firstname="X",
            lastname="Y",
            email="DUP@example.com",
            phonenum="222",
            password="pw2",
        )

        with patch.object(api, "read_users", new=_read_users), patch.object(api, "save_users", new=_save_users):
            with self.assertRaises(api.HTTPException) as ctx:
                await api.signup(duplicate)

        self.assertEqual(ctx.exception.status_code, 400)
        self.assertIn("Email already registered", str(ctx.exception.detail))

    async def test_login_wrong_password_returns_401(self) -> None:
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


if __name__ == "__main__":  # pragma: no cover
    unittest.main(verbosity=2)

