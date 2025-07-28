#!/bin/bash

echo "🔧 Adding Cortex Accessibility Permissions"
echo "=========================================="

# Get the exact path
CORTEX_PATH="/Users/shreyasgurav/Library/Developer/Xcode/DerivedData/Cortex-cqzmqlkfnwttsfaydnatslwiazpy/Build/Products/Debug/Cortex.app"

echo "📁 Cortex app path: $CORTEX_PATH"

# Check if the app exists
if [ ! -d "$CORTEX_PATH" ]; then
    echo "❌ Cortex app not found at: $CORTEX_PATH"
    echo "Please build the app first using Xcode"
    exit 1
fi

echo "✅ Cortex app found"

# Kill any existing Cortex processes
echo "🔄 Stopping any running Cortex processes..."
killall Cortex 2>/dev/null || true

# Reset accessibility permissions
echo "🔄 Resetting accessibility permissions..."
tccutil reset Accessibility com.cortexagent.Cortex

echo ""
echo "📋 Manual Steps Required:"
echo "1. Open System Preferences > Privacy & Security > Accessibility"
echo "2. Click the '+' button"
echo "3. Navigate to: $CORTEX_PATH"
echo "4. Select 'Cortex.app' and click 'Open'"
echo "5. Make sure the toggle is ON (blue)"
echo "6. Restart Cortex"
echo ""
echo "💡 Tip: You can copy the path above and paste it in Finder's 'Go to Folder' dialog"
echo ""

# Open System Preferences
read -p "Would you like to open System Preferences now? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
fi

echo "✅ Setup complete! Please follow the manual steps above." 