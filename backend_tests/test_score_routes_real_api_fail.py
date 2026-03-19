from __future__ import annotations

import unittest
from unittest.mock import AsyncMock, patch

try:
    import server as api  # type: ignore
except Exception as exc:  # pragma: no cover
    api = None
    _import_exc = exc


class RealScoreRoutesApiFailTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        if api is None:  # pragma: no cover
            raise unittest.SkipTest(f"Real code import failed: {_import_exc}")

    async def test_api_fail_fetch_aqi_returns_500(self) -> None:
        def _decode_poly(_encoded: str):
            return [(10.0, 20.0), (10.1, 20.1)]

        async def _fetch_aqi_fail(*_args, **_kwargs):
            raise RuntimeError("Simulated external AQ API failure")

        class _RouteReq:
            def __init__(self) -> None:
                self.id = "1"
                self.encoded_polyline = "ANY_VALID_STRING"
                self.distance_meters = 1000.0
                self.duration_seconds = 100.0

        class _ScoreReq:
            def __init__(self) -> None:
                self.routes = [_RouteReq()]
                self.sample_stride = 1
                self.focus_pollutants = None
                self.use_ontology = False

        with (
            patch.object(api, "decode_poly", new=_decode_poly),
            patch.object(api, "fetch_aqi", new=AsyncMock(side_effect=_fetch_aqi_fail)),
            patch.object(api, "fetch_humidity", new=AsyncMock(return_value=50.0)),
        ):
            with self.assertRaises(api.HTTPException) as ctx:
                await api.score_routes(_ScoreReq())

        self.assertEqual(ctx.exception.status_code, 500)
        self.assertIn("Simulated external AQ API failure", str(ctx.exception.detail))


if __name__ == "__main__":  # pragma: no cover
    unittest.main(verbosity=2)

