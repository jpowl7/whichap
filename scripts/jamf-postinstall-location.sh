#!/bin/bash
# WhichAP — Jamf post-install script
# Pre-authorizes WhichAP for Location Services by writing to locationd's clients.plist.
# Also launches the app as the logged-in user.
#
# This runs as root in the Jamf policy context.
# The clients.plist format is not officially documented by Apple and could change
# in future macOS releases. Tested on macOS 14 (Sonoma) and 15 (Sequoia).

BUNDLE_ID="com.grangerchurch.whichap"
APP_PATH="/Applications/WhichAP.app"
EXECUTABLE="${APP_PATH}/Contents/MacOS/WhichAP"
CLIENTS_PLIST="/var/db/locationd/clients.plist"

# The code signing designated requirement — stable across builds signed
# with the same Developer ID cert (team T6TF2VZNJL).
REQUIREMENT='identifier "com.grangerchurch.whichap" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = T6TF2VZNJL'

# --- Ensure system-wide Location Services is enabled ---
LOCATION_ENABLED=$(/usr/bin/defaults read /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd LocationServicesEnabled 2>/dev/null)
if [ "$LOCATION_ENABLED" != "1" ]; then
    echo "Enabling system-wide Location Services..."
    /usr/bin/defaults write /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd LocationServicesEnabled -bool true
fi

# --- Get the console user for launching the app ---
LOGGED_IN_USER=$(/usr/bin/stat -f%Su /dev/console)
LOGGED_IN_UID=""
if [ -n "$LOGGED_IN_USER" ] && [ "$LOGGED_IN_USER" != "root" ] && [ "$LOGGED_IN_USER" != "loginwindow" ]; then
    LOGGED_IN_UID=$(/usr/bin/id -u "$LOGGED_IN_USER")
fi

# --- Find existing locationd entry ---
PLIST_KEY=""
if [ -f "$CLIENTS_PLIST" ]; then
    PLIST_KEY=$(/usr/bin/plutil -convert xml1 -o - "$CLIENTS_PLIST" 2>/dev/null \
        | /usr/bin/grep -o "[^<]*i${BUNDLE_ID}[^<]*" \
        | head -1)
fi

# --- If no entry exists, launch the app briefly to create one ---
if [ -z "$PLIST_KEY" ] && [ -n "$LOGGED_IN_UID" ]; then
    echo "No locationd entry found. Launching WhichAP briefly to register with locationd..."
    /usr/bin/su - "$LOGGED_IN_USER" -c "/usr/bin/open '$APP_PATH'"

    # Wait for locationd to register the app (check every second, up to 15 seconds)
    for i in $(seq 1 15); do
        sleep 1
        PLIST_KEY=$(/usr/bin/plutil -convert xml1 -o - "$CLIENTS_PLIST" 2>/dev/null \
            | /usr/bin/grep -o "[^<]*i${BUNDLE_ID}[^<]*" \
            | head -1)
        if [ -n "$PLIST_KEY" ]; then
            echo "locationd registered WhichAP after ${i}s."
            break
        fi
    done

    # Kill the app so we can relaunch cleanly after authorization
    /usr/bin/pkill -x WhichAP 2>/dev/null
    sleep 1
fi

# --- Authorize the entry ---
if [ -n "$PLIST_KEY" ]; then
    echo "Found locationd entry: ${PLIST_KEY}"
    echo "Setting Authorized=true..."

    /usr/libexec/PlistBuddy -c "Set ':${PLIST_KEY}:Authorized' true" "$CLIENTS_PLIST" 2>/dev/null
    if [ $? -ne 0 ]; then
        /usr/libexec/PlistBuddy -c "Add ':${PLIST_KEY}:Authorized' bool true" "$CLIENTS_PLIST" 2>/dev/null
    fi

    /usr/libexec/PlistBuddy -c "Set ':${PLIST_KEY}:BundleId' '${BUNDLE_ID}'" "$CLIENTS_PLIST" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Set ':${PLIST_KEY}:BundlePath' '${APP_PATH}'" "$CLIENTS_PLIST" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Set ':${PLIST_KEY}:Executable' '${EXECUTABLE}'" "$CLIENTS_PLIST" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Set ':${PLIST_KEY}:Registered' true" "$CLIENTS_PLIST" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Set ':${PLIST_KEY}:Requirement' '${REQUIREMENT}'" "$CLIENTS_PLIST" 2>/dev/null

    echo "Restarting locationd to pick up changes..."
    /bin/launchctl kickstart -k system/com.apple.locationd

    echo "Location Services pre-authorized for WhichAP."
else
    echo "WARNING: Could not find or create locationd entry for ${BUNDLE_ID}."
    echo "User will need to grant Location Services manually."
fi

# --- Set default preferences ---
if [ -n "$LOGGED_IN_USER" ] && [ "$LOGGED_IN_USER" != "root" ] && [ "$LOGGED_IN_USER" != "loginwindow" ]; then
    /usr/bin/su - "$LOGGED_IN_USER" -c "/usr/bin/defaults write '$BUNDLE_ID' truncateAtColon -bool true" 2>/dev/null
fi

# --- Launch the app ---
if [ -n "$LOGGED_IN_USER" ] && [ "$LOGGED_IN_USER" != "root" ] && [ "$LOGGED_IN_USER" != "loginwindow" ]; then
    echo "Launching WhichAP as ${LOGGED_IN_USER}..."
    /usr/bin/su - "$LOGGED_IN_USER" -c "/usr/bin/open '$APP_PATH'"
fi

echo "WhichAP post-install complete."
exit 0
