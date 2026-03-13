#!/usr/bin/env python3
import os, asyncio, time, json
from typing import Dict, List, Optional, Tuple

import httpx
import polyline as gpoly
import numpy as np
import pandas as pd

from fastapi import FastAPI, HTTPException, Body
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

# ============================================================
# CONFIG & API KEYS
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


USER_DB_PATH = "Key.json"  # ไฟล์เก็บข้อมูลผู้ใช้ที่ฝั่ง Server
ONTOLOGY_PATH = os.path.join(os.path.dirname(__file__), "ontology_fixed.ttl")

LANG = "en"
HTTP_TIMEOUT = 4
MAX_CONCURRENCY = 10
AQ_CACHE_TTL = 300

CRITERIA = ["pm2.5", "pm10", "co", "no2", "o3", "so2"]
POLLUTANTS_ALLOWED = ["pm2.5", "pm10", "co", "no2", "o3", "so2"]

# ============================================================
# MODELS
# ============================================================

# --- User Management Models ---
class UserRegister(BaseModel):
    firstname: str
    lastname: str
    email: str
    phonenum: str
    password: str

class LoginRequest(BaseModel):
    email: str
    password: str

# --- DSS Models ---
class RouteItem(BaseModel):
    id: str
    encoded_polyline: Optional[str] = Field(None, alias="encodedPolyline")
    distance_meters: float = Field(..., alias="distanceMeters")
    duration_seconds: float = Field(..., alias="durationSeconds")

class ScoreRequest(BaseModel):
    routes: List[RouteItem]
    sample_stride: int = 20
    focus_pollutants: Optional[List[str]] = None
    use_ontology: bool = False

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
    ontology_label: Optional[str] = None
    ontology_info: Optional[dict] = None

class ScoreResponse(BaseModel):
    scores: List[ScoreResult]

# ============================================================
# USER MANAGEMENT HELPERS (File Operations)
# ============================================================

def read_users():
    if not os.path.exists(USER_DB_PATH):
        return []
    with open(USER_DB_PATH, "r", encoding="utf-8") as f:
        try:
            return json.load(f)
        except:
            return []

def save_users(users):
    with open(USER_DB_PATH, "w", encoding="utf-8") as f:
        json.dump(users, f, indent=4, ensure_ascii=False)

# ============================================================
# DSS HELPERS & EXTERNAL API FETCHERS
# ============================================================

def decode_poly(encoded: str):
    if not encoded: return []
    try: return gpoly.decode(encoded)
    except: return []

def sample_points(pts, stride):
    return pts[::max(1, stride)]

AQ_CACHE: Dict[str, Tuple[float, dict]] = {}
def cache_key(lat, lon): return f"{round(lat,4)},{round(lon,4)}"

async def fetch_aqi(client, lat, lon):
    key = cache_key(lat, lon)
    now = time.time()
    if key in AQ_CACHE:
        ts, data = AQ_CACHE[key]
        if now - ts < AQ_CACHE_TTL: return data

    payload = {
        "location": {"latitude": float(lat), "longitude": float(lon)},
        "extraComputations": ["POLLUTANT_CONCENTRATION", "LOCAL_AQI"],
        "languageCode": LANG
    }
    try:
        res = await client.post(f"{GOOGLE_AIR_URL}?key={GOOGLE_API_KEY}", json=payload, timeout=HTTP_TIMEOUT)
        js = res.json()
    except:
        js = {"pollutants": []}
    AQ_CACHE[key] = (now, js)
    return js

def extract_pollutants(api):
    out = {}
    for p in api.get("pollutants", []):
        raw = p.get("code", "").lower()
        code = "pm2.5" if raw in ("pm2.5", "p25", "pm25") else raw
        val = (p.get("concentration") or {}).get("value")
        out[code] = float(val) if val is not None else 9999.0
    for k in CRITERIA: out.setdefault(k, 9999.0)
    return out

async def fetch_humidity(client, lat, lon):
    url = f"https://data.tmd.go.th/nwpapi/v1/forecast/point?lat={lat}&lon={lon}"
    try:
        r = await client.get(url, headers={"Authorization": f"Bearer {TMD_TOKEN}"}, timeout=HTTP_TIMEOUT)
        js = r.json()
        return float(js["WeatherForecasts"][0]["WeatherForecastItems"][0]["relativeHumidity"])
    except: return None

def weather_score(rh: Optional[float]) -> int:
    if rh is None: return 2
    if rh > 75: return 3
    elif rh < 40: return 1
    return 2

# ============================================================
# DSS LOGIC (CRITIC, SCORING, ONTOLOGY)
# ============================================================

def critic_weights(data: pd.DataFrame) -> dict:
    if data.empty or len(data) < 2:
        return {k: 1.0 / len(CRITERIA) for k in CRITERIA}
    norm = data.apply(lambda x: (x.max() - x) / (x.max() - x.min() + 1e-12))
    std = norm.std(ddof=0)
    beta = std * (1 - norm.corr()).sum()
    beta_sum = beta.sum()
    if beta_sum == 0 or pd.isna(beta_sum):
        return {k: 1.0 / len(CRITERIA) for k in CRITERIA}
    return (beta / beta_sum).to_dict()

