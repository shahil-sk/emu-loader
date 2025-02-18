#!/bin/bash
set -e  # Exit script on error

setup_frida()
{
    echo "[!] Checking adb install?"
    sudo apt install adb 
    echo "[!] Checking pipx install?"
    sudo apt install pipx 
    echo "[!] Checking Frida-tools install?"
    pipx install frida-tools > /dev/null
}

# Add the path to 'gmtool' according to your genymotion installation
GMTOOL="#ADD PATH TO YOUR GENYMOTION GMTOOL HERE"
AVD="#NAME OF YOUR EMULATOR"

FRIDA_VERSION=$(frida --version)
FRIDA_DOWNLOAD_URL="https://github.com/frida/frida/releases/download/${FRIDA_VERSION}"
FRIDA_PATH="/data/local/tmp/frida-server"

start_genymotion() {
    echo "[!] Booting Genymotion..."
    $GMTOOL admin start $AVD
    sleep 2
    echo "[✔] Emulator Started"
}

enable_adb() {
    echo "[!] Ensuring ADB is Running..."
    adb start-server
    sleep 1
}

set_magisk_root() {
    echo "[!] Enabling Genymotion Root Access..."
    sleep 1
    adb shell setprop persist.sys.root_access 3
    echo "[✔] Root Granted"
}

set_proxy() {
    echo "[!] Setting Proxy to BurpSuite (localhost:8080)..."
    adb shell settings put global http_proxy localhost:3333
    adb reverse tcp:3333 tcp:8080 > /dev/null || { echo "[X] Failed to set proxy"; exit 1; }
    echo "[✔] Proxy Set Successfully"
}

check_dependencies() {
    echo "[+] Checking for required dependencies..."
    for cmd in adb wget xz; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "[X] Error: $cmd is not installed. Install it first."
            exit 1
        fi
    done
}

detect_device() {
    echo "[+] Checking for connected device..."
    if ! adb get-state 1>/dev/null 2>&1; then
        echo "[X] No device found. Connect your Android device and enable ADB."
        exit 1
    fi
}

detect_architecture() {
    echo "[+] Detecting device architecture..."
    ARCH=$(adb shell getprop ro.product.cpu.abi | tr -d '\r')
    case $ARCH in
        arm64-v8a)  FRIDA_BINARY="frida-server-${FRIDA_VERSION}-android-arm64" ;;
        armeabi-v7a) FRIDA_BINARY="frida-server-${FRIDA_VERSION}-android-arm" ;;
        x86)        FRIDA_BINARY="frida-server-${FRIDA_VERSION}-android-x86" ;;
        x86_64)     FRIDA_BINARY="frida-server-${FRIDA_VERSION}-android-x86_64" ;;
        *)          echo "[X] Unsupported architecture: $ARCH"; exit 1 ;;
    esac
}

download_frida() {
    if [ -f "$FRIDA_BINARY" ]; then
        echo "[✔] Frida-Server binary already exists: $FRIDA_BINARY"
    else
        echo "[+] Downloading Frida-Server ($ARCH)..."
        wget -q --show-progress "${FRIDA_DOWNLOAD_URL}/${FRIDA_BINARY}.xz"
        xz -d "${FRIDA_BINARY}.xz"
        chmod +x "$FRIDA_BINARY"
    fi
}

push_frida() {
    echo "[+] Checking for existing Frida-Server on device..."
    if adb shell "[ -f $FRIDA_PATH ]"; then
        DEVICE_FRIDA_VERSION=$(adb shell "$FRIDA_PATH --version" 2>/dev/null | tr -d '\r')

        if [ "$DEVICE_FRIDA_VERSION" == "$FRIDA_VERSION" ]; then
            echo "[✔] Frida-Server is already up-to-date (Version: $DEVICE_FRIDA_VERSION)"
            return
        else
            echo "[!] Outdated Frida-Server detected (Device: $DEVICE_FRIDA_VERSION, Script: $FRIDA_VERSION)"
            echo "[+] Removing old Frida-Server..."
            adb shell rm -f "$FRIDA_PATH"
        fi
    fi

    echo "[+] Pushing new Frida-Server (Version: $FRIDA_VERSION) to device..."
    adb push "$FRIDA_BINARY" "$FRIDA_PATH"
    adb shell chmod 777 "$FRIDA_PATH"
    echo "[✔] Frida-Server updated successfully!"
}


start_frida() {
    echo "[+] Killing any existing Frida-Server instances..."
    adb shell pkill -f frida-server || true
    echo "[+] Starting Frida-Server..."
    adb shell "$FRIDA_PATH" &
    sleep 2
}

check_frida() {
    echo "[+] Checking if Frida-Server is running..."
    for i in {1..5}; do
        if adb shell pgrep -f frida-server > /dev/null; then
            echo "[✔] Frida-Server is running successfully!"
            return
        fi
        echo "[!] Waiting for Frida-Server to start... (Attempt $i/5)"
        sleep 2
    done
    echo "[X] Failed to start Frida-Server after multiple attempts."
    exit 1
}

# Main Execution Flow
setup_frida
check_dependencies
start_genymotion
enable_adb
set_magisk_root
set_proxy
detect_device
detect_architecture
download_frida
adb root
push_frida
start_frida
check_frida

echo "[✔] DONE"
