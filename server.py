#!/usr/bin/env python3
import os, asyncio, time
from typing import Dict, List, Optional, Tuple

import httpx
import polyline as gpoly
import numpy as np
import pandas as pd

from fastapi import FastAPI, HTTPException
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
CRITERIA = ["pm2.5", "pm10", "co", "no2", "o3", "so2"]
POLLUTANTS_ALLOWED = ["pm2.5", "pm10", "co", "no2", "o3", "so2"]

# Ontology path
ONTOLOGY_PATH = os.path.join(os.path.dirname(__file__), "ontology_fixed.ttl")

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
    focus_pollutants: Optional[List[str]] = None  # For preference mode
    use_ontology: bool = False  # Enable ontology adjustment


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
            code = "pm2.5"  # Use pm2.5 for consistency with notebook
        else:
            code = raw

        val = (p.get("concentration") or {}).get("value")
        out[code] = float(val) if val is not None else 9999.0

    if len(out) == 0:
        out = {k: 9999.0 for k in CRITERIA}

    for k in CRITERIA:
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


def weather_score(relative_humidity: Optional[int]) -> int:
    if relative_humidity is None:
        return 2
    if relative_humidity > 75:
        return 3
    elif relative_humidity < 40:
        return 1
    return 2


# ============================================================
# NEW DSS FUNCTIONS (from notebook)
# ============================================================

def pollution_score(pm25=0, pm10=0, co=0, no2=0, o3=0, so2=0):
    """Rule-based pollution scoring (1-3 scale)"""
    if pm25 > 75:
        pm25_score = 1
    elif pm25 > 50:
        pm25_score = 2
    else:
        pm25_score = 3

    if pm10 > 150:
        pm10_score = 1
    elif pm10 > 100:
        pm10_score = 2
    else:
        pm10_score = 3

    co_mg = co / 1000
    if co_mg > 7:
        co_score = 1
    elif co_mg > 4:
        co_score = 2
    else:
        co_score = 3

    if no2 > 120:
        no2_score = 1
    elif no2 > 50:
        no2_score = 2
    else:
        no2_score = 3

    if o3 > 160:
        o3_score = 1
    elif o3 > 120:
        o3_score = 2
    else:
        o3_score = 3

    if so2 > 125:
        so2_score = 1
    elif so2 > 50:
        so2_score = 2
    else:
        so2_score = 3

    return min(pm25_score, pm10_score, co_score, no2_score, o3_score, so2_score)


def critic_weights(data: pd.DataFrame) -> dict:
    """Calculate CRITIC weights"""
    if data.empty or len(data) == 0:
        # Return equal weights if no data
        return {k: 1.0 / len(CRITERIA) for k in CRITERIA}
    
    # Normalize data
    norm = data.apply(lambda x: (x.max() - x) / (x.max() - x.min() + 1e-12))
    std = norm.std(ddof=0)
    corr = norm.corr()
    conflict = (1 - corr).sum()
    beta = std * conflict
    
    # Handle case where beta sum is zero or all NaN
    beta_sum = beta.sum()
    if beta_sum == 0 or pd.isna(beta_sum):
        # Return equal weights if calculation fails
        return {k: 1.0 / len(CRITERIA) for k in CRITERIA}
    
    weights = beta / beta_sum
    # Fill any NaN values with equal weights
    weights = weights.fillna(1.0 / len(CRITERIA))
    return weights.to_dict()


def route_pollution_score(avg_pollution: dict, critic_w: dict, global_mean: dict, global_std: dict):
    """Calculate route pollution score using CRITIC method"""
    keys = list(critic_w.keys())
    vals = np.array([avg_pollution.get(k, 0) for k in keys], dtype=float)
    weights = np.array([critic_w.get(k, 0) for k in keys], dtype=float)

    means = np.array([global_mean.get(k, 0) for k in keys])
    stds = np.array([global_std.get(k, 0) for k in keys])
    
    # Ensure stds is not too small to avoid extreme z-scores
    # If std is very small (< 0.1), use a minimum std of 0.1 for more stable normalization
    stds = np.maximum(stds, 0.1)

    z = (vals - means) / stds
    mapped = 1 / (1 + np.exp(-z))
    
    # Normalize weights sum to handle potential rounding issues
    weights_sum = weights.sum()
    if weights_sum == 0 or np.isnan(weights_sum):
        weights_sum = 1.0
    
    score = float(np.dot(mapped, weights) / weights_sum)
    return score, dict(zip(keys, mapped))


