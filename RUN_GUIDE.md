# How to Run the Application

This guide explains how to run both the backend server (Python/FastAPI) and the frontend (Flutter app).

## Prerequisites

- Python 3.8+ installed
- Flutter SDK installed
- Android Studio (for Android emulator) or Xcode (for iOS simulator)
- Virtual environment (venv) already exists in the project

---

## Part 1: Running the Backend Server

### Step 1: Activate Virtual Environment

```bash
# Navigate to project directory
cd "/Users/phonlapaturairong/Desktop/Senior_1/senior copy"

# Activate virtual environment
source venv/bin/activate
```

### Step 2: Install/Update Dependencies

```bash
# Install all required packages
pip install -r requirements.txt
```

### Step 3: Start the Server

```bash
# Run the FastAPI server with uvicorn
uvicorn server:app --reload --host 0.0.0.0 --port 8000
```

**Expected Output:**
```
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
INFO:     Started reloader process
INFO:     Started server process
INFO:     Waiting for application startup.
INFO:     Application startup complete.
```

### Step 4: Verify Server is Running

Open your browser and visit:
- **Health Check**: http://127.0.0.1:8000/health
- **API Docs**: http://127.0.0.1:8000/docs (Swagger UI)
- **Alternative Docs**: http://127.0.0.1:8000/redoc

You should see `{"ok": true}` for the health endpoint.

### Step 5: Check Ontology Status (Optional)

Visit: http://127.0.0.1:8000/ontology/status

This will show if the ontology file is loaded correctly.

---

## Part 2: Running the Flutter Frontend

### Step 1: Install Flutter Dependencies

```bash
# Make sure you're in the project root directory
cd "/Users/phonlapaturairong/Desktop/Senior_1/senior copy"

# Get Flutter packages
flutter pub get
```

### Step 2: Check Available Devices

```bash
# List all available devices/emulators
flutter devices
```

**Expected Output:**
```
2 connected devices:

sdk gphone64 arm64 (mobile) • emulator-5554 • android-arm64  • Android 14 (API 36.1) (emulator)
iPhone 15 Pro (mobile)      • 12345678-1234  • ios            • com.apple.CoreSimulator.SimRuntime.iOS-17-0 (simulator)
```

### Step 3: Start Android Emulator (if using Android)

**Option A: Using Command Line (Recommended)**
```bash
# Set Android SDK path
export ANDROID_HOME=/Users/phonlapaturairong/Library/Android/sdk

# Start the emulator (this will open a window)
$ANDROID_HOME/emulator/emulator -avd Medium_Phone_API_36.1
```

**Note:** The emulator window will appear and take 30-60 seconds to fully boot. Keep the terminal open.

**Option B: Using Android Studio**
1. Open Android Studio
2. Go to **Tools → Device Manager**
3. Click the ▶️ play button next to "Medium_Phone_API_36.1"

**Option C: Using Flutter Command**
```bash
# List available emulators
flutter emulators

# Launch emulator (if available)
flutter emulators --launch <emulator-id>
```

**Wait for emulator to boot**, then verify it's detected:
```bash
flutter devices
```

You should see something like:
```
sdk gphone64 arm64 (mobile) • emulator-5554 • android-arm64
```

### Step 4: Run the Flutter App

**For Android:**
```bash
flutter run -d emulator-5554
# Or simply:
flutter run
```

**For iOS (macOS only):**
```bash
flutter run -d <device-id>
# Or:
flutter run
```

**For Web:**
```bash
flutter run -d chrome
```

---

## Quick Start Scripts

### Option 1: Run Backend Only

Create a file `start_backend.sh`:
```bash
#!/bin/bash
cd "/Users/phonlapaturairong/Desktop/Senior_1/senior copy"
source venv/bin/activate
uvicorn server:app --reload --host 0.0.0.0 --port 8000
```

Make it executable and run:
```bash
chmod +x start_backend.sh
./start_backend.sh
```

