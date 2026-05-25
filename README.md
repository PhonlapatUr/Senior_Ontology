# Smart Route Finder

A Flutter-based mobile application that helps users find the safest and most optimal routes by analyzing pollution levels, weather conditions, distance, and travel time using a Decision Support System (DSS).

## Manual

### 1) Prerequisites

- Python 3.8+ installed
- Flutter SDK installed (latest stable version)
- Android Studio (for Android emulator)
- Virtual environment `.venv311` in project root
- Google Maps API key configured in app

### 2) Open Project

```bash
cd "<your-username>/Senior_Ontology-main-fixing"
```

Use your own local path to the project directory.

### 3) Start Backend Server

```bash
source .venv311/bin/activate
pip install -r requirements.txt
uvicorn server:app --reload --host 0.0.0.0 --port 8000
```

Backend runs at:
- `http://127.0.0.1:8000` (desktop)
- `http://10.0.2.2:8000` (Android emulator)

### 4) Run Flutter App

```bash
flutter pub get
flutter run -d emulator-5554
# or
flutter run
```

### 5) User Authentication Flow

#### Sign Up
1. Open app and click **Sign Up**
2. Fill all fields:
   - First Name
   - Last Name
   - Email
   - Phone Number
   - Password (minimum 6 characters)
   - Confirm Password
3. Click **Sign Up**
4. Data is sent to backend and saved in `Key.json`

Password handling:
- Password input is sent over HTTPS/TLS in production
- Backend hashes password with bcrypt before storage
- Only bcrypt hash is stored in `Key.json`

#### Login
1. Open app and click **Login**
2. Enter email and password
3. Click **Login**
4. Backend verifies entered password against stored bcrypt hash
5. On success, app navigates to map screen

### 6) Use Route Finder

1. Enter origin and destination
2. Select transportation mode (**DRIVE** or **WALK**)
3. Select pollution priorities
4. Request routes and review DSS scores (Di, Dt, Dp, Dw)
5. Start navigation

### 7) Deploy Backend for All Users

Deploy backend to a public host (Render/Railway/VPS) using:

- Build command: `pip install -r requirements.txt`
- Start command: `uvicorn server:app --host 0.0.0.0 --port $PORT`

Build app with deployed backend URL:

```bash
flutter build apk --dart-define=BACKEND_URL=https://your-server-url
```

Production must use HTTPS.

### 8) Useful Commands

Run backend tests:

```bash
./unit_test/run_coverage.sh
```

### 9) Troubleshooting

- Backend not connecting: confirm backend is running on port 8000 and app URL is correct
- Login/signup failed: check backend logs and `Key.json` write permission
- Map not loading: verify Google Maps API key and internet connection

For more details, see `RUN_GUIDE.md` and `TROUBLESHOOTING.md`.
