#!/bin/bash
#
# Install Parachute apps to Android device while preserving app data
#
# Usage:
#   ./scripts/install-android.sh [app] [device]
#
# Arguments:
#   app     - Which app to install: 'chat', 'daily', or 'both' (default: both)
#   device  - Device identifier (optional, will prompt if multiple devices)
#
# Examples:
#   ./scripts/install-android.sh              # Install both apps, auto-select device
#   ./scripts/install-android.sh chat         # Install only chat app
#   ./scripts/install-android.sh daily        # Install only daily app
#   ./scripts/install-android.sh both daylight:35859  # Install both to specific device
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# App configurations
CHAT_DIR="$REPO_ROOT/chat"
DAILY_DIR="$REPO_ROOT/daily"
CHAT_PACKAGE="com.openparachute.chat"
DAILY_PACKAGE="com.openparachute.daily"

# Ensure ADB is in PATH
export PATH="$PATH:$HOME/Library/Android/sdk/platform-tools"

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if ADB is available
check_adb() {
    if ! command -v adb &> /dev/null; then
        log_error "ADB not found. Please install Android SDK platform-tools."
        log_info "On macOS: brew install android-platform-tools"
        exit 1
    fi
}

# Get list of connected devices
get_devices() {
    adb devices 2>/dev/null | grep -v "^List" | grep -v "^$" | awk '{print $1}'
}

# Select device (interactive if multiple)
select_device() {
    local requested_device="$1"
    local devices=($(get_devices))

    if [ ${#devices[@]} -eq 0 ]; then
        log_error "No Android devices connected."
        log_info "Connect a device via USB or use: adb connect <host>:<port>"
        exit 1
    fi

    # If a specific device was requested, verify it exists
    if [ -n "$requested_device" ]; then
        for dev in "${devices[@]}"; do
            if [ "$dev" = "$requested_device" ]; then
                echo "$requested_device"
                return 0
            fi
        done

        # Try to connect if it looks like a network address
        if [[ "$requested_device" == *":"* ]]; then
            log_info "Attempting to connect to $requested_device..."
            if adb connect "$requested_device" 2>&1 | grep -q "connected"; then
                log_success "Connected to $requested_device"
                echo "$requested_device"
                return 0
            else
                log_error "Failed to connect to $requested_device"
                exit 1
            fi
        fi

        log_error "Device '$requested_device' not found."
        log_info "Available devices: ${devices[*]}"
        exit 1
    fi

    # If only one device, use it
    if [ ${#devices[@]} -eq 1 ]; then
        echo "${devices[0]}"
        return 0
    fi

    # Multiple devices - prompt user to select
    log_warn "Multiple devices detected. Please select one:"
    echo ""
    local i=1
    for dev in "${devices[@]}"; do
        # Try to get device model for better identification
        local model=$(adb -s "$dev" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
        echo "  $i) $dev ${model:+($model)}"
        ((i++))
    done
    echo ""

    read -p "Enter number (1-${#devices[@]}): " selection

    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#devices[@]} ]; then
        echo "${devices[$((selection-1))]}"
        return 0
    else
        log_error "Invalid selection."
        exit 1
    fi
}

# Build and install an app
install_app() {
    local app_name="$1"
    local app_dir="$2"
    local package="$3"
    local device="$4"

    log_info "Building $app_name..."

    cd "$app_dir"

    # Build the release APK
    if ! flutter build apk --release 2>&1; then
        log_error "Failed to build $app_name"
        return 1
    fi

    local apk_path="$app_dir/build/app/outputs/flutter-apk/app-release.apk"

    if [ ! -f "$apk_path" ]; then
        log_error "APK not found at $apk_path"
        return 1
    fi

    log_info "Installing $app_name to $device (preserving data)..."

    # Use -r flag to replace existing app while keeping data
    # Use -d flag to allow downgrade if needed
    if adb -s "$device" install -r -d "$apk_path" 2>&1; then
        log_success "$app_name installed successfully!"
    else
        log_error "Failed to install $app_name"
        return 1
    fi

    return 0
}

# Main
main() {
    local app="${1:-both}"
    local device_arg="$2"

    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}       Parachute Android Installer                     ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""

    check_adb

    local device=$(select_device "$device_arg")
    log_success "Using device: $device"
    echo ""

    local success=true

    case "$app" in
        chat)
            install_app "Parachute Chat" "$CHAT_DIR" "$CHAT_PACKAGE" "$device" || success=false
            ;;
        daily)
            install_app "Parachute Daily" "$DAILY_DIR" "$DAILY_PACKAGE" "$device" || success=false
            ;;
        both)
            install_app "Parachute Chat" "$CHAT_DIR" "$CHAT_PACKAGE" "$device" || success=false
            echo ""
            install_app "Parachute Daily" "$DAILY_DIR" "$DAILY_PACKAGE" "$device" || success=false
            ;;
        *)
            log_error "Unknown app: $app"
            log_info "Valid options: chat, daily, both"
            exit 1
            ;;
    esac

    echo ""
    if $success; then
        echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}       Installation complete!                          ${NC}"
        echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    else
        echo -e "${RED}═══════════════════════════════════════════════════════${NC}"
        echo -e "${RED}       Installation had errors                         ${NC}"
        echo -e "${RED}═══════════════════════════════════════════════════════${NC}"
        exit 1
    fi
}

main "$@"
