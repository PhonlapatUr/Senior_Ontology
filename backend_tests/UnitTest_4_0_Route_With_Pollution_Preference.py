"""
DFD 4.0 Find a route with pollution preference (backend slice).

4.1 Get route input — same as 3.1 (polyline + metrics from app after Map API).
4.2 Get pollution input — focus_pollutants list (e.g. pm2.5) on POST /scoreRoutes.
4.3–4.5 — Route list, selection, and detail are primarily client-side; server returns
scored detail (risk_score, di, dt, dp, dw) per route with preference applied to critic weights.
"""

from __future__ import annotations

import os
import sys
import unittest
from unittest.mock import AsyncMock, patch

_fix_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _fix_dir)
from dfd_route_fixtures import score_routes_fixture  # noqa: E402

try:
    import server as api
except Exception as exc:  # pragma: no cover
    api = None
    _import_exc = exc


class UnitTest_4_0_Route_With_Pollution_Preference(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        if api is None:  # pragma: no cover
            raise unittest.SkipTest(f"Real code import failed: {_import_exc}")

    async def test_dfd_4_0_score_routes_with_focus_pollutants(self) -> None:
        """4.0 / 4.2 — Baseline scoring then scoring with preferred pollutant weight boost."""
        decode, aqi_mock, hum_mock, ScoreReq = score_routes_fixture()
        captured_weights: list[dict] = []
        orig = api.route_pollution_score

        def _wrap(avg_pollution, critic_w, g_mean, g_std):
            captured_weights.append(dict(critic_w))
            return orig(avg_pollution, critic_w, g_mean, g_std)

        with (
            patch.object(api, "decode_poly", new=decode),
            patch.object(api, "fetch_aqi", new=AsyncMock(side_effect=aqi_mock)),
            patch.object(api, "fetch_humidity", new=AsyncMock(side_effect=hum_mock)),
            patch.object(api, "route_pollution_score", new=_wrap),
        ):
            await api.score_routes(ScoreReq(None))
            await api.score_routes(ScoreReq(["pm2.5"]))

        self.assertEqual(len(captured_weights), 2)
        self.assertGreater(captured_weights[1]["pm2.5"], captured_weights[0]["pm2.5"])
        self.assertAlmostEqual(sum(captured_weights[1].values()), 1.0, places=5)


if __name__ == "__main__":  # pragma: no cover
    unittest.main(verbosity=2)