def _parse_focus_list(focus_pollutants: Optional[List[str]]) -> List[str]:
    """Parse and validate focus pollutant list"""
    if not focus_pollutants:
        return []
    
    seen = set()
    out = []
    for p in focus_pollutants:
        p_lower = p.strip().lower()
        if p_lower in POLLUTANTS_ALLOWED and p_lower not in seen:
            out.append(p_lower)
            seen.add(p_lower)
    return out


def _apply_preference_to_weights(critic_w: dict, focus_list: list, boost: float = 100.0) -> dict:
    """Apply user preference boost to CRITIC weights"""
    w = dict(critic_w)
    for f in focus_list:
        if f in w:
            w[f] = w[f] * boost

    s = sum(w.values()) + 1e-12
    w_norm = {k: v / s for k, v in w.items()}
    return w_norm


# ============================================================
# ONTOLOGY FUNCTIONS
# ============================================================

def load_ontology_maps(ttl_path: str):
    """Load ontology and extract pollutant-source mappings"""
    try:
        from rdflib import Graph, Namespace, RDF, RDFS, OWL
    except Exception as e:
        print(f"[Ontology] rdflib not installed or error: {e}")
        return {}, {}

    if not os.path.exists(ttl_path):
        print(f"[Ontology] File not found: {ttl_path}")
        return {}, {}

    try:
        g = Graph()
        g.parse(ttl_path, format="turtle")
        AP = Namespace("http://www.example.org/airpollution#")

        pollutant_sources = {}
        source_types = {}

        # Extract direct hasSource relationships (if any)
        for s, p, o in g.triples((None, AP.hasSource, None)):
            pol_name = str(s).split("#")[-1]
            src_name = str(o).split("#")[-1]
            pollutant_sources.setdefault(pol_name, set()).add(src_name)

        # Extract hasSource from OWL restrictions
        # Pattern: :Pollutant rdfs:subClassOf [ owl:onProperty :hasSource ; owl:someValuesFrom :Source ]
        for pollutant_class in g.subjects(RDF.type, OWL.Class):
            pol_name = str(pollutant_class).split("#")[-1]
            
            # Check for restrictions with hasSource
            for restriction in g.objects(pollutant_class, RDFS.subClassOf):
                # Check if this is a restriction
                if (restriction, RDF.type, OWL.Restriction) in g:
                    # Get the property
                    for prop in g.objects(restriction, OWL.onProperty):
                        if prop == AP.hasSource:
                            # Get the source class
                            for source_class in g.objects(restriction, OWL.someValuesFrom):
                                src_name = str(source_class).split("#")[-1]
                                pollutant_sources.setdefault(pol_name, set()).add(src_name)

        # Extract type relationships (for HumanSources/NaturalSources classification)
        for s, p, o in g.triples((None, RDF.type, None)):
            ent = str(s).split("#")[-1]
            typ = str(o).split("#")[-1]
            source_types.setdefault(ent, set()).add(typ)

        # Extract subclass relationships for HumanSources/NaturalSources
        for s, p, o in g.triples((None, RDFS.subClassOf, AP.HumanSources)):
            ent = str(s).split("#")[-1]
            source_types.setdefault(ent, set()).add("HumanSources")

        for s, p, o in g.triples((None, RDFS.subClassOf, AP.NaturalSources)):
            ent = str(s).split("#")[-1]
            source_types.setdefault(ent, set()).add("NaturalSources")

        # Also check direct type assertions
        for s, p, o in g.triples((None, RDF.type, AP.HumanSources)):
            ent = str(s).split("#")[-1]
            source_types.setdefault(ent, set()).add("HumanSources")

        for s, p, o in g.triples((None, RDF.type, AP.NaturalSources)):
            ent = str(s).split("#")[-1]
            source_types.setdefault(ent, set()).add("NaturalSources")

        return pollutant_sources, source_types
    except Exception as e:
        print(f"[Ontology] Error loading ontology: {e}")
        import traceback
        traceback.print_exc()
        return {}, {}


