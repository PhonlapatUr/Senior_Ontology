#!/bin/bash

# Script to view all users from Key.json

echo "=========================================="
echo "All Registered Users in Database"
echo "=========================================="
echo ""

# Check project root Key.json
PROJECT_FILE="Key.json"

if [ -f "$PROJECT_FILE" ]; then
    echo "📁 Reading from project root: $PROJECT_FILE"
    echo ""
    
    # Use Python to parse and display JSON nicely
    python3 << 'EOF'
import json
import sys

try:
    with open('Key.json', 'r') as f:
        data = json.load(f)
    
    if isinstance(data, list):
        users = data
    elif isinstance(data, dict):
        # Old format - single user
        users = [data]
    else:
        users = []
    
    if not users:
        print("❌ No users found in database")
        sys.exit(1)
    
    print(f"✅ Total users: {len(users)}")
    print("")
    print("=" * 60)
    
    for i, user in enumerate(users, 1):
        print(f"\n👤 User #{i}:")
        print(f"   First Name: {user.get('firstname', 'N/A')}")
        print(f"   Last Name:  {user.get('lastname', 'N/A')}")
        print(f"   Email:      {user.get('email', 'N/A')}")
        print(f"   Phone:      {user.get('phonenum', 'N/A')}")
        print(f"   Password:   {'*' * len(user.get('password', ''))} ({len(user.get('password', ''))} characters)")
        if i < len(users):
            print("-" * 60)
    
    print("\n" + "=" * 60)
    
except FileNotFoundError:
    print("❌ Key.json file not found in project root")
    sys.exit(1)
except json.JSONDecodeError as e:
    print(f"❌ Error parsing JSON: {e}")
    sys.exit(1)
except Exception as e:
    print(f"❌ Error: {e}")
    sys.exit(1)
EOF

    echo ""
    
    # Also try to get from Android device if available
    if command -v adb &> /dev/null; then
        if adb devices | grep -q "device$"; then
            echo ""
            echo "📱 Also checking Android device..."
            DEVICE_DATA=$(adb shell "run-as com.example.senior cat /data/data/com.example.senior/app_flutter/Key.json" 2>/dev/null)
            
            if [ ! -z "$DEVICE_DATA" ]; then
                echo "$DEVICE_DATA" | python3 << 'EOF'
import json
import sys

try:
    data = json.load(sys.stdin)
    
    if isinstance(data, list):
        users = data
    elif isinstance(data, dict):
        users = [data]
    else:
        users = []
    
    if users:
        print(f"✅ Found {len(users)} user(s) on device")
        print("(Same as project root or different)")
    else:
        print("⚠️  No users found on device")
except:
    print("⚠️  Could not parse device data")
EOF
            fi
        fi
    fi
    
else
    echo "❌ Key.json file not found in project root"
    echo ""
    echo "💡 If you're testing on mobile, the file is saved in the app directory."
    echo "   Run this command to view it:"
    echo "   adb shell 'run-as com.example.senior cat /data/data/com.example.senior/app_flutter/Key.json'"
    exit 1
fi
