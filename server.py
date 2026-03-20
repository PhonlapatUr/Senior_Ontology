#!/usr/bin/env python3
import os, asyncio, time, json
from datetime import datetime, timedelta, timezone
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

TMD_TOKEN_ENV = os.getenv("TMD_TOKEN")
# NOTE: There is a placeholder token in code to keep the app from crashing.
# Real weather requires setting `TMD_TOKEN` environment variable to a valid OAuth access token.
TMD_TOKEN = TMD_TOKEN_ENV or (
    "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImp0aSI6ImM3ZDUxYzU0Njc3NWE5YTkxNTU0ZWE3NWJmYTljMWZjNWFhMGM1YWQ2ZDEzMzI1NWIxZDdmODA5Yjg0YjE2Mjc1YjdmZmFkNWI2NzkyZDIwIn0.eyJhdWQiOiIyIiwianRpIjoiYzdkNTFjNTQ2Nzc1YTlhOTE1NTRlYTc1YmZhOWMxZmM1YWEwYzVhZDZkMTMzMjU1YjFkN2Y4MDliODRiMTYyNzViN2ZmYWQ1YjY3OTJkMjAiLCJpYXQiOjE3NzQwMzQ4OTQsIm5iZiI6MTc3NDAzNDg5NCwiZXhwIjoxODA1NTcwODk0LCJzdWIiOiI1MDY1Iiwic2NvcGVzIjpbXX0.QZSVLQ1BkE70DqVq7oGKY1_IhqV08pJ4hm7HKpel7FIYf2vpeTP9iWAzbc1uq3-X1cd3fXkcOzL-lcyHPJg5oyvllrrIlQ-GbA-vC-lPUFGA0lZPXU0fTh6c5Yuplrulr1tSXugCCBhpH-9og_OMcT6EGTjBTn8m6edKZxFgH3cmz-QlbO6iVJn6n-0Id5QXgbImCG_G5doBUAF9vRujj8f8H6WWw1GLe3OxIS0jOPt4-bjz80SZJ8TOFL9O1oI3o-jESjvCx1qY3swTYu9iuTjxoaz5YKPvzWP6Ag1gBaznRc6hbTs3_jFsy4RG3M1dIGsFTIXqSburAW7VtdvPlzTRHWOi8J_oQN_8cc04-6oQVVnHXdA-Kc2ZQQjOfC6Qhn6XnTMC_F50MJeW1weVDvVdNwvYJvNaj4941JbYsilzGxVqetd-mM11kW56uZsZUszGN-YSeKVpWseeMGv7zGFDGo6lQYpUip37jpDZVIeN4TZUxLjKAsieT87k_LhJ-CeU2sjpTjXjZGOTWfHNI9DPBFl-MWDyTuH-NO8mOkBxljE8vruWL4PV2obnfJdwLbf8eu7v9ZEnJ-1kciE1y4XKDSLzHwvUW6lmACiEcvYXCtxPVoxtLvncnWefBV0WEktq_XVKod3zaNEW6Oq-jbc9b1KLF5prKHhVDvJAzLE"
)

if TMD_TOKEN_ENV is None:
    print("[TMD] WARNING: `TMD_TOKEN` env var not set. Using placeholder token; humidity requests will likely fail.")

# #region agent log
_DEBUG_LOG_PATH = os.path.join(os.path.dirname(__file__), ".cursor", "debug-9bfe97.log")

def _agent_debug_log(location: str, message: str, run_id: str, hypothesis_id: str, data: dict):
    try:
        payload = {
            "sessionId": "9bfe97",
            "runId": run_id,
            "hypothesisId": hypothesis_id,
            "location": location,
            "message": message,
            "data": data,
            "timestamp": int(time.time() * 1000),
        }
        with open(_DEBUG_LOG_PATH, "a", encoding="utf-8") as f:
            f.write(json.dumps(payload, ensure_ascii=True) + "\n")
    except Exception:
        pass
# #endregion


USER_DB_PATH = "Key.json"  
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

