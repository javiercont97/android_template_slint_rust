#!/bin/bash
# Android Build Script
# Builds the Android APK from the Rust library

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$PROJECT_ROOT/android"
RUST_ANDROID_CRATE="slint-android"
# App name (can be overridden with --app-name)
APP_NAME="slint_app"

# Default values
BUILD_TYPE="debug"
BUILD_FORMAT="apk"
# Default to architectures with pre-built Skia binaries
# armeabi-v7a and x86 require building Skia from source (slow)
ARCHITECTURES=("arm64-v8a" "x86_64")
CLEAN_BUILD=false
SIGN_BUILD=false
KEYSTORE_PATH=""
KEYSTORE_PASSWORD=""
KEY_ALIAS=""
KEY_PASSWORD=""

# Help message
show_help() {
    echo "Android Build Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -r, --release       Build release (default: debug)"
    echo "  -b, --bundle        Build AAB instead of APK (for Play Store)"
    echo "  -a, --arch ARCH     Target architecture(s), comma-separated"
    echo "                      Options: arm64-v8a, armeabi-v7a, x86_64, x86"
    echo "                      Default: arm64-v8a,x86_64 (pre-built Skia available)"
    echo "                      Note: armeabi-v7a and x86 require building Skia from source"
    echo "  --all-arch          Build for ALL architectures (slow, builds Skia from source)"
    echo "  -c, --clean         Clean build (removes previous artifacts)"
    echo "  -s, --sign          Sign the build (requires keystore options)"
    echo "  --keystore PATH     Path to keystore file"
    echo "  --keystore-pass PW  Keystore password"
    echo "  --key-alias ALIAS   Key alias in keystore"
    echo "  --key-pass PW       Key password"
    echo "  --app-name NAME     Set the base name for output APK/AAB (default: slint_app)"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                            # Debug APK for arm64 + x86_64"
    echo "  $0 -r                         # Release APK for arm64 + x86_64"
    echo "  $0 -r -b                      # Release AAB for Play Store"
    echo "  $0 -r -a arm64-v8a            # Release APK for arm64 only"
    echo "  $0 -r --all-arch              # Release APK for ALL architectures (slow)"
    echo "  $0 -c -r -b                   # Clean release AAB build"
    echo "  $0 -r -s --keystore key.jks --keystore-pass xxx --key-alias mykey --key-pass xxx"
    echo ""
    echo "Environment Variables (alternative to command-line options):"
    echo "  KEYSTORE_PATH        Path to keystore file"
    echo "  KEYSTORE_PASSWORD    Keystore password"
    echo "  KEY_ALIAS            Key alias"
    echo "  KEY_PASSWORD         Key password"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--release)
            BUILD_TYPE="release"
            shift
            ;;
        -b|--bundle)
            BUILD_FORMAT="aab"
            shift
            ;;
        -a|--arch)
            IFS=',' read -ra ARCHITECTURES <<< "$2"
            shift 2
            ;;
        --all-arch)
            ARCHITECTURES=("arm64-v8a" "armeabi-v7a" "x86_64" "x86")
            shift
            ;;
        -c|--clean)
            CLEAN_BUILD=true
            shift
            ;;
        -s|--sign)
            SIGN_BUILD=true
            shift
            ;;
        --keystore)
            KEYSTORE_PATH="$2"
            shift 2
            ;;
        --keystore-pass)
            KEYSTORE_PASSWORD="$2"
            shift 2
            ;;
        --key-alias)
            KEY_ALIAS="$2"
            shift 2
            ;;
        --key-pass)
            KEY_PASSWORD="$2"
            shift 2
            ;;
        --app-name)
            APP_NAME="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# Load signing config from environment if not provided via CLI
if [[ "$SIGN_BUILD" == true ]]; then
    KEYSTORE_PATH="${KEYSTORE_PATH:-$KEYSTORE_PATH}"
    KEYSTORE_PASSWORD="${KEYSTORE_PASSWORD:-$KEYSTORE_PASSWORD}"
    KEY_ALIAS="${KEY_ALIAS:-$KEY_ALIAS}"
    KEY_PASSWORD="${KEY_PASSWORD:-$KEY_PASSWORD}"
