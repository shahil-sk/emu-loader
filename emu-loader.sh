#!/bin/bash
set -e  # Exit script on error

# === Configuration ===
GMTOOL="/home/sk/Victims/genymotion/gmtool"
FRIDA_PATH="/data/local/tmp/frida-server"

# === Dependency Setup ===
setup_depends() {
    echo "[+] Ensuring required dependencies are installed..."

    if ! command -v adb &>/dev/null; then
        echo "[!] Installing adb..."
        sudo apt install -y adb
    else
        echo "[✔] adb already installed."
    fi

    if ! command -v pipx &>/dev/null; then
        echo "[!] Installing pipx..."
        sudo apt install -y pipx
    else
        echo "[✔] pipx already installed."
    fi

    if ! pipx list | grep -q frida-tools; then
        echo "[!] Installing frida-tools..."
        pipx install frida-tools > /dev/null
    else
        echo "[✔] frida-tools already installed."
    fi
}

check_dependencies() {
    echo "[+] Verifying essential CLI tools..."
    local missing=()
    for cmd in adb wget xz pipx; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if (( ${#missing[@]} )); then
        echo "[X] Missing required tools: ${missing[*]}"
        echo "[!] Run setup_depends to install them."
        exit 1
    fi
}

# === Genymotion AVD Handling ===
list_avds() {
    echo "[+] Available Genymotion VMs:"
    if [ -x "$GMTOOL" ]; then
        $GMTOOL admin list vms > /dev/null
    else
        echo "[X] gmtool not found or not executable: $GMTOOL"
        exit 1
    fi
}

select_avd() {
    echo ""
    echo "[+] Select an AVD to launch:"

    # Extract only the lines with VM entries, skipping headers
    local avds=()
    while IFS= read -r line; do
        name=$(echo "$line" | awk -F '|' '{print $4}' | xargs)
        if [[ -n "$name" && "$name" != "Name" ]]; then
            avds+=("$name")
        fi
    done < <($GMTOOL admin list vms | tail -n +3)

    if [ "${#avds[@]}" -eq 0 ]; then
        echo "[X] No AVDs found. Please create one in Genymotion first."
        exit 1
    fi

    select avd in "${avds[@]}"; do
        if [[ -n "$avd" ]]; then
            AVD="$avd"
            echo "[✔] Selected AVD: $AVD"
            break
        else
            echo "[X] Invalid selection. Try again."
        fi
    done
}


# === Emulator Setup ===
start_genymotion() {
    echo "[!] Booting Genymotion AVD: $AVD..."
    $GMTOOL admin start "$AVD"
    sleep 2
    echo "[✔] Emulator started."
}

enable_adb() {
    echo "[!] Starting ADB server..."
    adb start-server
    sleep 1
}

set_magisk_root() {
    echo "[!] Enabling root access on emulator..."
    for i in {1..4}; do
        adb shell setprop persist.sys.root_access 3
    done
    echo "[✔] Root access enabled."
}

set_proxy() {
    echo "[!] Setting proxy to localhost:8080 for BurpSuite..."
    adb shell settings put global http_proxy localhost:3333
    adb reverse tcp:3333 tcp:8080 > /dev/null || {
        echo "[X] Failed to reverse proxy."
        exit 1
    }
    echo "[✔] Proxy set."
}

# === Frida Server Setup ===
detect_device() {
    echo "[+] Checking for connected device..."
    if ! adb get-state 1>/dev/null 2>&1; then
        echo "[X] No device detected. Connect an emulator or device with ADB enabled."
        exit 1
    fi
}

detect_architecture() {
    echo "[+] Detecting device architecture..."
    ARCH=$(adb shell getprop ro.product.cpu.abi | tr -d '\r')

    case "$ARCH" in
        arm64-v8a)  FRIDA_BINARY="frida-server-${FRIDA_VERSION}-android-arm64" ;;
        armeabi-v7a) FRIDA_BINARY="frida-server-${FRIDA_VERSION}-android-arm" ;;
        x86)        FRIDA_BINARY="frida-server-${FRIDA_VERSION}-android-x86" ;;
        x86_64)     FRIDA_BINARY="frida-server-${FRIDA_VERSION}-android-x86_64" ;;
        *)          echo "[X] Unsupported architecture: $ARCH"; exit 1 ;;
    esac
    echo "[✔] Detected architecture: $ARCH"
}

download_frida() {
    if [ -f "$FRIDA_BINARY" ]; then
        echo "[✔] Local Frida binary already exists: $FRIDA_BINARY"
    else
        echo "[+] Downloading Frida-Server ($ARCH)..."
        wget -q --show-progress "${FRIDA_DOWNLOAD_URL}/${FRIDA_BINARY}.xz"
        xz -d "${FRIDA_BINARY}.xz"
        chmod +x "$FRIDA_BINARY"
    fi
}

push_frida() {
    echo "[+] Checking Frida-Server version on device..."
    local update_needed=true
    if adb shell "[ -f $FRIDA_PATH ]"; then
        DEVICE_FRIDA_VERSION=$(adb shell "$FRIDA_PATH --version" 2>/dev/null | tr -d '\r')
        if [[ "$DEVICE_FRIDA_VERSION" == "$FRIDA_VERSION" ]]; then
            echo "[✔] Frida-Server is already up-to-date (Version: $DEVICE_FRIDA_VERSION)"
            update_needed=false
        else
            echo "[!] Frida version mismatch: device has $DEVICE_FRIDA_VERSION, expected $FRIDA_VERSION"
        fi
    fi

    if [[ "$update_needed" == true ]]; then
        echo "[+] Updating Frida-Server..."
        adb shell rm -f "$FRIDA_PATH"
        adb push "$FRIDA_BINARY" "$FRIDA_PATH"
        adb shell chmod 777 "$FRIDA_PATH"
        echo "[✔] Frida-Server pushed and permissions set."
    fi
}

start_frida() {
    echo "[+] Killing any existing Frida-Server..."
    adb shell pkill -f frida-server || true
    echo "[+] Starting Frida-Server..."
    adb shell "$FRIDA_PATH" &
    sleep 2
}

check_frida() {
    echo "[+] Verifying Frida-Server is running..."
    for i in {1..5}; do
        if adb shell pgrep -f frida-server > /dev/null; then
            echo "[✔] Frida-Server is running!"
            return
        fi
        echo "[!] Waiting for Frida-Server... (Attempt $i/5)"
        sleep 2
    done
    echo "[X] Frida-Server failed to start."
    exit 1
}

# === Main Script Execution ===
FRIDA_VERSION=$(frida --version)
FRIDA_DOWNLOAD_URL="https://github.com/frida/frida/releases/download/${FRIDA_VERSION}"

setup_depends
check_dependencies
list_avds
select_avd
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

echo "[✔] Setup complete — Frida-Server is running on the selected AVD!"
