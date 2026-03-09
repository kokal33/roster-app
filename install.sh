#!/bin/bash

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo ""
echo "========================================"
echo "  ROSTER - Tablet Update Script"
echo "========================================"
echo ""

# Step 1: Get ADB
echo "[1/7] Setting up ADB..."
if command -v adb &> /dev/null; then
    echo -e "${GREEN}[OK] ADB already installed${NC}"
else
    echo "Installing ADB via Homebrew..."
    if ! command -v brew &> /dev/null; then
        echo "Installing Homebrew first..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
    fi
    brew install --cask android-platform-tools
    echo -e "${GREEN}[OK] ADB installed${NC}"
fi

# Step 2: Check tablet is connected
echo ""
echo "[2/7] Checking tablet connection..."
echo -e "${YELLOW}Make sure the tablet is connected via USB and USB debugging is ON${NC}"
echo ""
read -p "Press ENTER when ready..."

if ! adb devices 2>/dev/null | grep -w "device" > /dev/null; then
    echo -e "${RED}No tablet detected! Check USB cable and USB debugging.${NC}"
    exit 1
fi
DEVICE_ID=$(adb devices | grep -w "device" | head -1 | awk '{print $1}')
echo -e "${GREEN}[OK] Tablet connected: $DEVICE_ID${NC}"

# Step 3: Check root access
echo ""
echo "[3/7] Checking root access..."
if ! adb shell su 0 id 2>/dev/null | grep -q "uid=0"; then
    echo -e "${RED}ERROR: Tablet is not rooted!${NC}"
    echo "The old app is locked as device owner."
    echo "Without root, the only option is a FACTORY RESET."
    echo ""
    echo "To factory reset: hold Power + Volume Down for 10 seconds,"
    echo "then select Wipe Data/Factory Reset."
    echo "After reset, skip all Google accounts, then re-run this script."
    exit 1
fi
echo -e "${GREEN}[OK] Root access available${NC}"

# Step 4: Remove device owner + disable old app BEFORE reboot
echo ""
echo "[4/7] Removing device owner lock..."
adb shell su 0 rm /data/system/device_owner_2.xml 2>/dev/null || true
adb shell su 0 rm /data/system/device_policies.xml 2>/dev/null || true

# Force stop and disable the old app so it cant re-pin after reboot
adb shell su 0 am force-stop com.nfccheckin 2>/dev/null || true
adb shell su 0 pm disable com.nfccheckin 2>/dev/null || true

echo -e "${GREEN}[OK] Device lock removed, old app disabled${NC}"

# Step 5: Reboot and wait
echo ""
echo "[5/7] Rebooting tablet..."
adb reboot
echo "Waiting for tablet to restart (about 60 seconds)..."
sleep 15
adb wait-for-device
sleep 20
# Wait until boot is fully complete
while [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; do
    sleep 3
done
sleep 5
echo -e "${GREEN}[OK] Tablet rebooted${NC}"

# Step 6: Uninstall old app
echo ""
echo "[6/7] Uninstalling old app..."
adb shell pm enable com.nfccheckin 2>/dev/null || true
adb uninstall com.nfccheckin 2>/dev/null || true
echo -e "${GREEN}[OK] Old app removed${NC}"

# Step 7: Download and install new app
echo ""
echo "[7/7] Downloading and installing latest ROSTER app..."
DOWNLOAD_URL=$(curl -s https://api.github.com/repos/kokal33/roster-app/releases/latest \
    | grep "browser_download_url.*\.apk" \
    | head -1 \
    | cut -d '"' -f 4)

if [ -z "$DOWNLOAD_URL" ]; then
    echo -e "${RED}Could not find APK download!${NC}"
    exit 1
fi

TEMP_APK="/tmp/roster-app.apk"
curl -L -# -o "$TEMP_APK" "$DOWNLOAD_URL"

adb install "$TEMP_APK"
if [ $? -ne 0 ]; then
    echo -e "${RED}Install failed!${NC}"
    exit 1
fi
rm -f "$TEMP_APK"

# Launch
adb shell am start -n com.nfccheckin/.SetupActivity

echo ""
echo "========================================"
echo -e "${GREEN}  DONE! ROSTER is installed.${NC}"
echo "========================================"
echo ""
echo "The tablet shows the setup screen."
echo "Scan the QR code from the admin panel to pair it."
echo ""