fi

    echo -e "${GREEN}=== Android Build ===${NC}"
    echo "Build type: $BUILD_TYPE"
    echo "Build format: $BUILD_FORMAT"
    echo "Architectures: ${ARCHITECTURES[*]}"
    if [[ "$SIGN_BUILD" == true ]]; then
        echo "Signing: enabled"
    fi

# Check prerequisites
check_prerequisites() {
    echo -e "\n${YELLOW}Checking prerequisites...${NC}"
    
    # Check Rust
    if ! command -v rustc &> /dev/null; then
        echo -e "${RED}Error: Rust is not installed${NC}"
        exit 1
    fi
    echo "✓ Rust $(rustc --version | cut -d' ' -f2)"
    
    # Check cargo-ndk
    if ! command -v cargo-ndk &> /dev/null; then
        echo -e "${YELLOW}Installing cargo-ndk...${NC}"
        cargo install cargo-ndk
    fi
    echo "✓ cargo-ndk installed"
    
    # Check Android SDK
    if [[ -z "$ANDROID_HOME" ]]; then
        if [[ -d "$HOME/Android/Sdk" ]]; then
            export ANDROID_HOME="$HOME/Android/Sdk"
        else
            echo -e "${RED}Error: ANDROID_HOME not set and SDK not found${NC}"
            exit 1
        fi
    fi
    echo "✓ Android SDK: $ANDROID_HOME"
    
    # Check Android NDK
    if [[ -z "$ANDROID_NDK_HOME" ]]; then
        NDK_DIR=$(find "$ANDROID_HOME/ndk" -maxdepth 1 -type d 2>/dev/null | sort -V | tail -1)
        if [[ -n "$NDK_DIR" && -d "$NDK_DIR" ]]; then
            export ANDROID_NDK_HOME="$NDK_DIR"
        else
            echo -e "${RED}Error: ANDROID_NDK_HOME not set and NDK not found${NC}"
            exit 1
        fi
    fi
    echo "✓ Android NDK: $ANDROID_NDK_HOME"
    
    # Check Rust Android targets
    for arch in "${ARCHITECTURES[@]}"; do
        case $arch in
            arm64-v8a) TARGET="aarch64-linux-android" ;;
            armeabi-v7a) TARGET="armv7-linux-androideabi" ;;
            x86_64) TARGET="x86_64-linux-android" ;;
            x86) TARGET="i686-linux-android" ;;
            *)
                echo -e "${RED}Unknown architecture: $arch${NC}"
                exit 1
                ;;
        esac
        
        if ! rustup target list --installed | grep -q "$TARGET"; then
            echo -e "${YELLOW}Installing Rust target: $TARGET${NC}"
            rustup target add "$TARGET"
        fi
        echo "✓ Rust target: $TARGET"
    done
    
    # Check Android project exists
    if [[ ! -f "$ANDROID_DIR/gradlew" ]]; then
        echo -e "${RED}Error: Android project not found at $ANDROID_DIR${NC}"
        echo "Run this script from the project root or ensure the android/ directory exists"
        exit 1
    fi
    echo "✓ Android project found"
}

