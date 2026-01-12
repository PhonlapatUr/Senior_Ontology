# #!/usr/bin/env python3
# import os, asyncio, time
# from typing import Dict, List, Optional, Tuple

# import httpx
# import polyline as gpoly
# import numpy as np
# import pandas as pd

# from fastapi import FastAPI
# from fastapi.middleware.cors import CORSMiddleware
# from pydantic import BaseModel, Field


# # ============================================================
# # CONFIG
# # ============================================================

# GOOGLE_API_KEY = os.getenv(
#     "GOOGLE_API_KEY",
#     "AIzaSyDg3Gv6FLg7KT19XyEuJEMrMYAVP8sjU6Y"
# )

# GOOGLE_AIR_URL = "https://airquality.googleapis.com/v1/currentConditions:lookup"

# TMD_TOKEN = os.getenv(
#     "TMD_TOKEN",
#     "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImp0aSI6ImY2ZWJhZTUyZGM2NWRiZDM5MDAwNDA0ZGU2NzVjZGNmYzY0NzAzZWZhYTllMWQwYjJlOWYyOTMxMTZiMTM2YjEzODU3ODdmOTc5NzVhN2NhIn0.eyJhdWQiOiIyIiwianRpIjoiZjZlYmFlNTJkYzY1ZGJkMzkwMDA0MDRkZTY3NWNkY2ZjNjQ3MDNlZmFhOWUxZDBiMmU5ZjI5MzExNmIxMzZiMTM4NTc4N2Y5Nzk3NWE3Y2EiLCJpYXQiOjE3NjMyODcxNjUsIm5iZiI6MTc2MzI4NzE2NSwiZXhwIjoxNzk0ODIzMTY1LCJzdWIiOiI0MTA1Iiwic2NvcGVzIjpbXX0.JjQkr6iyQol_53-zWoeSlLSiIe2mWFUfCSn_-9qN_rgSkI0khY1g-vbgGDxnW_AgHbKWeT4bh6er1xTIfEzZdbdoHQSn4KgwS4DLJcM1isb14KXzz_lhShfeDHh_HgIz6an7rTL1LUWWOx5mD9AR4eHL23z5aqs10OphgmlShuUL7se-2i8l4HB1FSuOcapArt_lQoTv4ajJFE7gujOPFAz5dyxhX8XD-GXnACJm5Sly0I2-vAshFEG53oU2IRIrIY4wGY8iTRDqobb1oGEvg5vGdrL6Z5U1ObpruF3_9QA64PYM_LDPN5-t7Pb1tGp9ckocGpezcKFI-kUdINlvuP11fYwaZpy_kNfRAbVqS2we6NLoEAQlEO7yTVUy_pJ1HmLU8rwCHVLOTSbiaAbq0A1wz9ASKzA6go43k2CBvyzjl378z4cMsTSxJ2tf7fA5oywRVdX8nKkSg52WlAHPga2ODvAD0lC9cn3bbvk0dbieYnGB-aOniYnjHRWOhqTF7BZhNiAFOCP2tLcDJjxF0_Z6VoAljevebQynSZa71i8th9uwbCGgTVMZeN-On5qiOgGXe8TeiPUSnWob9ngIJQmYp6KfNodQTwErFwGho_Eb7QKgF_1BzTt9kxQyy5sYvRJjNKEw4g-dN57XxqBE4gDW-oJPliAAY2WqrCACmq"
# )

# LANG = "en"
# HTTP_TIMEOUT = 4
# MAX_CONCURRENCY = 10
# AQ_CACHE_TTL = 300

# POLLUTANT_KEYS = ["pm25", "pm10", "co", "no2", "o3", "so2"]


# # ============================================================
# # MODELS
# # ============================================================

# class RouteItem(BaseModel):
#     id: str
#     encoded_polyline: Optional[str] = Field(None, alias="encodedPolyline")
#     distance_meters: float = Field(..., alias="distanceMeters")
#     duration_seconds: float = Field(..., alias="durationSeconds")


# class ScoreRequest(BaseModel):
#     routes: List[RouteItem]
#     sample_stride: int = 20      # you picked 20 segments per route


# class ScoreResult(BaseModel):
#     id: str
#     risk_score: float
#     di: float
#     dt: float
#     dp: float
#     dw: float
#     avgHumidity: float
#     points_sampled: int
#     points_used: int
#     note: str


# class ScoreResponse(BaseModel):
#     scores: List[ScoreResult]


# # ============================================================
# # HELPERS
# # ============================================================

# def decode_poly(encoded: str):
#     if not encoded:
#         return []
#     try:
#         return gpoly.decode(encoded)
#     except:
#         return []