class ChangePasswordRequest(BaseModel):
    email: str
    old_password: str
    new_password: str

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
    weatherValid: bool
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
    # TMD Weather Forecast API (NWPAPI) "hourly/at"
    # Docs example:
    # https://data.tmd.go.th/nwpapi/v1/forecast/hourly/at?lat=13.10&lon=100.10&fields=tc,rh&date=2017-08-17&hour=8&duration=2
    now_th = datetime.now(timezone(timedelta(hours=7)))
    date_str = now_th.strftime("%Y-%m-%d")
    hour = now_th.hour

    # #region agent log
    token_raw = os.getenv("TMD_TOKEN")
    token_trimmed = (token_raw or "").strip()
    _agent_debug_log(
        "server.py:fetch_humidity:entry",
        "humidity fetch entry",
        run_id="initial",
        hypothesis_id="H1",
        data={
            "lat": round(float(lat), 5),
            "lon": round(float(lon), 5),
            "hasEnvToken": token_raw is not None,
            "tokenTrimmedLen": len(token_trimmed),
            "usingPlaceholder": token_trimmed == "" or token_trimmed == TMD_TOKEN,
            "hourBangkok": hour,
        },
    )
    # #endregion
    try:
        # Keep one documented TMD endpoint only.
        tmd_url = (
            "https://data.tmd.go.th/nwpapi/v1/forecast/hourly/at"
            f"?lat={lat}&lon={lon}&fields=tc,rh&date={date_str}&hour={hour}&duration=2"
        )
        tmd_resp = await client.get(
            tmd_url,
            headers={
                "accept": "application/json",
                "authorization": f"Bearer {TMD_TOKEN}",
            },
            timeout=HTTP_TIMEOUT,
        )
        # #region agent log
        _agent_debug_log(
            "server.py:fetch_humidity:tmd_response",
            "tmd response received",
            run_id="initial",
            hypothesis_id="H2",
            data={
                "status": tmd_resp.status_code,
                "urlHasHourlyAt": "forecast/hourly/at" in tmd_url,
                "bodySnippet": (tmd_resp.text or "")[:120].replace("\n", " "),
            },
        )
        # #endregion

        if tmd_resp.status_code == 200:
            try:
                tmd_js = tmd_resp.json()
                rh_val = tmd_js["WeatherForecasts"][0]["forecasts"][0]["data"]["rh"]
                print(f"[Humidity] source=tmd lat={lat} lon={lon} rh={rh_val}")
                return float(rh_val)
            except Exception as e:
                print(f"[Humidity] source=tmd status=200 but invalid payload lat={lat} lon={lon}; err={e}")
        else:
            body_snip = (tmd_resp.text or "")[:500].replace("\n", " ")
            print(
                f"[Humidity] source=tmd status={tmd_resp.status_code} lat={lat} lon={lon}; body_snip='{body_snip}'"
            )

        # Fallback source #1: Open-Meteo (keeps Dw usable when TMD endpoint/account is unavailable).
        # API docs: https://open-meteo.com/en/docs
        try:
            fallback_url = (
                "https://api.open-meteo.com/v1/forecast"
                f"?latitude={lat}&longitude={lon}"
                "&hourly=relative_humidity_2m"
                "&forecast_days=1"
                "&timezone=Asia%2FBangkok"
            )
            rf = await client.get(fallback_url, timeout=HTTP_TIMEOUT)
            # #region agent log
            _agent_debug_log(
                "server.py:fetch_humidity:fallback_response",
                "fallback response received",
                run_id="initial",
                hypothesis_id="H3",
                data={
                    "status": rf.status_code,
                    "bodySnippet": (rf.text or "")[:120].replace("\n", " "),
                },
            )
            # #endregion
            if rf.status_code != 200:
                body_snip = (rf.text or "")[:300].replace("\n", " ")
                print(f"[Humidity] fallback status={rf.status_code} lat={lat} lon={lon}; body_snip='{body_snip}'")
                raise RuntimeError(f"open-meteo status={rf.status_code}")

            jsf = rf.json()
            rh_list = ((jsf.get("hourly") or {}).get("relative_humidity_2m") or [])
            if not rh_list:
                print(f"[Humidity] fallback missing hourly humidity for lat={lat} lon={lon}")
                raise RuntimeError("open-meteo missing hourly humidity")

            # Use first available value for current forecast window.
            rh_val = next((v for v in rh_list if v is not None), None)
            if rh_val is None:
                print(f"[Humidity] fallback humidity list has no non-null values for lat={lat} lon={lon}")
                raise RuntimeError("open-meteo humidity list has no non-null values")

            print(f"[Humidity] fallback source=open-meteo lat={lat} lon={lon} rh={rh_val}")
            return float(rh_val)
        except Exception as fe:
            print(f"[Humidity] fallback request failed for lat={lat} lon={lon}: {fe}")
        # Fallback source #2: MET Norway Locationforecast (no API key, requires User-Agent).
        # Docs: https://api.met.no/weatherapi/locationforecast/2.0/documentation
        try:
            met_url = (
                "https://api.met.no/weatherapi/locationforecast/2.0/compact"
                f"?lat={lat}&lon={lon}"
            )
            rm = await client.get(
                met_url,
                headers={
                    "accept": "application/json",
                    "user-agent": "SeniorOntology/1.0 (contact: admin@example.com)",
                },
                timeout=HTTP_TIMEOUT,
            )
            # #region agent log
            _agent_debug_log(
                "server.py:fetch_humidity:metno_response",
                "met.no response received",
                run_id="initial",
                hypothesis_id="H4",
                data={
                    "status": rm.status_code,
                    "bodySnippet": (rm.text or "")[:120].replace("\n", " "),
                },
            )
            # #endregion
            if rm.status_code != 200:
                body_snip = (rm.text or "")[:300].replace("\n", " ")
                print(f"[Humidity] fallback2 status={rm.status_code} lat={lat} lon={lon}; body_snip='{body_snip}'")
                return None

            jm = rm.json()
            ts = ((jm.get("properties") or {}).get("timeseries") or [])
            if not ts:
                print(f"[Humidity] fallback2 missing timeseries for lat={lat} lon={lon}")
                return None

            details = (((ts[0] or {}).get("data") or {}).get("instant") or {}).get("details") or {}
            rh_val = details.get("relative_humidity")
            if rh_val is None:
                print(f"[Humidity] fallback2 missing relative_humidity for lat={lat} lon={lon}")
                return None

            print(f"[Humidity] fallback2 source=met.no lat={lat} lon={lon} rh={rh_val}")
            return float(rh_val)
        except Exception as fe2:
            print(f"[Humidity] fallback2 request failed for lat={lat} lon={lon}: {fe2}")
            return None
    except Exception as e:
        # Avoid leaking the token; just report coordinates and error.
        print(f"[Humidity] request failed for lat={lat} lon={lon}: {e}")
        return None

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
    # Matches notebook math:
    # z = (vals - mean) / std ; mapped = sigmoid(z) ; score = dot(mapped, weights)/sum(weights)
    keys = list(critic_w.keys())
    vals = np.array([avg_pollution[k] for k in keys], dtype=float)
    weights = np.array([critic_w[k] for k in keys], dtype=float)

    means = np.array([g_mean[k] for k in keys], dtype=float)
    stds = np.array([g_std[k] for k in keys], dtype=float) + 1e-12

    z = (vals - means) / stds
    mapped = 1 / (1 + np.exp(-z))
    score = float(np.dot(mapped, weights) / (weights.sum() + 1e-12))
    return score, dict(zip(keys, mapped))

