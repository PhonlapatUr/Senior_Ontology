# Frontend Troubleshooting Guide

## Quick Checks

### 1. Verify Dependencies
```bash
flutter pub get
```

### 2. Clean Build
```bash
flutter clean
flutter pub get
flutter run
```

### 3. Check for Devices
```bash
flutter devices
```

## Common Issues and Solutions

### Issue: App Won't Start / Crashes on Launch

**Possible Causes:**
1. Missing dependencies
2. File permission issues
3. Path provider not configured

**Solution:**
```bash
flutter clean
flutter pub get
flutter run -d <device-id>
```

### Issue: Login/Signup Buttons Are Disabled

**This is Expected Behavior:**
- **Login Button**: Disabled until both email AND password fields have text
- **Sign Up Button**: Disabled until ALL fields are filled and valid:
  - First Name ✓
  - Last Name ✓
  - Email (with @ and .) ✓
  - Phone Number (at least 8 characters) ✓
  - Password (at least 6 characters) ✓
  - Confirm Password (must match password) ✓

**Solution:** Fill in all required fields. The button will enable automatically.

### Issue: "Invalid email or password" Error

**Possible Causes:**
1. Key.json doesn't exist yet (need to sign up first)
2. Wrong email/password entered
3. Key.json file corrupted

**Solution:**
1. If first time user, go to Sign Up screen
2. Create an account with all fields filled
3. Then use those credentials to login

### Issue: Can't Save User Data

**Possible Causes:**
1. File system permissions
2. Path provider not working

**Solution:**
- The app saves to app's documents directory automatically
- Check console logs for error messages
- Try signing up again

### Issue: App Stuck on Loading Screen

**Possible Causes:**
1. Error checking authentication status
2. File read error

**Solution:**
- Check console for error messages
- The app should default to welcome screen if there's an error
- Try force closing and reopening the app

## Testing the Authentication Flow

### Step 1: First Time User
1. App opens → Welcome Screen
2. Click "Sign Up"
3. Fill ALL fields:
   - First Name: `John`
   - Last Name: `Doe`
   - Email: `john@example.com`
   - Phone: `0801234568`
   - Password: `password123`
   - Confirm Password: `password123`
4. Click "Sign up" (button should be enabled when all fields valid)
5. Should see success message
6. Redirected to Login screen

### Step 2: Login
1. Enter email: `john@example.com`
2. Enter password: `password123`
3. Click "Login" (button enabled when both fields filled)
4. Should redirect to Map screen

### Step 3: Returning User
1. If already logged in, app opens directly to Map screen
2. If not logged in, shows Welcome screen

## Debug Commands

### Check Flutter Setup
```bash
flutter doctor
```

### Run with Verbose Logging
```bash
flutter run -d <device-id> --verbose
```

### Check for Errors
```bash
flutter analyze
```

### View Logs (Android)
```bash
adb logcat | grep flutter
```

## File Locations

- **Key.json Location**: App's documents directory (not project root on mobile)
- **Android**: `/data/data/com.example.senior/app_flutter/Key.json`
- **iOS**: App's Documents directory
- **Desktop**: App's documents directory

## Still Not Working?

1. **Check Console Output**: Look for error messages in terminal
2. **Verify Backend**: Make sure backend server is running on port 8000
3. **Check Network**: Ensure device can reach backend (Android emulator uses `10.0.2.2:8000`)
4. **Try Web Version**: `flutter run -d chrome` to test in browser
5. **Check Device Logs**: Use `flutter logs` or device-specific logging tools

## Contact Information

If issues persist, provide:
- Error messages from console
- Device/emulator being used
- Steps to reproduce the issue
- Screenshots if possible
