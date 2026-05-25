"""Shared mocks for DFD 3.0 / 4.0 route scoring tests (POST /scoreRoutes)."""

from __future__ import annotations


def asyncio_run(coro):
    import asyncio

    return asyncio.run(coro)


def score_routes_fixture():
    def decode_poly(_encoded: str):
        return [(10.0, 20.0), (10.1, 20.1)]

    async def fetch_aqi_mock(_client, _lat, _lon):
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

    async def fetch_humidity_mock(_client, _lat, _lon):
        return 50.0

    class RouteReq:
        def __init__(self) -> None:
            self.id = "1"
            self.encoded_polyline = "x"
            self.distance_meters = 1000.0
            self.duration_seconds = 100.0

    class ScoreReq:
        def __init__(self, focus: list[str] | None) -> None:
            self.routes = [RouteReq()]
            self.sample_stride = 1
            self.focus_pollutants = focus
            self.use_ontology = False

    return decode_poly, fetch_aqi_mock, fetch_humidity_mock, ScoreReq