# def sample_points(pts, stride):
#     return pts[::max(1, stride)]


# AQ_CACHE: Dict[str, Tuple[float, dict]] = {}


# def cache_key(lat, lon):
#     return f"{round(lat,4)},{round(lon,4)}"


# # ============================================================
# # GOOGLE AQI FETCH
# # ============================================================

# async def fetch_aqi(client, lat, lon):
#     key = cache_key(lat, lon)
#     now = time.time()

#     # CACHE
#     if key in AQ_CACHE:
#         ts, data = AQ_CACHE[key]
#         if now - ts < AQ_CACHE_TTL:
#             return data

#     payload = {
#         "location": {"latitude": float(lat), "longitude": float(lon)},
#         "extraComputations": [
#             "POLLUTANT_CONCENTRATION",
#             "POLLUTANT_ADDITIONAL_INFO",
#             "LOCAL_AQI"
#         ],
#         "languageCode": LANG
#     }

#     try:
#         res = await client.post(
#             f"{GOOGLE_AIR_URL}?key={GOOGLE_API_KEY}",
#             json=payload,
#             timeout=HTTP_TIMEOUT
#         )
#         js = res.json()
#     except:
#         js = {"pollutants": []}

#     AQ_CACHE[key] = (now, js)
#     return js


# # ============================================================
# # POLLUTANT EXTRACTION
# # ============================================================

# def extract_pollutants(api):
#     out = {}

#     for p in api.get("pollutants", []):
#         raw = p.get("code", "").lower()

#         if raw in ("pm2.5", "p25", "pm25"):
#             code = "pm25"
#         else:
#             code = raw

#         val = (p.get("concentration") or {}).get("value")
#         out[code] = float(val) if val is not None else 9999.0

#     # If Google returned nothing
#     if len(out) == 0:
#         out = {k: 9999.0 for k in POLLUTANT_KEYS}

#     # Ensure all keys exist
#     for k in POLLUTANT_KEYS:
#         out.setdefault(k, 9999.0)

#     return out


# # ============================================================
# # WEATHER (TMD)
# # ============================================================

# async def fetch_humidity(client, lat, lon):
#     url = f"https://data.tmd.go.th/nwpapi/v1/forecast/point?lat={lat}&lon={lon}"
#     try:
#         r = await client.get(
#             url,
#             headers={"Authorization": f"Bearer {TMD_TOKEN}"},
#             timeout=HTTP_TIMEOUT
#         )
#         js = r.json()
#         return float(js["WeatherForecasts"][0]["WeatherForecastItems"][0]["relativeHumidity"])
#     except:
#         return None


# def weather_score(h):
#     if h is None:
#         return 2
#     if h > 75:
#         return 3
#     if h < 40:
#         return 1
#     return 2


# # ============================================================
# # CRITIC SYSTEM
# # ============================================================

# def critic_weights(df):
#     norm = df.apply(lambda x: (x.max() - x) / (x.max() - x.min() + 1e-12))
#     std = norm.std(ddof=0)
#     corr = norm.corr()
#     conflict = (1 - corr).sum()
#     beta = std * conflict
#     w = beta / beta.sum()
#     return w.to_dict()


# def critic_pollution_score(avg, critic_w, means, stds):
#     keys = list(critic_w.keys())

#     vals = np.array([avg[k] for k in keys])
#     w = np.array([critic_w[k] for k in keys])
#     mu = np.array([means[k] for k in keys])
#     sd = np.array([stds[k] for k in keys]) + 1e-12

#     z = (vals - mu) / sd
#     mapped = 1 / (1 + np.exp(-z))

#     return float(np.dot(mapped, w) / w.sum())


# # ============================================================
# # SINGLE ROUTE SCORING
# # ============================================================

# async def score_single_route(route, stride, max_dist, max_time,
#                              critic_w, gmean, gstd):

#     pts = decode_poly(route.encoded_polyline)
#     pts = sample_points(pts, stride)

#     if not pts:
#         return None

#     pollut_rows = []
#     humidity_rows = []

#     sem = asyncio.Semaphore(MAX_CONCURRENCY)

#     async with httpx.AsyncClient() as client:

#         async def worker(lat, lon):
#             async with sem:
#                 aqi = await fetch_aqi(client, lat, lon)
#                 pollut_rows.append(extract_pollutants(aqi))

#                 h = await fetch_humidity(client, lat, lon)
#                 humidity_rows.append(h if h is not None else 60)

#         await asyncio.gather(*(worker(lat, lon) for lat, lon in pts))