def evaluate_route(route_data, max_vals, critic_w, g_mean, g_std, avg_poll, weather_scores, avg_h):
    """
    Notebook-matched scoring with missing-data branches:
    - if pollution and weather missing: 0.50*di + 0.50*dt
    - if weather missing only: 0.30*di + 0.30*dt + 0.40*dp
    - if pollution missing only: 0.45*di + 0.45*dt + 0.10*dw
    - otherwise: 0.30*di + 0.30*dt + 0.30*dp + 0.10*dw
    """
    # di & dt
    di = 1 - (route_data["distance_meters"] / max_vals["distance"]) if max_vals["distance"] > 0 else 0.5
    dt = 1 - (route_data["duration_seconds"] / max_vals["time"]) if max_vals["time"] > 0 else 0.5

    has_pollution = avg_poll is not None
    has_weather = len(weather_scores) > 0

    # dp (pollution contribution)
    if has_pollution:
        critic_score, norm_vals = route_pollution_score(avg_poll, critic_w, g_mean, g_std)
        dp = 1 - critic_score
    else:
        critic_score = 0.5
        norm_vals = {}
        dp = 0.5

    # dw (weather contribution)
    if has_weather:
        avg_weather = float(np.mean(weather_scores))
        dw = (avg_weather - 1) / 2
    else:
        avg_weather = None
        dw = 0.5

    # Final Weighted Score (missing-data aware)
    if not has_pollution and not has_weather:
        final = (0.50 * di) + (0.50 * dt)
    elif has_weather and not has_pollution:
        final = (0.45 * di) + (0.45 * dt) + (0.10 * dw)
    elif has_pollution and not has_weather:
        final = (0.30 * di) + (0.30 * dt) + (0.40 * dp)
    else:
        final = (0.30 * di) + (0.30 * dt) + (0.30 * dp) + (0.10 * dw)

    return {
        "final_score": final,
        "di": di,
        "dt": dt,
        "dp": dp,
        "dw": dw,
        "avg_humidity": avg_h,
        "weather_valid": has_weather,
        "critic_score": critic_score,
        "avg_pollution_raw": avg_poll,
        "avg_pollutant_norms": norm_vals,
    }


