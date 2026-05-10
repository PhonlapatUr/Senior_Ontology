# Quick Start Guide

## 🚀 Running the Application

### Step 1: Start the Backend Server

Open Terminal 1:

```bash
cd "/Users/phonlapaturairong/Desktop/Senior_1/senior copy"
source venv/bin/activate
uvicorn server:app --reload --host 0.0.0.0 --port 8000
```

Wait for: `INFO:     Uvicorn running on http://0.0.0.0:8000`

### Step 2: Start the Flutter App

Open Terminal 2:

```bash
cd "/Users/phonlapaturairong/Desktop/Senior_1/senior copy"
flutter pub get
flutter run
```

**Or if you need to select a device:**
```bash
flutter devices          # List available devices
flutter run -d <device-id>
```

### Step 3: Use the App

1. **First Time?** → Click "Sign Up"
   - Fill in: First Name, Last Name, Email, Phone, Password, Confirm Password
   - Click "Sign up"
   - You'll be redirected to Login

2. **Already have account?** → Click "Login"
   - Enter your Email and Password
   - Click "Login"

3. **After Login** → You'll see the Map screen
   - Search for locations
   - Get route recommendations

---

## 📋 Prerequisites Checklist

- [ ] Python 3.8+ installed
- [ ] Flutter SDK installed (`flutter --version`)
- [ ] Virtual environment exists (`venv/` folder)
- [ ] Android emulator or iOS simulator running
- [ ] Backend dependencies installed (`pip install -r requirements.txt`)

---

## 🔧 Common Commands

### Backend
```bash
# Activate venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Run server
uvicorn server:app --reload --host 0.0.0.0 --port 8000

# Deactivate venv
deactivate
```

### Flutter
```bash
# Get dependencies
flutter pub get

# Check devices
flutter devices

# Run app
flutter run

# Clean build
flutter clean && flutter pub get
```

---

## 🐛 Quick Troubleshooting

| Problem | Solution |
|---------|----------|
| Port 8000 in use | `lsof -i :8000` then `kill -9 <PID>` |
| Flutter can't find device | Start emulator first: `flutter emulators --launch <id>` |
| Backend not connecting | Check URL: Android uses `10.0.2.2:8000`, iOS uses `127.0.0.1:8000` |
| Dependencies missing | Run `flutter pub get` and `pip install -r requirements.txt` |

---

## 📱 Testing Authentication

1. **Sign Up Flow:**
   - Open app → Welcome screen
   - Click "Sign Up"
   - Fill all fields (validation will show errors if missing)
   - Submit → Redirected to Login

2. **Login Flow:**
   - Enter email and password from signup
   - Submit → Redirected to Map screen

3. **Auto-login:**
   - If already logged in, app opens directly to Map screen

---

For detailed information, see `RUN_GUIDE.md`
