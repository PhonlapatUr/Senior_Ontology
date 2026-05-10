"""
DFD 3.0 Find a route with no pollution preference (backend slice).

Scope: After the Flutter app obtains routes (Google Map API) from Origin/Destination,
POST /scoreRoutes scores them without focus_pollutants (no preferred pollutant).

3.1 Get route input — represented by encoded polyline + distance/duration on each route.
3.2 Generate route list — client-side in app; here we score one candidate route.
3.3 Get selected route — client-side selection; tests use one route id.
3.4 Generate detail of route — di, dt, dp, dw and risk_score in API response.

Supporting tests mock Pollution API and Relative Humidity API behaviour used inside scoreRoutes.
"""

from __future__ import annotations

import os
import sys
import unittest
from unittest.mock import AsyncMock, patch

import pandas as pd
import time

_fix_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _fix_dir)
from dfd_route_fixtures import asyncio_run, score_routes_fixture  # noqa: E402

try:
    import server as api
except Exception as exc:  # pragma: no cover
    api = None
    _import_exc = exc


class UnitTest_3_0_DSS_Support(unittest.TestCase):
    def setUp(self) -> None:
        if api is None:  # pragma: no cover
            self.skipTest(f"Real code import failed: {_import_exc}")

    def test_route_pollution_score_equal_to_global_mean_is_half(self) -> None:
        critic_w = {k: 1.0 / len(api.CRITERIA) for k in api.CRITERIA}
        g_mean = {k: 10.0 for k in api.CRITERIA}
        g_std = {k: 2.0 for k in api.CRITERIA}
        avg = {k: 10.0 for k in api.CRITERIA}
        score, norms = api.route_pollution_score(avg, critic_w, g_mean, g_std)
        self.assertAlmostEqual(score, 0.5, places=6)
        for k in api.CRITERIA:
            self.assertAlmostEqual(norms[k], 0.5, places=6)

    def test_route_pollution_score_weights_shift_toward_high_pollutant(self) -> None:
        critic_w = {k: 0.06 for k in api.CRITERIA}
        critic_w["pm2.5"] = 0.7
        s = sum(critic_w.values())
        critic_w = {k: v / s for k, v in critic_w.items()}
        g_mean = {k: 0.0 for k in api.CRITERIA}
        g_std = {k: 1.0 for k in api.CRITERIA}
        low = {k: 0.0 for k in api.CRITERIA}
        high_pm = {k: 0.0 for k in api.CRITERIA}
        high_pm["pm2.5"] = 5.0
        s_low, _ = api.route_pollution_score(low, critic_w, g_mean, g_std)
        s_high, norms_high = api.route_pollution_score(high_pm, critic_w, g_mean, g_std)
        self.assertGreater(s_high, s_low)
        self.assertGreater(norms_high["pm2.5"], 0.5)

    def test_evaluate_route_all_branches(self) -> None:
        route = {"distance_meters": 500.0, "duration_seconds": 50.0}
        max_vals = {"distance": 1000.0, "time": 100.0}
        cw = {k: 1.0 / len(api.CRITERIA) for k in api.CRITERIA}
        gm = {k: 0.0 for k in api.CRITERIA}
        gs = {k: 1.0 for k in api.CRITERIA}
        avg = {k: 0.0 for k in api.CRITERIA}
        out_none = api.evaluate_route(route, max_vals, cw, gm, gs, None, [], 60.0)
        out_weather = api.evaluate_route(route, max_vals, cw, gm, gs, None, [3], 80.0)
        out_poll = api.evaluate_route(route, max_vals, cw, gm, gs, avg, [], 60.0)
        out_both = api.evaluate_route(route, max_vals, cw, gm, gs, avg, [2], 60.0)
        self.assertGreaterEqual(out_none["final_score"], 0.0)
        self.assertGreaterEqual(out_weather["final_score"], 0.0)
        self.assertGreaterEqual(out_poll["final_score"], 0.0)
        self.assertGreaterEqual(out_both["final_score"], 0.0)
        self.assertFalse(out_none["weather_valid"])
        self.assertTrue(out_weather["weather_valid"])

    def test_critic_weights_and_weather_score_branches(self) -> None:
        df_empty = pd.DataFrame(columns=api.CRITERIA)
        w_empty = api.critic_weights(df_empty)
        self.assertAlmostEqual(sum(w_empty.values()), 1.0, places=6)
        df_two = pd.DataFrame(
            [
                {"pm2.5": 100.0, "pm10": 0.0, "co": 0.0, "no2": 0.0, "o3": 0.0, "so2": 0.0},
                {"pm2.5": 0.0, "pm10": 100.0, "co": 0.0, "no2": 0.0, "o3": 0.0, "so2": 0.0},
            ]
        )
        w_two = api.critic_weights(df_two)
        self.assertAlmostEqual(sum(w_two.values()), 1.0, places=6)
        self.assertEqual(api.weather_score(None), 2)
        self.assertEqual(api.weather_score(76), 3)
        self.assertEqual(api.weather_score(30), 1)
        self.assertEqual(api.weather_score(50), 2)

    def test_extract_pollutants_missing_concentration_and_alias(self) -> None:
        js = {
            "pollutants": [
                {"code": "pm25", "concentration": {"value": 7}},
                {"code": "p25", "concentration": {"value": 8}},
                {"code": "so2", "concentration": {"value": None}},
            ]
        }
        out = api.extract_pollutants(js)
        self.assertEqual(out["pm2.5"], 8.0)
        self.assertEqual(out["so2"], 9999.0)
        for k in api.CRITERIA:
            self.assertIn(k, out)

    def test_decode_poly_and_sample_points_and_cache_key(self) -> None:
        self.assertEqual(api.decode_poly(""), [])
        self.assertIsInstance(api.decode_poly("NOT_A_POLYLINE"), list)
        pts = [(0, 0), (1, 1), (2, 2), (3, 3)]
        self.assertEqual(api.sample_points(pts, 2), [(0, 0), (2, 2)])
        self.assertEqual(api.sample_points(pts, 0), pts)
        self.assertEqual(api.cache_key(10.123456, 20.987654), "10.1235,20.9877")

    def test_fetch_aqi_cache_hit_and_exception_branch(self) -> None:
        cache_client = type("CacheClient", (), {})()
        cache_client.post = AsyncMock()
        api.AQ_CACHE.clear()
        key = api.cache_key(1.0, 2.0)
        api.AQ_CACHE[key] = (time.time(), {"pollutants": [{"code": "pm10"}]})
        out = asyncio_run(api.fetch_aqi(cache_client, 1.0, 2.0))
        self.assertIn("pollutants", out)
        cache_client.post.assert_not_called()

        class _Client2:
            async def post(self, *_args, **_kwargs):
                raise RuntimeError("boom")

        api.AQ_CACHE.clear()
        out2 = asyncio_run(api.fetch_aqi(_Client2(), 3.0, 4.0))
        self.assertEqual(out2, {"pollutants": []})

    def test_ontology_explain_and_adjustment_branches(self) -> None:
        label, exp = api.ontology_explain_route({}, {}, {})
        self.assertEqual(label, "Unknown")
        self.assertEqual(exp["total_score"], 0.0)
        avg = {"pm2.5": 10.0, "pm10": 5.0}
        pollutant_sources = {"PM2.5": {"Factory"}, "PM10": {"SeaSalt"}}
        source_types = {"Factory": {"HumanSources"}, "SeaSalt": {"NaturalSources"}}
        label2, exp2 = api.ontology_explain_route(avg, pollutant_sources, source_types)
        self.assertIn(label2, {"Mixed", "HumanSources", "NaturalSources"})
        self.assertGreater(exp2["total_score"], 0.0)
        base = [{"final_score": 1.0, "avg_pollution_raw": {"pm2.5": 0.0}}]
        adj = api.apply_ontology_adjustment(base, pollutant_sources, source_types, penalty_max=2.0)
        self.assertEqual(len(adj), 1)
        self.assertIn("ontology_info", adj[0])

    def test_get_ontology_maps_missing_file_branch(self) -> None:
        api._ONTOLOGY_MAPS_CACHE = None
        with patch.object(api, "ONTOLOGY_PATH", new="/tmp/does-not-exist.ttl"):
            maps = api._get_ontology_maps()
        self.assertEqual(maps, ({}, {}))

    def test_fetch_humidity_branches(self) -> None:
        api.HUMIDITY_CACHE.clear()
        k = api.cache_key(1.0, 2.0)
        api.HUMIDITY_CACHE[k] = (time.time(), 55.0)
        humidity_cache_client = type("HumidityCacheClient", (), {})()
        humidity_cache_client.get = AsyncMock()
        h = asyncio_run(api.fetch_humidity(humidity_cache_client, 1.0, 2.0))
        self.assertEqual(h, 55.0)
        humidity_cache_client.get.assert_not_called()

        api.HUMIDITY_CACHE.clear()

        class _Resp:
            def __init__(self, status_code: int, payload=None, text: str = ""):
                self.status_code = status_code
                self._payload = payload
                self.text = text

            def json(self):
                return self._payload

        class _Client2:
            async def get(self, url, **_kwargs):
                if "data.tmd.go.th" in url:
                    return _Resp(
                        200,
                        {
                            "WeatherForecasts": [
                                {"forecasts": [{"data": {"rh": 66.0}}]},
                            ]
                        },
                        text="ok",
                    )

        h2 = asyncio_run(api.fetch_humidity(_Client2(), 10.0, 20.0))
        self.assertEqual(h2, 66.0)

        api.HUMIDITY_CACHE.clear()
        api.OPEN_METEO_BACKOFF_UNTIL = 0.0

        class _Client3:
            async def get(self, url, **_kwargs):
                if "data.tmd.go.th" in url:
                    return _Resp(401, payload={}, text="no")
                if "api.open-meteo.com" in url:
                    return _Resp(200, payload={"hourly": {"relative_humidity_2m": [None, 44.0]}})

        h3 = asyncio_run(api.fetch_humidity(_Client3(), 11.0, 22.0))
        self.assertEqual(h3, 44.0)

        api.HUMIDITY_CACHE.clear()
        api.OPEN_METEO_BACKOFF_UNTIL = 0.0

        class _Client4:
            async def get(self, url, **_kwargs):
                if "data.tmd.go.th" in url:
                    return _Resp(401, payload={}, text="no")
                if "api.open-meteo.com" in url:
                    return _Resp(429, payload={}, text="rate")
                if "api.met.no" in url:
                    return _Resp(500, payload={}, text="err")
                if "wttr.in" in url:
                    return _Resp(503, payload={}, text="busy")

        h4 = asyncio_run(api.fetch_humidity(_Client4(), 12.0, 23.0))
        self.assertIsNone(h4)

        api.HUMIDITY_CACHE.clear()
        api.OPEN_METEO_BACKOFF_UNTIL = time.time() + 999

        class _Client5:
            async def get(self, url, **_kwargs):
                if "data.tmd.go.th" in url:
                    return _Resp(401, payload={}, text="no")
                if "api.met.no" in url:
                    return _Resp(
                        200,
                        payload={
                            "properties": {
                                "timeseries": [
                                    {"data": {"instant": {"details": {"relative_humidity": 77.0}}}}
                                ]
                            }
                        },
                        text="ok",
                    )

        h5 = asyncio_run(api.fetch_humidity(_Client5(), 13.0, 24.0))
        self.assertEqual(h5, 77.0)


