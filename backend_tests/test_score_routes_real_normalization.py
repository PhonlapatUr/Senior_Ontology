from __future__ import annotations

import unittest
from unittest.mock import AsyncMock, patch

try:
    import server as api  # type: ignore
except Exception as exc:  # pragma: no cover
    api = None
    _import_exc = exc


class RealScoreRoutesNormalizationTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        if api is None:  # pragma: no cover
            raise unittest.SkipTest(f"Real code import failed: {_import_exc}")

    async def test_missing_pollutant_normalized_to_zero(self) -> None:
        captured = {}

        original = api.route_pollution_score

        def wrapper(avg_pollution, critic_w, g_mean, g_std):
            # Inspect avg_p after server normalization (9999.0 -> 0.0)
            captured.update(avg_pollution)
            return original(avg_pollution, critic_w, g_mean, g_std)

        def _decode_poly(_encoded: str):
            return [(10.0, 20.0), (10.1, 20.1)]

        async def _fetch_aqi_mock(_client, _lat, _lon):
            # pm10 is missing => extract_pollutants will set pm10 to 9999.0,
            # then server replaces 9999.0 with 0.0 before calling route_pollution_score.
            return {
                "pollutants": [
                    {"code": "pm2.5", "concentration": {"value": 10}},
                    {"code": "pm10", "concentration": {"value": None}},
                    {"code": "co", "concentration": {"value": 1}},
                    {"code": "no2", "concentration": {"value": 30}},
                    {"code": "o3", "concentration": {"value": 40}},
                    {"code": "so2", "concentration": {"value": 5}},
                ]
            }

        async def _fetch_humidity_mock(_client, lat, _lon):
            return 30.0 if lat < 10.05 else 80.0

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
            patch.object(api, "fetch_aqi", new=AsyncMock(side_effect=_fetch_aqi_mock)),
            patch.object(api, "fetch_humidity", new=AsyncMock(side_effect=_fetch_humidity_mock)),
            patch.object(api, "route_pollution_score", new=wrapper),
        ):
            resp = await api.score_routes(_ScoreReq())

        self.assertEqual(len(resp.scores), 1)
        self.assertIn("pm10", captured)
        self.assertEqual(captured["pm10"], 0.0)


if __name__ == "__main__":  # pragma: no cover
    unittest.main(verbosity=2)

