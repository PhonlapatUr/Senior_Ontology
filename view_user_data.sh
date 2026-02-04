#!/bin/bash

# Script to view user data from Android device

echo "=========================================="
echo "Viewing User Data from Android Device"
echo "=========================================="
echo ""

# Check if device is connected
if ! adb devices | grep -q "device$"; then
    echo "❌ No Android device connected!"
    echo "Please connect your device or start the emulator."
    exit 1
fi

echo "📱 Device connected"
echo ""

# Try to pull the Key.json file from the app directory
APP_DIR="/data/data/com.example.senior/app_flutter"
TEMP_FILE="/tmp/key_from_device.json"

echo "📥 Pulling Key.json from device..."
adb shell "run-as com.example.senior cat $APP_DIR/Key.json" > "$TEMP_FILE" 2>/dev/null

if [ -s "$TEMP_FILE" ]; then
    echo ""
    echo "✅ Found user data on device:"
    echo "=========================================="
    cat "$TEMP_FILE"
    echo "=========================================="
    echo ""
    echo "💡 To copy to project root, run:"
    echo "   adb shell 'run-as com.example.senior cat $APP_DIR/Key.json' > Key.json"
else
    echo ""
    echo "⚠️  No Key.json found in app directory"
    echo "The user might not have signed up yet, or the file is in a different location."
    echo ""
    echo "💡 Alternative: Check the console output when signing up"
    echo "   The app prints the saved user information to the console."
fi

rm -f "$TEMP_FILE"
