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

# --- Find the WhichAP key in clients.plist (Sonoma+ uses UUID:iBundleId: format) ---
# The key contains the bundle ID, so grep for it.
PLIST_KEY=""
if [ -f "$CLIENTS_PLIST" ]; then
    # Convert to XML, find the key containing our bundle ID
    PLIST_KEY=$(/usr/bin/plutil -convert xml1 -o - "$CLIENTS_PLIST" 2>/dev/null \
        | /usr/bin/grep -o "[^<]*i${BUNDLE_ID}[^<]*" \
        | head -1)
fi

if [ -z "$PLIST_KEY" ]; then
    echo "No existing locationd entry found for ${BUNDLE_ID}."
    echo "The app will register itself on first launch and the user will see the prompt."
    echo "If this is a Jamf-managed machine, consider running this script after first launch."
else
    echo "Found locationd entry: ${PLIST_KEY}"
    echo "Setting Authorized=true..."

    # Use PlistBuddy to set Authorized on the existing entry
    /usr/libexec/PlistBuddy -c "Set ':${PLIST_KEY}:Authorized' true" "$CLIENTS_PLIST" 2>/dev/null
    if [ $? -ne 0 ]; then
        # Key doesn't exist yet — add it
        /usr/libexec/PlistBuddy -c "Add ':${PLIST_KEY}:Authorized' bool true" "$CLIENTS_PLIST" 2>/dev/null
    fi

    # Ensure other required fields are set
    /usr/libexec/PlistBuddy -c "Set ':${PLIST_KEY}:BundleId' '${BUNDLE_ID}'" "$CLIENTS_PLIST" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Set ':${PLIST_KEY}:BundlePath' '${APP_PATH}'" "$CLIENTS_PLIST" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Set ':${PLIST_KEY}:Executable' '${EXECUTABLE}'" "$CLIENTS_PLIST" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Set ':${PLIST_KEY}:Registered' true" "$CLIENTS_PLIST" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Set ':${PLIST_KEY}:Requirement' '${REQUIREMENT}'" "$CLIENTS_PLIST" 2>/dev/null

    echo "Restarting locationd to pick up changes..."
    /bin/launchctl kickstart -k system/com.apple.locationd

    echo "Location Services pre-authorized for WhichAP."
fi

# --- Set default preferences and launch ---
# stat -f%Su /dev/console is the most reliable way to get the console user
# from a root Jamf policy context (per snelson.us/2022/07)
LOGGED_IN_USER=$(/usr/bin/stat -f%Su /dev/console)
if [ -n "$LOGGED_IN_USER" ] && [ "$LOGGED_IN_USER" != "root" ] && [ "$LOGGED_IN_USER" != "loginwindow" ]; then
    # Set truncateAtColon default
    /usr/bin/su - "$LOGGED_IN_USER" -c "/usr/bin/defaults write '$BUNDLE_ID' truncateAtColon -bool true" 2>/dev/null

    # Launch the app as the logged-in user
    echo "Launching WhichAP as ${LOGGED_IN_USER}..."
    /usr/bin/su - "$LOGGED_IN_USER" -c "/usr/bin/open '$APP_PATH'"
fi

echo "WhichAP post-install complete."
exit 0
