# Smart Route Finder

A Flutter-based mobile application that helps users find the safest and most optimal routes by analyzing pollution levels, weather conditions, distance, and travel time using a Decision Support System (DSS).

## 🌟 Features

### Authentication System
- **User Registration**: Sign up with first name, last name, email, phone number, and password
- **User Login**: Secure login with email and password verification
- **Multiple Users Support**: Store and manage multiple user accounts
- **Data Persistence**: User data saved in `Key.json` file

### Route Finding & Analysis
- **Google Maps Integration**: Interactive map with route visualization
- **Multiple Route Options**: Compare different routes with safety scores
- **Decision Support System (DSS)**: Calculate route scores based on:
  - Distance (Di)
  - Travel Time (Dt)
  - Pollution Levels (Dp) - PM2.5, PM10, CO, NO2, O3, SO2
  - Weather Conditions (Dw)
- **CRITIC Method**: Advanced multi-criteria decision making
- **Ontology Integration**: Pollution source analysis and hazard assessment
- **Real-time Data**: Live pollution and weather data from APIs

### User Interface
- **Beautiful UI**: Modern, intuitive interface with color-coded information
- **Route Details**: Comprehensive route information display
- **DSS Calculation Screen**: Detailed breakdown of route scoring
- **Navigation Mode**: Turn-by-turn navigation support

## 📋 Prerequisites

- **Python 3.8+** installed
- **Flutter SDK** installed (latest stable version)
- **Android Studio** (for Android emulator) or **Xcode** (for iOS simulator)
- **Virtual environment** (venv) - already included in project
- **Google Maps API Key** - required for map functionality

## 🚀 Quick Start

### 1. Clone/Download the Project

```bash
cd "/Users/phonlapaturairong/Desktop/Senior_1/senior copy"
```

### 2. Set Up Backend Server

```bash
# Activate virtual environment
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Start the server
uvicorn server:app --reload --host 0.0.0.0 --port 8000
```

The backend server will run on `http://localhost:8000` (or `http://10.0.2.2:8000` for Android emulator).

### 3. Run Flutter App

```bash
# Get Flutter dependencies
flutter pub get

# Run on Android emulator
flutter run -d emulator-5554

# Or run on available device
flutter run
```

For detailed running instructions, see [RUN_GUIDE.md](RUN_GUIDE.md).

### Deploying so all users can use the app (any network)

To run the server in one place and let everyone use the app from anywhere (not only same WiFi):