### Option 2: Run Both (Separate Terminals)

**Terminal 1 - Backend:**
```bash
cd "/Users/phonlapaturairong/Desktop/Senior_1/senior copy"
source venv/bin/activate
uvicorn server:app --reload --host 0.0.0.0 --port 8000
```

**Terminal 2 - Frontend:**
```bash
cd "/Users/phonlapaturairong/Desktop/Senior_1/senior copy"
flutter run
```

---

## Important Notes

### Backend URL Configuration

The Flutter app is configured to connect to:
- **Android Emulator**: `http://10.0.2.2:8000` (special IP for Android emulator)
- **iOS Simulator/Other**: `http://127.0.0.1:8000` (localhost)

This is automatically handled in `lib/screens/map_screen.dart`.

### Port Configuration

- Backend runs on **port 8000** by default
- If port 8000 is busy, change it in the uvicorn command:
  ```bash
  uvicorn server:app --reload --host 0.0.0.0 --port 8001
  ```
  Then update `lib/screens/map_screen.dart` to use the new port.

### Troubleshooting

1. **Server not starting?**
   - Check if port 8000 is already in use: `lsof -i :8000`
   - Kill the process: `kill -9 <PID>`

2. **Flutter can't connect to backend?**
   - Make sure backend is running first
   - Check the URL in `lib/screens/map_screen.dart`
   - For Android emulator, use `10.0.2.2` not `127.0.0.1`

3. **Ontology not loading?**
   - Verify `ontology_fixed.ttl` exists in the project root
   - Check server logs for ontology errors
   - Visit `/ontology/status` endpoint to verify

4. **Dependencies issues?**
   - Backend: `pip install -r requirements.txt --upgrade`
   - Frontend: `flutter pub get`
   - If path_provider is missing: `flutter pub get` (already added to pubspec.yaml)

5. **Authentication not working?**
   - Make sure all fields are filled during signup
   - Check that email format is valid (contains @ and .)
   - Verify password is at least 6 characters
   - Ensure passwords match in signup confirmation
   - User data is saved to Key.json in the app's documents directory

---

## Testing the Integration

1. **Start the backend server** (Terminal 1)
2. **Start the Flutter app** (Terminal 2 or Android Studio)
3. **In the app:**
   - **First Time Users**: You'll see the Welcome screen
     - Click "Sign Up" to create a new account
     - Fill in all required fields (First Name, Last Name, Email, Phone Number, Password, Confirm Password)
     - Click "Sign up" to save your information to Key.json
     - You'll be redirected to the Login screen
   - **Existing Users**: 
     - Click "Login" from the Welcome screen
     - Enter your email and password (from Key.json)
     - You'll be redirected to the Map screen if credentials are correct
   - **After Login**:
     - Search for a location
     - Request routes
     - The app will call the backend API to score routes
     - You should see route scores displayed

### Authentication Notes

- **User data is saved in Key.json** (stored in the app's documents directory)
- **All fields are required** during signup
- **Password must be at least 6 characters**
- **Passwords must match** in signup confirmation
- **Email format is validated**
- The app checks authentication status on startup and redirects accordingly

---

## API Endpoints

Once the server is running, you can test these endpoints:

- `GET /health` - Health check
- `GET /ontology/status` - Check ontology loading status
- `POST /scoreRoutes` - Score routes (used by Flutter app)
- `GET /docs` - Interactive API documentation (Swagger UI)
- `GET /redoc` - Alternative API documentation

---

## Stopping the Services

- **Backend**: Press `Ctrl+C` in the terminal running uvicorn
- **Flutter**: Press `q` in the terminal, or stop from Android Studio/Xcode
- **Deactivate venv**: Run `deactivate` when done

---

## Environment Variables (Optional)

You can set these environment variables before starting the server:

```bash
export GOOGLE_API_KEY="your-api-key"
export TMD_TOKEN="your-tmd-token"
```

Or create a `.env` file (not included in repo for security).