#     df = pd.DataFrame(pollut_rows)
#     avg_poll = df.mean().to_dict()

#     critic = critic_pollution_score(avg_poll, critic_w, gmean, gstd)
#     dp = 1 - critic

#     avg_h = float(np.mean(humidity_rows))
#     weather_lvls = [weather_score(h) for h in humidity_rows]
#     dw = (np.mean(weather_lvls) - 1) / 2

#    # Convert meters → km and seconds → minutes
# dist_km = route.distance_meters / 1000.0
# time_min = route.duration_seconds / 60.0

# # Apply max values converted to km/min
# max_dist_km = max_dist / 1000.0
# max_time_min = max_time / 60.0

# # Normalized indicators (0..1)
# di = 1 - (dist_km / max_dist_km)
# dt = 1 - (time_min / max_time_min)

# # safety guard: no negative values
# di = max(0.0, min(di, 1.0))
# dt = max(0.0, min(dt, 1.0))


#     final = 0.30 * di + 0.30 * dt + 0.30 * dp + 0.10 * dw

#     return ScoreResult(
#         id=route.id,
#         risk_score=final,
#         di=di,
#         dt=dt,
#         dp=dp,
#         dw=dw,
#         avgHumidity=avg_h,
#         points_sampled=len(pts),
#         points_used=len(pollut_rows),
#         note="ok"
#     )


# # ============================================================
# # FASTAPI APP
# # ============================================================

# app = FastAPI(title="Smart Route DSS v2")

# app.add_middleware(
#     CORSMiddleware,
#     allow_origins=["*"],
#     allow_methods=["*"],
#     allow_headers=["*"],
# )


# @app.post("/scoreRoutes", response_model=ScoreResponse)
# async def score_routes(req: ScoreRequest):

#     all_pollut = []

#     async with httpx.AsyncClient() as client:
#         for r in req.routes:
#             pts = decode_poly(r.encoded_polyline)
#             pts = sample_points(pts, req.sample_stride)

#             for lat, lon in pts:
#                 aqi = await fetch_aqi(client, lat, lon)
#                 all_pollut.append(extract_pollutants(aqi))

#     df = pd.DataFrame(all_pollut).fillna(9999.0)

#     critic_w = critic_weights(df)
#     gmean = df.mean().to_dict()
#     gstd = df.std(ddof=0).to_dict()

#     max_dist = max(r.distance_meters for r in req.routes)
#     max_time = max(r.duration_seconds for r in req.routes)

#     tasks = [
#         score_single_route(r, req.sample_stride, max_dist, max_time,
#                            critic_w, gmean, gstd)
#         for r in req.routes
#     ]

#     results = await asyncio.gather(*tasks)
#     return ScoreResponse(scores=[r for r in results if r])


# @app.get("/health")
# def health():
#     return {"ok": True}



#!/usr/bin/env python3
import os, asyncio, time
from typing import Dict, List, Optional, Tuple

import httpx
import polyline as gpoly
import numpy as np
import pandas as pd

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

# ============================================================
# CONFIG
# ============================================================

GOOGLE_API_KEY = os.getenv(
    "GOOGLE_API_KEY",
    "AIzaSyDg3Gv6FLg7KT19XyEuJEMrMYAVP8sjU6Y"
)

GOOGLE_AIR_URL = "https://airquality.googleapis.com/v1/currentConditions:lookup"

