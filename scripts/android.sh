#!/bin/bash
# Build, install, run, and debug the Android app

set -e

# Prefer Windows adb.exe and emulator.exe if available (WSL environment)
# User has to set WIN_ANDROID_SDK in .bashrc or similar
# For example: export WIN_ANDROID_SDK="/mnt/c/Users/<User>/AppData/Local/Android/Sdk"
if [[ -x "$WIN_ANDROID_SDK/platform-tools/adb.exe" ]]; then
    ADB="$WIN_ANDROID_SDK/platform-tools/adb.exe"
else
    ADB="adb"
fi
if [[ -x "$WIN_ANDROID_SDK/emulator/emulator.exe" ]]; then
    EMULATOR="$WIN_ANDROID_SDK/emulator/emulator.exe"
else
    EMULATOR="emulator"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
#######################################################
APP_NAME="slint_app" # Change this to your app name
#######################################################
ANDROID_DIR="$PROJECT_ROOT/android"
PACKAGE_NAME="com.${APP_NAME}.app"
ACTIVITY_NAME="android.app.NativeActivity"

# APK paths
DEBUG_APK="$PROJECT_ROOT/${APP_NAME}-debug.apk"
RELEASE_APK="$PROJECT_ROOT/${APP_NAME}-release.apk"

show_help() {
    echo "Android Tooling"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  build [--release]   Build the Android APK (default: debug, arm64 only)"
    echo "  install             Install the APK on connected device"
    echo "  run                 Build, install, and launch app on device"
    echo "  launch              Launch already installed app"
    echo "  uninstall           Uninstall app from device"
    echo "  log                 Show filtered logcat for Rust/app output"
    echo "  logcat              Show full logcat (unfiltered)"
    echo "  devices             List connected devices/emulators"
    echo "  emulator [name]     Start an emulator (lists available if no name)"
    echo "  clean               Clean build artifacts"
    echo "  help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 build              # Debug build for arm64"
    echo "  $0 build --release    # Release build for arm64"
    echo "  $0 run                # Build, install, and launch (debug)"
    echo "  $0 run --release      # Build, install, and launch (release)"
    echo "  $0 log                # Watch app logs"
    echo "  $0 emulator           # List available emulators"
    echo "  $0 emulator Pixel_6   # Start Pixel_6 emulator"
}


# Check if adb is available (using $ADB)
check_adb() {
    if ! command -v "$ADB" &> /dev/null; then
        echo -e "${RED}Error: adb not found. Install Android SDK platform-tools.${NC}"
        exit 1
    fi
}

# Check if emulator is available (using $EMULATOR)
check_emulator() {
    if ! command -v "$EMULATOR" &> /dev/null; then
        echo -e "${RED}Error: emulator not found. Install Android SDK emulator.${NC}"
        exit 1
    fi
}

# Check if device is connected
check_device() {
    check_adb
    DEVICES=$("$ADB" devices | grep -v "List" | grep -v "^$" | wc -l)
    if [[ "$DEVICES" -eq 0 ]]; then
        echo -e "${RED}Error: No Android device connected.${NC}"
        echo "Connect a device via USB or start an emulator:"
        echo "  $0 emulator"
        exit 1
    fi
}

# Build command
cmd_build() {
    local BUILD_TYPE="debug"
    
    # Parse build options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --release|-r)
                BUILD_TYPE="release"
                shift
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                exit 1
                ;;
        esac
    done
    
    echo -e "${GREEN}=== Building Android APK ($BUILD_TYPE) ===${NC}"
    
    # Use arm64 only for fast local builds
    if [[ "$BUILD_TYPE" == "release" ]]; then
        "$PROJECT_ROOT/scripts/build-android.sh" -r
        # "$PROJECT_ROOT/scripts/build-android.sh" -r -a arm64-v8a
    else
        "$PROJECT_ROOT/scripts/build-android.sh"
        # "$PROJECT_ROOT/scripts/build-android.sh" -a arm64-v8a
    fi
}

# Install command
cmd_install() {
    local APK_PATH="$DEBUG_APK"
    
    # Check for release flag
    if [[ "$1" == "--release" || "$1" == "-r" ]]; then
        APK_PATH="$RELEASE_APK"
    fi
    
    if [[ ! -f "$APK_PATH" ]]; then
        echo -e "${RED}Error: APK not found at $APK_PATH${NC}"
        echo "Run '$0 build' first"
        exit 1
    fi
    
    check_device
    
    # echo -e "${YELLOW}Uninstalling previous version...${NC}"
    # "$ADB" uninstall "$PACKAGE_NAME" 2>/dev/null || true
    echo -e "${YELLOW}Installing APK...${NC}"
    "$ADB" install -r "$APK_PATH"
    echo -e "${GREEN}✓ Installed successfully${NC}"
}

