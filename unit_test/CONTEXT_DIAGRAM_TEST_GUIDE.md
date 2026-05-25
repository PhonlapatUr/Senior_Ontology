# Context diagram and backend unit tests

The **context diagram** defines four top-level capabilities **1.0–4.0**. Backend tests are split into **four modules** with matching names. Route geometry from **Google Map API** and list/selection UI are primarily in the Flutter client; the server tests focus on **POST /scoreRoutes**, **User Info** persistence (mocked), and **Pollution / Relative Humidity** behaviour (mocked where needed).

## 1.0 User registration

**Module:** `unit_test/UnitTest_1_0_User_Registration.py`

| DFD | Coverage |
|-----|----------|
| 1.1 Get user information | `test_dfd_1_1_get_user_info_signup_payload` — five fields via `UserRegister` / `signup` |
| 1.2 Check existing user | `test_dfd_1_2_check_existing_user_duplicate`, `test_dfd_1_2_check_email_endpoint` |
| 1.3 Record user information | Signup persist; `test_dfd_1_3_record_and_post_registration_password` (incl. change password on same store) |

## 2.0 Login

**Module:** `unit_test/UnitTest_2_0_Login.py`

| DFD | Coverage |
|-----|----------|
| 2.1 Get user information | `LoginRequest` (email, password) |
| 2.2 Check existing user | Success, case-insensitive email, wrong password, unknown email |
| 2.0 Login completion | Success returns user subset; `test_api_health_root_available` (service up) |

## 3.0 Find a route with no pollution preference

**Module:** `unit_test/UnitTest_3_0_Route_No_Pollution_Preference.py`  
**Fixture:** `unit_test/dfd_route_fixtures.py`

| DFD | Coverage |
|-----|----------|
| 3.1 Get route input | Polyline decode, sample points, cache key; fixture supplies encoded route |
| 3.2 Generate route list | Client-side list; server scores candidates — `test_dfd_3_0_score_routes_without_focus_pollutants` with `focus_pollutants=None` |
| 3.3 / 3.4 Selection & detail | `evaluate_route`, pollution/weather/critic tests; response fields di, dt, dp, dw, risk_score |
| External APIs (mocked) | `fetch_aqi`, `fetch_humidity`, plus support tests for ontology and extract_pollutants |

## 4.0 Find a route with pollution preference

**Module:** `unit_test/UnitTest_4_0_Route_With_Pollution_Preference.py`

| DFD | Coverage |
|-----|----------|
| 4.1 Get route input | Same fixture as 3.0 (polyline + metrics) |
| 4.2 Get pollution input | `focus_pollutants=['pm2.5']` on `score_routes` |
| 4.3–4.5 | Weighted scoring vs baseline; `test_dfd_4_0_score_routes_with_focus_pollutants` captures critic weights |

## Commands

- Run all four modules: `./unit_test/run_coverage.sh`
