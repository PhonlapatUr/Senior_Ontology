from __future__ import annotations

import unittest
from unittest.mock import AsyncMock, patch

try:
    import server as api  # type: ignore
except Exception as exc:  # pragma: no cover
    api = None
    _import_exc = exc


class RealScoreRoutesHappyCaseTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        if api is None:  # pragma: no cover
            raise unittest.SkipTest(f"Real code import failed: {_import_exc}")

    async def test_happy_case_returns_valid_scores(self) -> None:
        # Mock external inputs only. DSS math should use real code.
        def _decode_poly(_encoded: str):
            return [(10.0, 20.0), (10.1, 20.1)]

        async def _fetch_aqi_mock(_client, _lat, _lon):
            return {
                "pollutants": [
                    {"code": "pm2.5", "concentration": {"value": 10}},
                    {"code": "pm10", "concentration": {"value": 20}},
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
        ):
            resp = await api.score_routes(_ScoreReq())

        self.assertEqual(len(resp.scores), 1)
        score = resp.scores[0]

        for attr in ["risk_score", "di", "dt", "dp", "dw", "avgHumidity"]:
            self.assertTrue(hasattr(score, attr))

        for v in [score.risk_score, score.di, score.dt, score.dp, score.dw]:
            self.assertGreaterEqual(v, 0.0)
            self.assertLessEqual(v, 1.0)


if __name__ == "__main__":  # pragma: no cover
    unittest.main(verbosity=2)