# Launch command
cmd_launch() {
    check_device
    
    echo -e "${YELLOW}Launching app...${NC}"
    "$ADB" shell am start -n "$PACKAGE_NAME/$ACTIVITY_NAME"
    echo -e "${GREEN}✓ App launched${NC}"
}

# Run command (build + install + launch)
cmd_run() {
    local BUILD_OPTS=""
    
    if [[ "$1" == "--release" || "$1" == "-r" ]]; then
        BUILD_OPTS="--release"
    fi
    
    cmd_build $BUILD_OPTS
    cmd_install $BUILD_OPTS
    cmd_launch
}

# Uninstall command
cmd_uninstall() {
    check_device
    
    echo -e "${YELLOW}Uninstalling app...${NC}"
    "$ADB" uninstall "$PACKAGE_NAME"
    echo -e "${GREEN}✓ App uninstalled${NC}"
}

# Log command (filtered)
cmd_log() {
    check_device
    
    echo -e "${GREEN}=== Showing Rust/App logs (Ctrl+C to stop) ===${NC}"
    echo ""
    
    # Filter for Rust stdout/stderr and common app tags
    "$ADB" logcat -c  # Clear existing logs
    "$ADB" logcat | grep -E "(RustStdoutStderr|NativeActivity|slint)"
}

# Full logcat command
cmd_logcat() {
    check_device
    
    echo -e "${GREEN}=== Full logcat (Ctrl+C to stop) ===${NC}"
    "$ADB" logcat
}

# Devices command
cmd_devices() {
    check_adb
    
    echo -e "${GREEN}=== Connected Devices ===${NC}"
    "$ADB" devices -l
}

# Emulator command
cmd_emulator() {
    local EMU_NAME="$1"
    check_emulator
    if [[ -z "$EMU_NAME" ]]; then
        echo -e "${GREEN}=== Available Emulators ===${NC}"
        "$EMULATOR" -list-avds
        echo ""
        echo "Start an emulator with: $0 emulator <name>"
    else
        echo -e "${YELLOW}Starting emulator: $EMU_NAME${NC}"
        "$EMULATOR" -avd "$EMU_NAME" > /dev/null 2>&1 &
        echo "Waiting for device to boot..."
        "$ADB" wait-for-device
        # Wait for boot to complete
        while [[ "$($ADB shell getprop sys.boot_completed 2>/dev/null)" != "1" ]]; do
            sleep 1
        done
        echo -e "${GREEN}✓ Emulator ready${NC}"
    fi
}

# Clean command
cmd_clean() {
    echo -e "${YELLOW}Cleaning build artifacts...${NC}"
    
    # Remove APKs from project root
    rm -f "$PROJECT_ROOT/${APP_NAME}-debug.apk"
    rm -f "$PROJECT_ROOT/${APP_NAME}-release.apk"
    rm -f "$PROJECT_ROOT/${APP_NAME}-debug.aab"
    rm -f "$PROJECT_ROOT/${APP_NAME}-release.aab"
    
    # Clean Android build
    rm -rf "$ANDROID_DIR/app/build"
    rm -rf "$ANDROID_DIR/app/src/main/jniLibs"
    rm -rf "$ANDROID_DIR/.gradle"
    
    # Clean Rust Android targets
    rm -rf "$PROJECT_ROOT/target/aarch64-linux-android"
    rm -rf "$PROJECT_ROOT/target/x86_64-linux-android"
    
    echo -e "${GREEN}✓ Clean complete${NC}"
}

# Main
case "${1:-help}" in
    build)
        shift
        cmd_build "$@"
        ;;
    install)
        shift
        cmd_install "$@"
        ;;
    run)
        shift
        cmd_run "$@"
        ;;
    launch)
        cmd_launch
        ;;
    uninstall|clean-device)
        cmd_uninstall
        ;;
    log|debug)
        cmd_log
        ;;
    logcat)
        cmd_logcat
        ;;
    devices)
        cmd_devices
        ;;
    emulator|emu)
        shift
        cmd_emulator "$@"
        ;;
    clean)
        cmd_clean
        ;;
    help|-h|--help)
        show_help
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo ""
        show_help
        exit 1
        ;;
esac
