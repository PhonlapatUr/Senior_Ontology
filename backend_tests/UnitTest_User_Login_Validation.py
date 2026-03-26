from __future__ import annotations

import unittest
from unittest.mock import Mock, patch

try:
    import server as api  # type: ignore
except Exception as exc:  # pragma: no cover
    api = None
    _import_exc = exc


class UnitTestUserLoginValidation(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        if api is None:  # pragma: no cover
            raise unittest.SkipTest(f"Real code import failed: {_import_exc}")

    async def test_login_success_returns_payload(self) -> None:
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

    async def test_login_email_case_insensitive(self) -> None:
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

    async def test_login_unknown_email_returns_401(self) -> None:
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

    async def test_root_health_and_check_email(self) -> None:
        # root/health are sync, check_email is async.
        self.assertIn("message", api.root())
        self.assertEqual(api.health(), {"ok": True})

        def _read_users():
            return [{"email": "a@example.com"}, {"email": "b@example.com"}]

        with patch.object(api, "read_users", new=_read_users):
            out1 = await api.check_email("A@EXAMPLE.COM")
            out2 = await api.check_email("missing@example.com")
        self.assertEqual(out1, {"exists": True})
        self.assertEqual(out2, {"exists": False})

    async def test_signup_success_and_change_password_branches(self) -> None:
        # Use a shared mutable store so read_users always sees the latest saved list.
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
            out = await api.signup(u)
        self.assertEqual(out["message"], "User created")
        self.assertEqual(len(store["users"]), 1)

        # Wrong old password -> 401
        bad = api.ChangePasswordRequest(email="new@example.com", old_password="wrong", new_password="npw")
        with patch.object(api, "read_users", new=_read_users), patch.object(api, "save_users", new=_save_users):
            with self.assertRaises(api.HTTPException) as ctx1:
                await api.change_password(bad)
        self.assertEqual(ctx1.exception.status_code, 401)

        # Email not found -> 404
        nf = api.ChangePasswordRequest(email="none@example.com", old_password="x", new_password="y")
        with patch.object(api, "read_users", new=_read_users), patch.object(api, "save_users", new=_save_users):
            with self.assertRaises(api.HTTPException) as ctx2:
                await api.change_password(nf)
        self.assertEqual(ctx2.exception.status_code, 404)

        # Success -> 200
        ok = api.ChangePasswordRequest(email="new@example.com", old_password="oldpw", new_password="newpw")
        with patch.object(api, "read_users", new=_read_users), patch.object(api, "save_users", new=_save_users):
            out2 = await api.change_password(ok)
        self.assertIn("Password updated", out2["message"])
        self.assertEqual(store["users"][0]["password"], "newpw")


if __name__ == "__main__":  # pragma: no cover
    unittest.main(verbosity=2)