# Build Rust library
build_rust() {
    echo -e "\n${YELLOW}Building Rust library...${NC}"
    
    cd "$PROJECT_ROOT"
    
    export ANDROID_NDK="$ANDROID_NDK_HOME"
    export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
    export ANDROID_SDK_ROOT="$ANDROID_HOME"
    
    PLATFORM_DIR=$(find "$ANDROID_HOME/platforms" -maxdepth 1 -type d -name "android-*" 2>/dev/null | sort -V | tail -1)
    if [[ -n "$PLATFORM_DIR" ]]; then
        export ANDROID_PLATFORM="$PLATFORM_DIR"
        export ANDROID_JAR="$PLATFORM_DIR/android.jar"
        echo "Using Android platform: $PLATFORM_DIR"
        echo "Using Android JAR: $ANDROID_JAR"
    fi
    
    # Build cargo-ndk arguments
    NDK_ARGS=""
    for arch in "${ARCHITECTURES[@]}"; do
        NDK_ARGS="$NDK_ARGS -t $arch"
    done
    
    # Set output directory
    JNILIBS_DIR="$ANDROID_DIR/app/src/main/jniLibs"
    
    # Build command
    if [[ "$BUILD_TYPE" == "release" ]]; then
        cargo ndk $NDK_ARGS -o "$JNILIBS_DIR" build -p "$RUST_ANDROID_CRATE" --release
    else
        cargo ndk $NDK_ARGS -o "$JNILIBS_DIR" build -p "$RUST_ANDROID_CRATE"
    fi
    
    echo "✓ Rust library built"
    
    # Show built libraries
    echo -e "\nBuilt libraries:"
    find "$JNILIBS_DIR" -name "*.so" -exec ls -lh {} \;
}

# Build APK or AAB
build_apk() {
    echo -e "\n${YELLOW}Building ${BUILD_FORMAT^^}...${NC}"
    
    cd "$ANDROID_DIR"
    
    # Determine Gradle task
    if [[ "$BUILD_FORMAT" == "aab" ]]; then
        if [[ "$BUILD_TYPE" == "release" ]]; then
            GRADLE_TASK="bundleRelease"
            OUTPUT_PATH="$ANDROID_DIR/app/build/outputs/bundle/release/app-release.aab"
            OUTPUT_NAME="${APP_NAME}-release.aab"
        else
            GRADLE_TASK="bundleDebug"
            OUTPUT_PATH="$ANDROID_DIR/app/build/outputs/bundle/debug/app-debug.aab"
            OUTPUT_NAME="${APP_NAME}-debug.aab"
        fi
    else
        if [[ "$BUILD_TYPE" == "release" ]]; then
            GRADLE_TASK="assembleRelease"
            OUTPUT_PATH="$ANDROID_DIR/app/build/outputs/apk/release/app-release-unsigned.apk"
            OUTPUT_NAME="${APP_NAME}-release.apk"
        else
            GRADLE_TASK="assembleDebug"
            OUTPUT_PATH="$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk"
            OUTPUT_NAME="${APP_NAME}-debug.apk"
        fi
    fi
    
    ./gradlew "$GRADLE_TASK"
    
    cd "$PROJECT_ROOT"
    
    if [[ -f "$OUTPUT_PATH" ]]; then
        echo -e "\n${GREEN}✓ ${BUILD_FORMAT^^} built successfully!${NC}"
        ls -lh "$OUTPUT_PATH"
        
        # Sign if requested (release builds only)
        if [[ "$SIGN_BUILD" == true && "$BUILD_TYPE" == "release" ]]; then
            sign_build "$OUTPUT_PATH" "$OUTPUT_NAME"
        else
            # Copy to project root for easy access
            cp "$OUTPUT_PATH" "$PROJECT_ROOT/$OUTPUT_NAME"
            echo -e "\nCopied to: $PROJECT_ROOT/$OUTPUT_NAME"
        fi
    else
        echo -e "${RED}Error: ${BUILD_FORMAT^^} not found at expected location${NC}"
        exit 1
    fi
}