# ============================================================
# ONTOLOGY ADJUSTMENT (Notebook port)
# ============================================================

_ONTOLOGY_MAPS_CACHE: Optional[Tuple[dict, dict]] = None

def _get_ontology_maps():
    global _ONTOLOGY_MAPS_CACHE
    if _ONTOLOGY_MAPS_CACHE is not None:
        return _ONTOLOGY_MAPS_CACHE

    if not ONTOLOGY_PATH or not os.path.exists(ONTOLOGY_PATH):
        _ONTOLOGY_MAPS_CACHE = ({}, {})
        return _ONTOLOGY_MAPS_CACHE

    try:
        from rdflib import Graph, Namespace, RDF, RDFS, OWL
    except Exception:
        _ONTOLOGY_MAPS_CACHE = ({}, {})
        return _ONTOLOGY_MAPS_CACHE

    g = Graph()
    g.parse(ONTOLOGY_PATH, format="turtle")

    AP = Namespace("http://www.example.org/airpollution#")

    pollutant_sources = {}
    source_types = {}

    def local_name(term):
        s = str(term)
        if "#" in s:
            return s.split("#")[-1]
        return s.rsplit("/", 1)[-1]

    # pollutant -> sources via AP.hasSource (and via OWL restrictions)
    for s, _, o in g.triples((None, AP.hasSource, None)):
        pol_name = local_name(s)
        src_name = local_name(o)
        pollutant_sources.setdefault(pol_name, set()).add(src_name)

    for pol, _, sup in g.triples((None, RDFS.subClassOf, None)):
        if (sup, RDF.type, OWL.Restriction) in g and (sup, OWL.onProperty, AP.hasSource) in g:
            for _, _, src in g.triples((sup, OWL.someValuesFrom, None)):
                pol_name = local_name(pol)
                src_name = local_name(src)
                pollutant_sources.setdefault(pol_name, set()).add(src_name)

    # src -> types for HumanSources/NaturalSources classes
    human_cls = AP.HumanSources
    natural_cls = AP.NaturalSources

    for s, _, o in g.triples((None, RDF.type, None)):
        if o == human_cls or o == natural_cls:
            ent_name = local_name(s)
            type_name = local_name(o)
            source_types.setdefault(ent_name, set()).add(type_name)

    for s, _, o in g.triples((None, RDFS.subClassOf, None)):
        if o == human_cls or o == natural_cls:
            ent_name = local_name(s)
            type_name = local_name(o)
            source_types.setdefault(ent_name, set()).add(type_name)

    # Normalize sets to plain dicts for JSON-serializable usage
    pollutant_sources_final = {k: set(v) for k, v in pollutant_sources.items()}
    source_types_final = {k: set(v) for k, v in source_types.items()}

    _ONTOLOGY_MAPS_CACHE = (pollutant_sources_final, source_types_final)
    return _ONTOLOGY_MAPS_CACHE