def ontology_explain_route(avg_pollution: dict, pollutant_sources: dict, source_types: dict):
    """Analyze route pollution using ontology"""
    if not avg_pollution:
        return "Unknown", {
            "human_score": 0.0,
            "natural_score": 0.0,
            "total_score": 0.0,
            "pollutants": {}
        }

    key_to_ttl = {
        "pm2.5": "PM2.5",
        "pm10": "PM10",
        "co": "CO",
        "no2": "NO2",
        "o3": "O3",
        "so2": "SO2"
    }

    detail = {}
    human_score = 0.0
    natural_score = 0.0
    total_score = 0.0

    for k, v in avg_pollution.items():
        if k not in key_to_ttl:
            continue

        ttl_pol = key_to_ttl[k]
        sources = sorted(list(pollutant_sources.get(ttl_pol, [])))

        src_type_list = []
        has_human = False
        has_natural = False

        for src in sources:
            types = sorted(list(source_types.get(src, [])))
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
            "flags": {"human": has_human, "natural": has_natural}
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
        "pollutants": detail
    }

    return label, explanation


def apply_ontology_adjustment(results: list, pollutant_sources: dict, source_types: dict,
                              penalty_max: float = 0.30):
    """Apply ontology-based penalty to route scores (matches notebook version)"""
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

        r2 = dict(r)  # Create copy (matches notebook)
        r2["ontology_label"] = label
        r2["ontology_info"] = {
            "human_ratio": human_ratio,
            "natural_ratio": natural_ratio,
            "hazard_index": hazard_index,
            "penalty_factor": penalty_factor,
            "adjusted_score": adjusted_score,
            "detail": exp["pollutants"]
        }
        r2["final_score"] = adjusted_score  # Update final score
        adjusted.append(r2)

    return adjusted


# ============================================================
# ROUTE EVALUATION (Enhanced from notebook)
# ============================================================

