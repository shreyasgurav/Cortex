#!/bin/bash

echo "🔧 Building Cortex App for Production Testing"
echo "=============================================="

# Kill any existing Cortex processes
echo "🔄 Stopping any running Cortex processes..."
killall Cortex 2>/dev/null || true

# Build the app
echo "🔨 Building Cortex app..."
xcodebuild -project Cortex.xcodeproj -scheme Cortex -configuration Release build

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    
    # Find the built app
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "Cortex.app" -type d | head -1)
    
    if [ -n "$APP_PATH" ]; then
        echo "📱 Found app at: $APP_PATH"
        
        # Copy to Desktop for easy access
        DESKTOP_PATH="$HOME/Desktop/Cortex.app"
        echo "📋 Copying to Desktop..."
        rm -rf "$DESKTOP_PATH" 2>/dev/null || true
        cp -R "$APP_PATH" "$DESKTOP_PATH"
        
        echo ""
        echo "🎉 Build Complete!"
        echo "=================="
        echo "📱 App location: $DESKTOP_PATH"
        echo ""
        echo "🔧 Next Steps:"
        echo "1. Double-click Cortex.app on Desktop to launch"
        echo "2. When prompted, grant Accessibility permissions"
        echo "3. Test memory insertion in any text field"
        echo ""
        echo "🔒 If permissions don't work:"
        echo "   - Go to System Settings > Privacy & Security > Accessibility"
        echo "   - Remove Cortex if listed"
        echo "   - Click '+' and manually add Cortex.app from Desktop"
        echo ""
        
        # Open the app
        echo "🚀 Launching Cortex..."
        open "$DESKTOP_PATH"
        
    else
        echo "❌ Could not find built app"
        exit 1
    fi
else
    echo "❌ Build failed!"
    exit 1
fi 