def ontology_explain_route(avg_pollution: dict, pollutant_sources: dict, source_types: dict):
    if not avg_pollution:
        return "Unknown", {
            "human_score": 0.0,
            "natural_score": 0.0,
            "total_score": 0.0,
            "pollutants": {},
        }

    key_to_ttl = {
        "pm2.5": "PM2.5",
        "pm10": "PM10",
        "co": "CO",
        "no2": "NO2",
        "o3": "O3",
        "so2": "SO2",
    }

    detail = {}
    human_score = 0.0
    natural_score = 0.0
    total_score = 0.0

    for k, v in avg_pollution.items():
        if k not in key_to_ttl:
            continue

        ttl_pol = key_to_ttl[k]
        sources = sorted(list(pollutant_sources.get(ttl_pol, set())))

        src_type_list = []
        has_human = False
        has_natural = False

        for src in sources:
            types = sorted(list(source_types.get(src, set())))
            src_type_list.append({"source": src, "types": types})
            if "HumanSources" in types:
                has_human = True
            if "NaturalSources" in types:
                has_natural = True

        w = float(v)
        total_score += w
        if has_human:
            human_score += w
        if has_natural:
            natural_score += w

        detail[k] = {
            "ttl_pollutant": ttl_pol,
            "value": float(v),
            "sources": src_type_list,
            "flags": {"human": has_human, "natural": has_natural},
        }

    if total_score <= 0:
        label = "Unknown"
    else:
        human_ratio = human_score / total_score
        natural_ratio = natural_score / total_score

        if human_ratio >= 0.60 and natural_ratio < 0.40:
            label = "HumanSources"
        elif natural_ratio >= 0.60 and human_ratio < 0.40:
            label = "NaturalSources"
        else:
            label = "Mixed"

    explanation = {
        "human_score": human_score,
        "natural_score": natural_score,
        "total_score": total_score,
        "pollutants": detail,
    }
    return label, explanation


def apply_ontology_adjustment(results: list, pollutant_sources: dict, source_types: dict, penalty_max: float = 0.30):
    adjusted = []
    for r in results:
        avg_pol = r.get("avg_pollution_raw")
        label, exp = ontology_explain_route(avg_pol, pollutant_sources, source_types)

        base_score = r["final_score"]
        total = exp["total_score"]
        if total > 0:
            human_ratio = exp["human_score"] / total
            natural_ratio = exp["natural_score"] / total
            hazard_index = 0.7 * human_ratio + 0.3 * natural_ratio
        else:
            human_ratio = natural_ratio = 0.0
            hazard_index = 0.0

        penalty_factor = 1.0 - penalty_max * hazard_index
        if penalty_factor < 0.0:
            penalty_factor = 0.0

        adjusted_score = base_score * penalty_factor

        r2 = dict(r)
        r2["ontology_label"] = label
        r2["ontology_info"] = {
            "human_ratio": human_ratio,
            "natural_ratio": natural_ratio,
            "hazard_index": hazard_index,
            "penalty_factor": penalty_factor,
            "adjusted_score": adjusted_score,
            "detail": exp["pollutants"],
        }
        adjusted.append(r2)

    return adjusted

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

@app.get("/")
def root():
    return {"message": "Senior Ontology API is running", "health": "/health"}

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

# --- 4. USER: Change Password ---
@app.post("/change-password")
async def change_password(req: ChangePasswordRequest):
    users = read_users()
    for u in users:
        if u['email'].lower() == req.email.lower():
            if u['password'] != req.old_password:
                raise HTTPException(status_code=401, detail="Old password is incorrect")
            u['password'] = req.new_password
            save_users(users)
            print(f"🔒 Password changed: {u['email']}")
            return {"message": "Password updated successfully"}
    raise HTTPException(status_code=404, detail="Email not found")