def evaluate_route(route_data: dict, max_values: dict, critic_w: dict, 
                  global_mean: dict, global_std: dict, avg_pollution: dict,
                  weather_scores: List[int], avg_humidity: float):
    """
    Evaluate route using enhanced DSS logic.
    
    Input data sources:
    - route_data: Contains distance_meters and duration_seconds from API request
    - max_values: Max distance/time from API request (for normalization)
    - avg_pollution: Average pollution data from Google Air Quality API
    - weather_scores: Weather data from TMD API
    - critic_w, global_mean, global_std: Calculated from pollution API data
    
    All data flows through calculation pipeline to produce:
    - di (distance indicator), dt (time indicator)
    - dp (pollution indicator), dw (weather indicator)
    - final_score (weighted combination of all indicators)
    """
    
    # ============================================================
    # Calculate distance and time indicators
    # Using distance/time from API request
    # ============================================================
    # Handle case where all routes have same distance/time or max is 0
    route_dist = route_data["distance_meters"]
    route_time = route_data["duration_seconds"]
    max_dist = max_values["distance"]
    max_time = max_values["time"]
    
    if max_dist == 0 or route_dist == 0:
        # If no distance data or route has no distance, set to 0.5 (neutral)
        di = 0.5
    elif route_dist >= max_dist:
        # If this route is the longest, it gets score 0 (worst)
        di = 0.0
    else:
        # Normalize: shorter routes get higher scores
        di = 1 - (route_dist / max_dist)
    
    if max_time == 0 or route_time == 0:
        # If no time data or route has no time, set to 0.5 (neutral)
        dt = 0.5
    elif route_time >= max_time:
        # If this route is the slowest, it gets score 0 (worst)
        dt = 0.0
    else:
        # Normalize: faster routes get higher scores
        dt = 1 - (route_time / max_time)

    di = max(0.0, min(di, 1.0))
    dt = max(0.0, min(dt, 1.0))

    has_pollution = avg_pollution is not None and len(avg_pollution) > 0
    # Check if pollution data is actually valid (not all zeros or missing)
    pollution_valid = False
    if has_pollution:
        # Check if we have any non-zero pollution values
        pollution_values = [v for v in avg_pollution.values() if v and v > 0]
        pollution_valid = len(pollution_values) > 0
    
    has_weather = len(weather_scores) > 0

    # ============================================================
    # Calculate pollution indicator
    # Using pollution data from Google Air Quality API
    # ============================================================
    if has_pollution and pollution_valid:
        # Check if pollution is actually very low (all zeros or near-zero)
        pollution_sum = sum(v for v in avg_pollution.values() if v and not pd.isna(v))
        if pollution_sum < 0.1:
            # Very clean air - give high score (good)
            critic_score = 0.0
            norm_vals = {k: 0.0 for k in CRITERIA if k in avg_pollution}
            dp = 1.0
        else:
            critic_score, norm_vals = route_pollution_score(
                avg_pollution, critic_w, global_mean, global_std
            )
            dp = 1 - critic_score
            # Ensure dp is in valid range
            dp = max(0.0, min(dp, 1.0))
        
        rb_level = pollution_score(
            pm25=avg_pollution.get("pm2.5", 0),
            pm10=avg_pollution.get("pm10", 0),
            co=avg_pollution.get("co", 0),
            no2=avg_pollution.get("no2", 0),
            o3=avg_pollution.get("o3", 0),
            so2=avg_pollution.get("so2", 0)
        )
        rb_norm = (rb_level - 1) / 2
    else:
        # No valid pollution data - set to neutral score
        critic_score = 0.5
        norm_vals = {}
        dp = 0.5  # Neutral score when no pollution data
        rb_level = None
        rb_norm = None

    # ============================================================
    # Calculate weather indicator
    # Using weather data from TMD API
    # ============================================================
    if has_weather and len(weather_scores) > 0:
        avg_weather = float(np.mean(weather_scores))
        dw = (avg_weather - 1) / 2
        # Ensure dw is in valid range [0, 1]
        dw = max(0.0, min(1.0, dw))
    else:
        dw = 0.5  # Default when no weather data

    # Final score calculation (from notebook logic)
    # Always use numeric values for dp and dw (ScoreResult requires floats)
    if not has_pollution and not has_weather:
        final_score = (0.50 * di) + (0.50 * dt)
        # Use default numeric values when data is missing
        dp_final = 0.5  # Neutral score when no pollution data
        dw_final = 0.5  # Neutral score when no weather data
    elif has_weather and not has_pollution:
        final_score = (0.45 * di) + (0.45 * dt) + (0.10 * dw)
        dp_final = 0.5  # Neutral score when no pollution data
        dw_final = dw
    elif has_pollution and not has_weather:
        final_score = (0.30 * di) + (0.30 * dt) + (0.40 * dp)
        dp_final = dp
        dw_final = 0.5  # Neutral score when no weather data
    else:
        final_score = (0.30 * di + 0.30 * dt + 0.30 * dp + 0.10 * dw)
        dp_final = dp
        dw_final = dw

    return {
        "final_score": final_score,
        "di": di,
        "dt": dt,
        "dp": dp_final,  # Always numeric
        "dw": dw_final,  # Always numeric
        "avg_pollution_raw": avg_pollution,
        "avg_pollution_score": critic_score,
        "avg_pollutant_norms": norm_vals,
        "rule_based_level": rb_level,
        "rule_based_score": rb_norm,
        "avg_humidity": avg_humidity
    }


# ============================================================
# SINGLE ROUTE SCORING
# ============================================================

