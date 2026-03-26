from __future__ import annotations

import unittest
from unittest.mock import AsyncMock, patch

import pandas as pd
import time

try:
    import server as api  # type: ignore
except Exception as exc:  # pragma: no cover
    api = None
    _import_exc = exc


class UnitTestScorePollutant(unittest.TestCase):
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
        # Some arbitrary strings can still decode into coordinates; ensure we don't crash and return a list.
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
        # Empty avg -> Unknown
        label, exp = api.ontology_explain_route({}, {}, {})
        self.assertEqual(label, "Unknown")
        self.assertEqual(exp["total_score"], 0.0)

        # HumanSources / NaturalSources / Mixed labels via manual maps
        avg = {"pm2.5": 10.0, "pm10": 5.0}
        pollutant_sources = {"PM2.5": {"Factory"}, "PM10": {"SeaSalt"}}
        source_types = {"Factory": {"HumanSources"}, "SeaSalt": {"NaturalSources"}}
        label2, exp2 = api.ontology_explain_route(avg, pollutant_sources, source_types)
        self.assertIn(label2, {"Mixed", "HumanSources", "NaturalSources"})
        self.assertGreater(exp2["total_score"], 0.0)

        # apply_ontology_adjustment total==0 branch and penalty floor branch
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
        # Cache hit
        api.HUMIDITY_CACHE.clear()
        k = api.cache_key(1.0, 2.0)
        api.HUMIDITY_CACHE[k] = (time.time(), 55.0)

        humidity_cache_client = type("HumidityCacheClient", (), {})()
        humidity_cache_client.get = AsyncMock()

        h = asyncio_run(api.fetch_humidity(humidity_cache_client, 1.0, 2.0))
        self.assertEqual(h, 55.0)
        humidity_cache_client.get.assert_not_called()

        # TMD 200 valid payload
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

        # TMD non-200 -> open-meteo 200 -> returns first non-null
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

        # open-meteo 429 triggers backoff then met.no non-200 -> None
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

        h4 = asyncio_run(api.fetch_humidity(_Client4(), 12.0, 23.0))
        self.assertIsNone(h4)

        # backoff active skips open-meteo and goes to met.no success path
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


def asyncio_run(coro):
    import asyncio

    return asyncio.run(coro)


class UnitTestScorePollutantIntegration(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        if api is None:  # pragma: no cover
            raise unittest.SkipTest(f"Real code import failed: {_import_exc}")

    async def test_focus_pollutants_and_missing_normalization(self) -> None:
        captured_weights = []
        captured_avg = {}

        def _decode_poly(_encoded: str):
            return [(10.0, 20.0), (10.1, 20.1)]

        async def _fetch_aqi_mock(_client, _lat, _lon):
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

        async def _fetch_humidity_mock(_client, _lat, _lon):
            return 50.0

        class _RouteReq:
            def __init__(self) -> None:
                self.id = "1"
                self.encoded_polyline = "x"
                self.distance_meters = 1000.0
                self.duration_seconds = 100.0

        class _ScoreReq:
            def __init__(self, focus: list[str] | None) -> None:
                self.routes = [_RouteReq()]
                self.sample_stride = 1
                self.focus_pollutants = focus
                self.use_ontology = False

        orig = api.route_pollution_score

        def _wrap(avg_pollution, critic_w, g_mean, g_std):
            captured_weights.append(dict(critic_w))
            captured_avg.update(avg_pollution)
            return orig(avg_pollution, critic_w, g_mean, g_std)

        with (
            patch.object(api, "decode_poly", new=_decode_poly),
            patch.object(api, "fetch_aqi", new=AsyncMock(side_effect=_fetch_aqi_mock)),
            patch.object(api, "fetch_humidity", new=AsyncMock(side_effect=_fetch_humidity_mock)),
            patch.object(api, "route_pollution_score", new=_wrap),
        ):
            await api.score_routes(_ScoreReq(None))
            await api.score_routes(_ScoreReq(["pm2.5"]))

        self.assertEqual(len(captured_weights), 2)
        self.assertGreater(captured_weights[1]["pm2.5"], captured_weights[0]["pm2.5"])
        self.assertEqual(captured_avg["pm10"], 0.0)


if __name__ == "__main__":  # pragma: no cover
    unittest.main(verbosity=2)