def route_pollution_score(avg_pollution: dict, critic_w: dict, g_mean: dict, g_std: dict):
    keys = list(critic_w.keys())
    vals = np.array([avg_pollution.get(k, 0) for k in keys])
    means = np.array([g_mean.get(k, 0) for k in keys])
    stds = np.maximum(np.array([g_std.get(k, 1) for k in keys]), 0.1)
    
    z = (vals - means) / stds
    mapped = 1 / (1 + np.exp(-z))
    weights = np.array([critic_w.get(k, 0) for k in keys])
    score = float(np.dot(mapped, weights) / (weights.sum() + 1e-12))
    return score, dict(zip(keys, mapped))

def evaluate_route(route_data, max_vals, critic_w, g_mean, g_std, avg_poll, weather_scores, avg_h):
    # di & dt
    di = 1 - (route_data["distance_meters"] / max_vals["distance"]) if max_vals["distance"] > 0 else 0.5
    dt = 1 - (route_data["duration_seconds"] / max_vals["time"]) if max_vals["time"] > 0 else 0.5
    
    # dp
    if avg_poll:
        cp_score, _ = route_pollution_score(avg_poll, critic_w, g_mean, g_std)
        dp = 1 - cp_score
    else: dp = 0.5

    # dw
    dw = (np.mean(weather_scores) - 1) / 2 if weather_scores else 0.5
    
    # Final Weighted Score
    final = (0.3 * di) + (0.3 * dt) + (0.3 * dp) + (0.1 * dw)
    return {"final_score": final, "di": di, "dt": dt, "dp": dp, "dw": dw, "avg_humidity": avg_h}

# ============================================================
# FASTAPI APP
# ============================================================

app = FastAPI(title="Smart Route & User Management API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health")
def health(): return {"ok": True}

# --- 1. USER: Check Email ---
@app.get("/check-email")
async def check_email(email: str):
    users = read_users()
    exists = any(u['email'].lower() == email.lower() for u in users)
    return {"exists": exists}

# --- 2. USER: Signup ---
@app.post("/signup", status_code=201)
async def signup(user: UserRegister):
    users = read_users()
    if any(u['email'].lower() == user.email.lower() for u in users):
        raise HTTPException(status_code=400, detail="Email already registered")
    users.append(user.dict())
    save_users(users)
    print(f"✅ User Signup: {user.email}")
    return {"message": "User created"}

# --- 3. USER: Login ---
@app.post("/login")
async def login(req: LoginRequest):
    users = read_users()
    for u in users:
        if u['email'].lower() == req.email.lower() and u['password'] == req.password:
            print(f"🔑 User Login: {u['email']}")
            return {"message": "Success", "user": {"firstname": u['firstname'], "email": u['email']}}
    raise HTTPException(status_code=401, detail="Invalid credentials")

# --- 4. DSS: Score Routes ---
@app.post("/scoreRoutes", response_model=ScoreResponse)
async def score_routes(req: ScoreRequest):
    try:
        all_pollut = []
        async with httpx.AsyncClient(timeout=httpx.Timeout(HTTP_TIMEOUT)) as client:
            for r in req.routes:
                pts = sample_points(decode_poly(r.encoded_polyline), req.sample_stride)
                for lat, lon in pts:
                    aqi = await fetch_aqi(client, lat, lon)
                    all_pollut.append(extract_pollutants(aqi))

        df = pd.DataFrame(all_pollut).replace(9999.0, np.nan).dropna(how='all').fillna(0)
        gmean = df.mean().to_dict()
        gstd = df.std(ddof=0).to_dict()
        critic_w = critic_weights(df)

        # Apply user preference boost
        if req.focus_pollutants:
            for f in req.focus_pollutants:
                if f in critic_w: critic_w[f] *= 100
            total_w = sum(critic_w.values())
            critic_w = {k: v/total_w for k, v in critic_w.items()}

        max_dist = max(r.distance_meters for r in req.routes)
        max_time = max(r.duration_seconds for r in req.routes)

        scores = []
        async with httpx.AsyncClient() as client:
            for r in req.routes:
                pts = sample_points(decode_poly(r.encoded_polyline), req.sample_stride)
                p_rows, h_rows = [], []
                for lat, lon in pts:
                    aq = await fetch_aqi(client, lat, lon)
                    p_rows.append(extract_pollutants(aq))
                    h_rows.append(await fetch_humidity(client, lat, lon))
                
                avg_p = pd.DataFrame(p_rows).replace(9999.0, 0).mean().to_dict()
                avg_h = np.mean([h for h in h_rows if h is not None]) if any(h_rows) else 60.0
                w_scores = [weather_score(h) for h in h_rows if h is not None]

                res = evaluate_route(
                    {"distance_meters": r.distance_meters, "duration_seconds": r.duration_seconds},
                    {"distance": max_dist, "time": max_time},
                    critic_w, gmean, gstd, avg_p, w_scores, avg_h
                )
                scores.append(ScoreResult(
                    id=r.id, risk_score=res["final_score"],
                    di=res["di"], dt=res["dt"], dp=res["dp"], dw=res["dw"],
                    avgHumidity=res["avg_humidity"], points_sampled=len(pts), 
                    points_used=len(p_rows), note="ok"
                ))
        return ScoreResponse(scores=scores)
    except Exception as e:
        print(f"Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", "8000"))
    uvicorn.run(app, host="0.0.0.0", port=port)