async def score_single_route(route, stride, max_dist, max_time,
                             critic_w, gmean, gstd, pollutant_sources=None, 
                             source_types=None, use_ontology=False):
    """
    Score a single route.
    
    Data sources:
    - Distance/Time: from route parameter (route.distance_meters, route.duration_seconds)
    - Pollution: fetched from Google Air Quality API (fetch_aqi)
    - Weather: fetched from TMD API (fetch_humidity)
    All data then flows through evaluate_route() for scoring calculations.
    """
    # Decode polyline from route request
    pts = decode_poly(route.encoded_polyline)
    pts = sample_points(pts, stride)

    if not pts:
        return None

    # ============================================================
    # Fetch pollution and weather data from external APIs
    # ============================================================
    pollut_rows = []
    humidity_rows = []

    sem = asyncio.Semaphore(MAX_CONCURRENCY)

    async with httpx.AsyncClient(timeout=httpx.Timeout(HTTP_TIMEOUT)) as client:

        async def worker(lat, lon):
            async with sem:
                # Fetch pollution data from Google Air Quality API
                aqi = await fetch_aqi(client, lat, lon)
                pollut_rows.append(extract_pollutants(aqi))

                # Fetch weather data from TMD API
                h = await fetch_humidity(client, lat, lon)
                humidity_rows.append(h if h is not None else None)

        await asyncio.gather(*(worker(lat, lon) for lat, lon in pts))

    # Process pollution data from API
    df = pd.DataFrame(pollut_rows)
    # Replace 9999.0 with NaN for proper calculation
    df = df.replace(9999.0, np.nan)
    
    # Filter out rows with all NaN
    df_valid = df.dropna(how='all')
    
    if len(df_valid) == 0:
        avg_poll = None
    else:
        avg_poll = df_valid.mean().to_dict()
        # Replace NaN with 0 for missing values
        avg_poll = {k: (v if not pd.isna(v) else 0) for k, v in avg_poll.items()}

    # Process weather data from API
    valid_humidity = [h for h in humidity_rows if h is not None]
    weather_scores = [weather_score(h) for h in valid_humidity]
    # Calculate average humidity, default to 60.0 if no valid data
    if len(valid_humidity) > 0:
        avg_h = float(np.mean(valid_humidity))
    else:
        avg_h = 60.0

    # ============================================================
    # Prepare route data from API request
    # ============================================================
    # Distance and time come from the route request (not calculated here)
    route_data = {
        "distance_meters": route.distance_meters,  # From API request
        "duration_seconds": route.duration_seconds  # From API request
    }
    
    max_values = {
        "distance": max_dist,
        "time": max_time
    }

    eval_result = evaluate_route(
        route_data, max_values, critic_w, gmean, gstd,
        avg_poll, weather_scores, avg_h
    )

    final_score = eval_result["final_score"]
    
    # Apply ontology adjustment if enabled
    ontology_label = None
    ontology_info = None
    
    if use_ontology and pollutant_sources and source_types and avg_poll:
        route_result_temp = {
            "final_score": final_score,
            "avg_pollution_raw": avg_poll
        }
        adjusted_results = apply_ontology_adjustment(
            [route_result_temp], pollutant_sources, source_types, penalty_max=0.30
        )
        if adjusted_results:
            final_score = adjusted_results[0]["final_score"]
            ontology_label = adjusted_results[0].get("ontology_label")
            ontology_info = adjusted_results[0].get("ontology_info")

    return ScoreResult(
        id=route.id,
        risk_score=round(final_score, 4),
        di=round(eval_result["di"], 4),
        dt=round(eval_result["dt"], 4),
        dp=round(eval_result["dp"], 4),  # Always numeric now
        dw=round(eval_result["dw"], 4),  # Always numeric now
        avgHumidity=round(avg_h, 2),
        points_sampled=len(pts),
        points_used=len(pollut_rows),
        note="ok",
        ontology_label=ontology_label,
        ontology_info=ontology_info
    )


# ============================================================
# FASTAPI APP
# ============================================================