TMD_TOKEN = os.getenv(
    "TMD_TOKEN",
    "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImp0aSI6ImY2ZWJhZTUyZGM2NWRiZDM5MDAwNDA0ZGU2NzVjZGNmYzY0NzAzZWZhYTllMWQwYjJlOWYyOTMxMTZiMTM2YjEzODU3ODdmOTc5NzVhN2NhIn0.eyJhdWQiOiIyIiwianRpIjoiZjZlYmFlNTJkYzY1ZGJkMzkwMDA0MDRkZTY3NWNkY2ZjNjQ3MDNlZmFhOWUxZDBiMmU5ZjI5MzExNmIxMzZiMTM4NTc4N2Y5Nzk3NWE3Y2EiLCJpYXQiOjE3NjMyODcxNjUsIm5iZiI6MTc2MzI4NzE2NSwiZXhwIjoxNzk0ODIzMTY1LCJzdWIiOiI0MTA1Iiwic2NvcGVzIjpbXX0.JjQkr6iyQol_53-zWoeSlLSiIe2mWFUfCSn_-9qN_rgSkI0khY1g-vbgGDxnW_AgHbKWeT4bh6er1xTIfEzZdbdoHQSn4KgwS4DLJcM1isb14KXzz_lhShfeDHh_HgIz6an7rTL1LUWWOx5mD9AR4eHL23z5aqs10OphgmlShuUL7se-2i8l4HB1FSuOcapArt_lQoTv4ajJFE7gujOPFAz5dyxhX8XD-GXnACJm5Sly0I2-vAshFEG53oU2IRIrIY4wGY8iTRDqobb1oGEvg5vGdrL6Z5U1ObpruF3_9QA64PYM_LDPN5-t7Pb1tGp9ckocGpezcKFI-kUdINlvuP11fYwaZpy_kNfRAbVqS2we6NLoEAQlEO7yTVUy_pJ1HmLU8rwCHVLOTSbiaAbq0A1wz9ASKzA6go43k2CBvyzjl378z4cMsTSxJ2tf7fA5oywRVdX8nKkSg52WlAHPga2ODvAD0lC9cn3bbvk0dbieYnGB-aOniYnjHRWOhqTF7BZhNiAFOCP2tLcDJjxF0_Z6VoAljevebQynSZa71i8th9uwbCGgTVMZeN-On5qiOgGXe8TeiPUSnWob9ngIJQmYp6KfNodQTwErFwGho_Eb7QKgF_1BzTt9kxQyy5sYvRJjNKEw4g-dN57XxqBE4gDW-oJPliAAY2WqrCACmq"
)

LANG = "en"
HTTP_TIMEOUT = 4
MAX_CONCURRENCY = 10
AQ_CACHE_TTL = 300

POLLUTANT_KEYS = ["pm25", "pm10", "co", "no2", "o3", "so2"]

# ============================================================
# MODELS
# ============================================================

class RouteItem(BaseModel):
    id: str
    encoded_polyline: Optional[str] = Field(None, alias="encodedPolyline")
    distance_meters: float = Field(..., alias="distanceMeters")
    duration_seconds: float = Field(..., alias="durationSeconds")


class ScoreRequest(BaseModel):
    routes: List[RouteItem]
    sample_stride: int = 20


class ScoreResult(BaseModel):
    id: str
    risk_score: float
    di: float
    dt: float
    dp: float
    dw: float
    avgHumidity: float
    points_sampled: int
    points_used: int
    note: str


class ScoreResponse(BaseModel):
    scores: List[ScoreResult]


# ============================================================
# HELPERS
# ============================================================

def decode_poly(encoded: str):
    if not encoded:
        return []
    try:
        return gpoly.decode(encoded)
    except:
        return []


def sample_points(pts, stride):
    return pts[::max(1, stride)]


AQ_CACHE: Dict[str, Tuple[float, dict]] = {}


def cache_key(lat, lon):
    return f"{round(lat,4)},{round(lon,4)}"


# ============================================================
# GOOGLE AQI FETCH
# ============================================================

async def fetch_aqi(client, lat, lon):
    key = cache_key(lat, lon)
    now = time.time()

    if key in AQ_CACHE:
        ts, data = AQ_CACHE[key]
        if now - ts < AQ_CACHE_TTL:
            return data

    payload = {
        "location": {"latitude": float(lat), "longitude": float(lon)},
        "extraComputations": [
            "POLLUTANT_CONCENTRATION",
            "POLLUTANT_ADDITIONAL_INFO",
            "LOCAL_AQI"
        ],
        "languageCode": LANG
    }

    try:
        res = await client.post(
            f"{GOOGLE_AIR_URL}?key={GOOGLE_API_KEY}",
            json=payload,
            timeout=HTTP_TIMEOUT
        )
        js = res.json()
    except:
        js = {"pollutants": []}

    AQ_CACHE[key] = (now, js)
    return js


# ============================================================
# POLLUTANT EXTRACTION
# ============================================================

def extract_pollutants(api):
    out = {}

    for p in api.get("pollutants", []):
        raw = p.get("code", "").lower()

        if raw in ("pm2.5", "p25", "pm25"):
            code = "pm25"
        else:
            code = raw

        val = (p.get("concentration") or {}).get("value")
        out[code] = float(val) if val is not None else 9999.0

    if len(out) == 0:
        out = {k: 9999.0 for k in POLLUTANT_KEYS}

    for k in POLLUTANT_KEYS:
        out.setdefault(k, 9999.0)

    return out


# ============================================================
# WEATHER (TMD)
# ============================================================

async def fetch_humidity(client, lat, lon):
    url = f"https://data.tmd.go.th/nwpapi/v1/forecast/point?lat={lat}&lon={lon}"
    try:
        r = await client.get(
            url,
            headers={"Authorization": f"Bearer {TMD_TOKEN}"},
            timeout=HTTP_TIMEOUT
        )
        js = r.json()
        return float(js["WeatherForecasts"][0]["WeatherForecastItems"][0]["relativeHumidity"])
    except:
        return None