class UnitTest_3_0_Route_No_Pollution_Preference(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        if api is None:  # pragma: no cover
            raise unittest.SkipTest(f"Real code import failed: {_import_exc}")

    async def test_dfd_3_0_score_routes_without_focus_pollutants(self) -> None:
        """3.0 — POST /scoreRoutes with focus_pollutants=None (no preferred pollution)."""
        decode, aqi_mock, hum_mock, ScoreReq = score_routes_fixture()
        captured_weights: list[dict] = []
        captured_avg: dict = {}
        orig = api.route_pollution_score

        def _wrap(avg_pollution, critic_w, g_mean, g_std):
            captured_weights.append(dict(critic_w))
            captured_avg.update(avg_pollution)
            return orig(avg_pollution, critic_w, g_mean, g_std)

        with (
            patch.object(api, "decode_poly", new=decode),
            patch.object(api, "fetch_aqi", new=AsyncMock(side_effect=aqi_mock)),
            patch.object(api, "fetch_humidity", new=AsyncMock(side_effect=hum_mock)),
            patch.object(api, "route_pollution_score", new=_wrap),
        ):
            resp = await api.score_routes(ScoreReq(None))

        self.assertEqual(len(resp.scores), 1)
        s0 = resp.scores[0]
        self.assertGreaterEqual(s0.risk_score, 0.0)
        self.assertLessEqual(s0.risk_score, 1.0)
        self.assertEqual(len(captured_weights), 1)
        self.assertAlmostEqual(sum(captured_weights[0].values()), 1.0, places=5)
        self.assertEqual(captured_avg["pm10"], 0.0)


if __name__ == "__main__":  # pragma: no cover
    unittest.main(verbosity=2)