# Sign the build
sign_build() {
    local INPUT_PATH="$1"
    local OUTPUT_NAME="$2"
    
    echo -e "\n${YELLOW}Signing build...${NC}"
    
    # Validate signing config
    if [[ -z "$KEYSTORE_PATH" || -z "$KEYSTORE_PASSWORD" || -z "$KEY_ALIAS" || -z "$KEY_PASSWORD" ]]; then
        echo -e "${RED}Error: Signing requires all keystore options${NC}"
        echo "Required: --keystore, --keystore-pass, --key-alias, --key-pass"
        echo "Or set environment variables: KEYSTORE_PATH, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD"
        exit 1
    fi
    
    if [[ ! -f "$KEYSTORE_PATH" ]]; then
        echo -e "${RED}Error: Keystore not found at $KEYSTORE_PATH${NC}"
        exit 1
    fi
    
    if [[ "$BUILD_FORMAT" == "aab" ]]; then
        # AAB signing with jarsigner
        SIGNED_OUTPUT="$PROJECT_ROOT/${OUTPUT_NAME%.aab}-signed.aab"
        
        jarsigner -verbose \
            -sigalg SHA256withRSA \
            -digestalg SHA-256 \
            -keystore "$KEYSTORE_PATH" \
            -storepass "$KEYSTORE_PASSWORD" \
            -keypass "$KEY_PASSWORD" \
            -signedjar "$SIGNED_OUTPUT" \
            "$INPUT_PATH" \
            "$KEY_ALIAS"
        
        echo -e "${GREEN}✓ Signed AAB: $SIGNED_OUTPUT${NC}"
    else
        # APK signing with apksigner (zipalign first)
        ALIGNED_APK="$PROJECT_ROOT/${OUTPUT_NAME%.apk}-aligned.apk"
        SIGNED_APK="$PROJECT_ROOT/${OUTPUT_NAME%.apk}-signed.apk"
        
        # Zipalign for 16 KB page size (Android 15+ requirement)
        ZIPALIGN="$ANDROID_HOME/build-tools/36.1.0/zipalign"
        if [[ -x "$ZIPALIGN" ]]; then
            "$ZIPALIGN" -v -p 16384 "$INPUT_PATH" "$ALIGNED_APK"
        else
            echo -e "${YELLOW}Warning: zipalign not found at $ZIPALIGN, skipping 16 KB alignment${NC}"
            cp "$INPUT_PATH" "$ALIGNED_APK"
        fi
        
        # Sign with apksigner
        if command -v apksigner &> /dev/null; then
            apksigner sign \
                --ks "$KEYSTORE_PATH" \
                --ks-pass "pass:$KEYSTORE_PASSWORD" \
                --ks-key-alias "$KEY_ALIAS" \
                --key-pass "pass:$KEY_PASSWORD" \
                --out "$SIGNED_APK" \
                "$ALIGNED_APK"
        elif [[ -f "$ANDROID_HOME/build-tools/34.0.0/apksigner" ]]; then
            "$ANDROID_HOME/build-tools/34.0.0/apksigner" sign \
                --ks "$KEYSTORE_PATH" \
                --ks-pass "pass:$KEYSTORE_PASSWORD" \
                --ks-key-alias "$KEY_ALIAS" \
                --key-pass "pass:$KEY_PASSWORD" \
                --out "$SIGNED_APK" \
                "$ALIGNED_APK"
        else
            echo -e "${RED}Error: apksigner not found${NC}"
            exit 1
        fi
        
        # Clean up aligned APK
        rm -f "$ALIGNED_APK"
        
        echo -e "${GREEN}✓ Signed APK: $SIGNED_APK${NC}"
    fi
}

# Clean build
clean_build() {
    echo -e "\n${YELLOW}Cleaning previous build...${NC}"
    
    # Clean Rust targets
    for arch in "${ARCHITECTURES[@]}"; do
        case $arch in
            arm64-v8a) TARGET="aarch64-linux-android" ;;
            armeabi-v7a) TARGET="armv7-linux-androideabi" ;;
            x86_64) TARGET="x86_64-linux-android" ;;
            x86) TARGET="i686-linux-android" ;;
        esac
        rm -rf "$PROJECT_ROOT/target/$TARGET"
    done
    
    # Clean Android build
    rm -rf "$ANDROID_DIR/app/build"
    rm -rf "$ANDROID_DIR/app/src/main/jniLibs"
    rm -rf "$ANDROID_DIR/.gradle"
    
    echo "✓ Clean complete"
}

# Main execution
main() {
    if [[ "$CLEAN_BUILD" == true ]]; then
        clean_build
    fi
    
    check_prerequisites
    build_rust
    build_apk
    
    echo -e "\n${GREEN}=== Build Complete ===${NC}"
}

main