app = FastAPI(title="Smart Route DSS v3 (Enhanced)")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.post("/scoreRoutes", response_model=ScoreResponse)
async def score_routes(req: ScoreRequest):
    """
    Score routes endpoint.
    
    Data Flow:
    1. Distance/Time: Come from API request (req.routes[].distance_meters, duration_seconds)
    2. Pollution: Fetched from external API (Google Air Quality API via fetch_aqi)
    3. Weather: Fetched from external API (TMD API via fetch_humidity)
    4. All data flows through calculation pipeline to produce scores
    """
    try:
        # ============================================================
        # STEP 1: Fetch pollution data from external API
        # ============================================================
        # Collect pollution data from ALL routes to build global statistics
        all_pollut = []

        async with httpx.AsyncClient(timeout=httpx.Timeout(HTTP_TIMEOUT)) as client:
            for r in req.routes:
                # Decode polyline from route request
                pts = decode_poly(r.encoded_polyline)
                pts = sample_points(pts, req.sample_stride)

                # Fetch pollution data from Google Air Quality API for each point
                for lat, lon in pts:
                    aqi = await fetch_aqi(client, lat, lon)
                    all_pollut.append(extract_pollutants(aqi))

        # ============================================================
        # STEP 2: Process pollution data and build global statistics
        # ============================================================
        # Build global statistics from pollution data fetched from API
        df = pd.DataFrame(all_pollut)
        df = df.replace(9999.0, np.nan)
        df_valid = df.dropna(how='all')
        
        if len(df_valid) == 0:
            # Fallback: use all data even with NaN
            df_valid = df.fillna(0)
        
        # Ensure all criteria columns exist
        for col in CRITERIA:
            if col not in df_valid.columns:
                df_valid[col] = 0.0

        df_valid = df_valid[CRITERIA]
        
        # Handle empty DataFrame case
        if len(df_valid) == 0:
            # If DataFrame is completely empty, set default values
            gmean = {k: 0.0 for k in CRITERIA}
            gstd = {k: 1.0 for k in CRITERIA}
            # Create empty DataFrame with CRITERIA columns for CRITIC weights
            df_valid = pd.DataFrame(columns=CRITERIA)
        else:
            # Calculate mean and std with proper handling
            gmean = df_valid.mean(numeric_only=True).to_dict()
            gstd = df_valid.std(ddof=0, numeric_only=True).to_dict()
            
            # Fill NaN values and handle cases where std is 0 (all values same)
            for k in CRITERIA:
                if k not in gmean or pd.isna(gmean.get(k)):
                    gmean[k] = 0.0
                if k not in gstd or pd.isna(gstd.get(k)) or gstd.get(k) == 0:
                    # If std is 0 or NaN, use a default value to avoid division issues
                    # Use 10% of mean if mean > 0, otherwise use 1.0
                    mean_val = gmean.get(k, 0.0)
                    gstd[k] = max(0.1, abs(mean_val) * 0.1) if mean_val != 0 else 1.0
        
        # Calculate CRITIC weights from pollution data
        critic_w = critic_weights(df_valid)
        
        # Apply preference boost only if user selected pollutants
        # No boost if user has no pollution concern (focus_pollutants is None or empty)
        focus_list = _parse_focus_list(req.focus_pollutants)
        if focus_list and len(focus_list) > 0:
            # Boost all selected pollutants when user has pollution concern
            critic_w = _apply_preference_to_weights(critic_w, focus_list, boost=100.0)
        # If no pollutants selected (no concern), use original CRITIC weights without boost

        # ============================================================
        # STEP 3: Extract distance and time from API request
        # ============================================================
        # Distance and time come from the request API (req.routes)
        # These values are used for normalization in the scoring calculations
        max_dist = max(r.distance_meters for r in req.routes) if req.routes else 0
        max_time = max(r.duration_seconds for r in req.routes) if req.routes else 0

        # Load ontology if enabled
        pollutant_sources = None
        source_types = None
        if req.use_ontology:
            pollutant_sources, source_types = load_ontology_maps(ONTOLOGY_PATH)

        # ============================================================
        # STEP 4: Calculate scores for each route
        # ============================================================
        # For each route:
        # - Distance/Time: from route request (r.distance_meters, r.duration_seconds)
        # - Pollution: fetched from API in score_single_route()
        # - All data flows through evaluate_route() for scoring calculations
        tasks = [
            score_single_route(
                r,  # Route from API request (contains distance_meters, duration_seconds)
                req.sample_stride,
                max_dist,  # Max distance from request
                max_time,  # Max time from request
                critic_w,  # CRITIC weights from pollution data
                gmean,     # Global mean from pollution API data
                gstd,      # Global std from pollution API data
                pollutant_sources, 
                source_types, 
                req.use_ontology
            )
            for r in req.routes
        ]

        results = await asyncio.gather(*tasks, return_exceptions=True)
        # Filter out None results and exceptions
        valid_results = []
        for r in results:
            if isinstance(r, Exception):
                # Log the exception but continue with other routes
                import traceback
                error_msg = f"Error processing route: {str(r)}\n{traceback.format_exc()}"
                print(error_msg)
                continue
            if r is not None:
                valid_results.append(r)
        
        if not valid_results:
            # If all routes failed, raise an error
            raise HTTPException(status_code=500, detail="All routes failed to process")
        
        return ScoreResponse(scores=valid_results)
    except HTTPException:
        # Re-raise HTTP exceptions as-is
        raise
    except Exception as e:
        import traceback
        error_msg = f"Error in score_routes: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        # Return more detailed error message for debugging
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")


@app.get("/health")
def health():
    return {"ok": True}


@app.get("/ontology/status")
def ontology_status():
    """Check ontology loading status"""
    if os.path.exists(ONTOLOGY_PATH):
        pollutant_sources, source_types = load_ontology_maps(ONTOLOGY_PATH)
        return {
            "loaded": len(pollutant_sources) > 0,
            "path": ONTOLOGY_PATH,
            "pollutant_sources_count": len(pollutant_sources),
            "source_types_count": len(source_types)
        }
    return {
        "loaded": False,
        "path": ONTOLOGY_PATH,
        "error": "File not found"
    }