1. **Deploy the backend** to a host with a public URL, for example:
   - [Railway](https://railway.app): connect your repo, add a Python service, set start command `uvicorn server:app --host 0.0.0.0 --port $PORT`, add env vars `GOOGLE_API_KEY`, `TMD_TOKEN` if needed.
   - [Render](https://render.com): New Web Service, build `pip install -r requirements.txt`, start `uvicorn server:app --host 0.0.0.0 --port $PORT`.
   - Or any VPS/cloud VM: run the server and expose port 8000 (or use `PORT` env); use HTTPS in production (e.g. nginx + Let’s Encrypt).

2. **Set the app’s backend URL** when building for production. Replace `https://your-app.railway.app` with your real server URL (no trailing slash):

   ```bash
   flutter build apk --dart-define=BACKEND_URL=https://your-app.railway.app
   # or for iOS:
   flutter build ios --dart-define=BACKEND_URL=https://your-app.railway.app
   ```

   For local/dev builds, omit `BACKEND_URL`; the app will keep using `127.0.0.1:8000` (or emulator URL).

3. **HTTPS**: Use HTTPS for the server in production so the app can call it from any network. Free tiers on Railway/Render provide HTTPS by default.

## 👤 User Authentication

### Sign Up

1. Open the app and click "Sign Up"
2. Fill in all required fields:
   - First Name
   - Last Name
   - Email (must be valid email format)
   - Phone Number (9-10 digits)
   - Password (minimum 6 characters)
   - Confirm Password (must match)
3. Click "Sign Up" button
4. User information is saved to `Key.json`

### Login

1. Open the app and click "Login"
2. Enter your registered email and password
3. Click "Login" button
4. Upon successful login, you'll be redirected to the map screen

### User Data Storage

User information is stored in `Key.json` file in array format:

```json
[
  {
    "firstname": "John",
    "lastname": "Doe",
    "email": "john@example.com",
    "phonenum": "0912345678",
    "password": "password123"
  },
  {
    "firstname": "Jane",
    "lastname": "Smith",
    "email": "jane@example.com",
    "phonenum": "0987654321",
    "password": "securepass"
  }
]
```

**Note**: 
- On **desktop/web**: Data is saved to project root `Key.json`
- On **mobile (Android/iOS)**: Data is saved to app's documents directory (sandboxed)

### Viewing All Users

To view all registered users, use the helper script:

```

For Android devices, pull the file:

```bash
adb shell "run-as com.example.senior cat /data/data/com.example.senior/app_flutter/Key.json"
```

## 🗺️ Using the Route Finder

### 1. Set Origin and Destination

- Enter your starting location in the "Your Location" field
- Enter your destination in the destination field
- Or use "My Location" button to use current GPS location

### 2. Select Transportation Mode

- **DRIVE**: Car routes
- **WALK**: Walking routes

### 3. Pollution Concerns (Optional)

- Choose if you have pollution concerns
- Select specific pollutants to prioritize (PM2.5, PM10, CO, etc.)
- This affects the DSS calculation weights

### 4. View Route Details

- See route distance and estimated time
- View pollution concerns and CRITIC point
- Check real-time factor scores (Di, Dt, Dp, Dw)
- Review the DSS equation and calculation
- See the final route score

### 5. Start Navigation

- Click "Next" to proceed
- Confirm when asked if you want to start the route
- Navigate with turn-by-turn directions

## 📁 Project Structure

```
senior copy/
├── lib/
│   ├── main.dart                 # App entry point
│   ├── screens/
│   │   ├── welcome_screen.dart  # Welcome/login/signup selection
│   │   ├── login_screen.dart    # User login
│   │   ├── signup_screen.dart   # User registration
│   │   └── map_screen.dart      # Main map and route finding
│   ├── widgets/
│   │   ├── detail_card.dart     # Route details display
│   │   ├── dss_calculation_screen.dart  # DSS calculation screen
│   │   ├── route_list.dart      # Route list widget
│   │   └── ...
│   ├── services/
│   │   ├── auth_service.dart    # User authentication
│   │   ├── backend_service.dart # Backend API communication
│   │   ├── google_routes_service.dart  # Google Routes API
│   │   └── ...
│   └── models/
│       ├── safe_score.dart      # Route score model
│       └── ...
├── server.py                    # FastAPI backend server
├── Key.json                     # User database (JSON)
├── ontology_fixed.ttl          # Pollution ontology
├── requirements.txt            # Python dependencies
├── pubspec.yaml                # Flutter dependencies
└── README.md                   # This file
```

## 🔧 Configuration

### Backend Configuration

The backend server runs on:
- **Desktop/Web**: `http://127.0.0.1:8000`
- **Android Emulator**: `http://10.0.2.2:8000`
- **iOS Simulator**: `http://127.0.0.1:8000`

### Google Maps API

Update the API key in `lib/screens/map_screen.dart`:

```dart
const String googleApiKey = "YOUR_API_KEY_HERE";
```

## 📊 Decision Support System (DSS)

The app uses a multi-criteria decision-making approach to evaluate routes:

### Factors Considered

1. **Distance (Di)**: Normalized distance score
2. **Time (Dt)**: Normalized travel time score
3. **Pollution (Dp)**: Air quality score based on multiple pollutants
4. **Weather (Dw)**: Weather condition score (humidity-based)

### Scoring Equation

The final score is calculated using weighted factors:

```
Final Score = (0.30 × Di) + (0.30 × Dt) + (0.30 × Dp) + (0.10 × Dw)
```

(Weights may vary based on available data)

### CRITIC Method

The CRITIC (Criteria Importance Through Intercriteria Correlation) method is used to:
- Analyze relationships between pollutants
- Calculate importance weights
- Provide objective scoring

## 🛠️ Development

### Running Tests

```bash
flutter test
```

### Building for Production

```bash
# Android
flutter build apk --release

# iOS
flutter build ios --release
```

## 📝 Helper Scripts

- `view_all_users.sh`: View all registered users in the database
- `view_user_data.sh`: View user data from Android device

Make scripts executable:

```bash
chmod +x *.sh
```

## 🐛 Troubleshooting

### Backend Not Connecting

- Ensure the backend server is running on port 8000
- Check if the correct URL is used (different for emulator vs device)
- Verify firewall settings

### User Data Not Saving

- On mobile: Data is saved in app directory, not project root
- Use `adb pull` to retrieve from Android device
- Check console logs for error messages

### Map Not Loading

- Verify Google Maps API key is correct
- Check API key restrictions and permissions
- Ensure internet connection is available

For more troubleshooting tips, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## 📚 Additional Documentation

- [RUN_GUIDE.md](RUN_GUIDE.md) - Detailed running instructions
- [QUICK_START.md](QUICK_START.md) - Quick start guide
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues and solutions

## 🤝 Contributing

This is a senior project. For questions or issues, please contact the development team.

## 📄 License

This project is for educational purposes.

---

**Last Updated**: 2024