def weather_score(h):
    if h is None:
        return 2
    if h > 75:
        return 3
    if h < 40:
        return 1
    return 2


# ============================================================
# CRITIC SYSTEM
# ============================================================

def critic_weights(df):
    norm = df.apply(lambda x: (x.max() - x) / (x.max() - x.min() + 1e-12))
    std = norm.std(ddof=0)
    corr = norm.corr()
    conflict = (1 - corr).sum()
    beta = std * conflict
    w = beta / beta.sum()
    return w.to_dict()


def critic_pollution_score(avg, critic_w, means, stds):
    keys = list(critic_w.keys())

    vals = np.array([avg[k] for k in keys])
    w = np.array([critic_w[k] for k in keys])
    mu = np.array([means[k] for k in keys])
    sd = np.array([stds[k] for k in keys]) + 1e-12

    z = (vals - mu) / sd
    mapped = 1 / (1 + np.exp(-z))

    return float(np.dot(mapped, w) / w.sum())


# ============================================================
# SINGLE ROUTE SCORING
# ============================================================

async def score_single_route(route, stride, max_dist, max_time,
                             critic_w, gmean, gstd):

    pts = decode_poly(route.encoded_polyline)
    pts = sample_points(pts, stride)

    if not pts:
        return None

    pollut_rows = []
    humidity_rows = []

    sem = asyncio.Semaphore(MAX_CONCURRENCY)

    async with httpx.AsyncClient() as client:

        async def worker(lat, lon):
            async with sem:
                aqi = await fetch_aqi(client, lat, lon)
                pollut_rows.append(extract_pollutants(aqi))

                h = await fetch_humidity(client, lat, lon)
                humidity_rows.append(h if h is not None else 60)

        await asyncio.gather(*(worker(lat, lon) for lat, lon in pts))

    df = pd.DataFrame(pollut_rows)
    avg_poll = df.mean().to_dict()

    critic = critic_pollution_score(avg_poll, critic_w, gmean, gstd)
    dp = 1 - critic

    avg_h = float(np.mean(humidity_rows))
    weather_lvls = [weather_score(h) for h in humidity_rows]
    dw = (np.mean(weather_lvls) - 1) / 2

    
    dist_km = round(route.distance_meters / 1000.0, 2)
    time_min = round(route.duration_seconds / 60.0, 2)

    max_dist_km = round(max_dist / 1000.0, 2)
    max_time_min = round(max_time / 60.0, 2)


    if max_dist == 0:
     di = 1.0
    else:
        di = 1 - (route.distance_meters / max_dist)

    if max_time == 0:
        dt = 1.0
    else:
        dt = 1 - (route.duration_seconds / max_time)

    di = max(0.0, min(di, 1.0))
    dt = max(0.0, min(dt, 1.0))


    final = 0.30 * di + 0.30 * dt + 0.30 * dp + 0.10 * dw
    final = round(final, 2)


    return ScoreResult(
        id=route.id,
        risk_score=round(final, 2),
        di=round(di, 3),
        dt=round(dt, 2),
        dp=round(dp, 2),
        dw=round(dw, 2),
        avgHumidity=round(avg_h, 2),
        points_sampled=len(pts),
        points_used=len(pollut_rows),
        note="ok"
    )



# ============================================================
# FASTAPI APP
# ============================================================

app = FastAPI(title="Smart Route DSS v2")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.post("/scoreRoutes", response_model=ScoreResponse)
async def score_routes(req: ScoreRequest):

    all_pollut = []

    async with httpx.AsyncClient() as client:
        for r in req.routes:
            pts = decode_poly(r.encoded_polyline)
            pts = sample_points(pts, req.sample_stride)

            for lat, lon in pts:
                aqi = await fetch_aqi(client, lat, lon)
                all_pollut.append(extract_pollutants(aqi))

    df = pd.DataFrame(all_pollut).fillna(9999.0)

    critic_w = critic_weights(df)
    gmean = df.mean().to_dict()
    gstd = df.std(ddof=0).to_dict()

    max_dist = max(r.distance_meters for r in req.routes)
    max_time = max(r.duration_seconds for r in req.routes)

    tasks = [
        score_single_route(r, req.sample_stride, max_dist, max_time,
                           critic_w, gmean, gstd)
        for r in req.routes
    ]

    results = await asyncio.gather(*tasks)
    return ScoreResponse(scores=[r for r in results if r])


@app.get("/health")
def health():
    return {"ok": True}