# --- 5. DSS: Score Routes ---
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

        # Build global stats only from points that have at least one pollutant.
        df = pd.DataFrame(all_pollut).replace(9999.0, np.nan).dropna(how='all').fillna(0)
        df = df[CRITERIA]
        gmean = df.mean().to_dict()
        gstd = df.std(ddof=0).to_dict()
        critic_w = critic_weights(df)

        # Apply user preference boost
        if req.focus_pollutants:
            for f in req.focus_pollutants:
                f2 = (f or "").strip().lower()
                if f2 in critic_w:
                    critic_w[f2] *= 100
            total_w = sum(critic_w.values())
            critic_w = {k: v/total_w for k, v in critic_w.items()}

        max_dist = max(r.distance_meters for r in req.routes)
        max_time = max(r.duration_seconds for r in req.routes)

        scores = []
        async with httpx.AsyncClient() as client:
            for r in req.routes:
                decoded_pts = decode_poly(r.encoded_polyline)
                pts = sample_points(decoded_pts, req.sample_stride)

                p_rows = []
                for lat, lon in pts:
                    aq = await fetch_aqi(client, lat, lon)
                    p_rows.append(extract_pollutants(aq))

                # Fetch weather only at the starting point (first polyline point).
                # This matches the requirement: Dw validity comes from the route start only.
                h_rows = []
                if decoded_pts:
                    o_lat, o_lon = decoded_pts[0]
                    h_o = await fetch_humidity(client, o_lat, o_lon)
                    if h_o is not None:
                        h_rows.append(h_o)
                
                df_route_raw = pd.DataFrame(p_rows)
                df_route_valid = df_route_raw.replace(9999.0, np.nan).dropna(how="all")
                has_pollution = not df_route_valid.empty
                avg_p = df_route_raw.replace(9999.0, 0).mean().to_dict() if has_pollution else None

                avg_h = np.mean([h for h in h_rows if h is not None]) if any(h_rows) else 60.0
                w_scores = [weather_score(h) for h in h_rows if h is not None]

                res = evaluate_route(
                    {"distance_meters": r.distance_meters, "duration_seconds": r.duration_seconds},
                    {"distance": max_dist, "time": max_time},
                    critic_w, gmean, gstd, avg_p, w_scores, avg_h
                )
                base_score_result = {
                    "id": r.id,
                    "route_id": r.id,
                    "final_score": res["final_score"],
                    "di": res["di"],
                    "dt": res["dt"],
                    "dp": res["dp"],
                    "dw": res["dw"],
                    "avg_humidity": res["avg_humidity"],
                    "weatherValid": res["weather_valid"],
                    "points_sampled": len(pts),
                    "points_used": len(p_rows),
                    "note": "ok",
                    "avg_pollution_raw": res.get("avg_pollution_raw"),
                }
                scores.append(base_score_result)

        # Optional ontology adjustment (not used by the current tests but matches the notebook).
        if req.use_ontology:
            pollutant_sources, source_types = _get_ontology_maps()
            adjusted = apply_ontology_adjustment(scores, pollutant_sources, source_types, penalty_max=0.30)
            final_results = adjusted
        else:
            final_results = scores

        resp_scores = []
        for r in final_results:
            resp_scores.append(
                ScoreResult(
                    id=r["id"],
                    risk_score=r.get("final_score") if not req.use_ontology else r["ontology_info"]["adjusted_score"],
                    di=r["di"],
                    dt=r["dt"],
                    dp=r["dp"],
                    dw=r["dw"],
                    avgHumidity=r["avg_humidity"],
                    weatherValid=r["weatherValid"],
                    points_sampled=r["points_sampled"],
                    points_used=r["points_used"],
                    note=r["note"],
                    ontology_label=r.get("ontology_label"),
                    ontology_info=r.get("ontology_info"),
                )
            )
        return ScoreResponse(scores=resp_scores)
    except Exception as e:
        print(f"Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", "8000"))
    uvicorn.run(app, host="0.0.0.0", port=port)
