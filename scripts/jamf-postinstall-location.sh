#!/bin/bash
# WhichAP — Jamf post-install script
# Launches the app as the logged-in user so SMAppService can register the
# login item on first install. Runs as root in the Jamf policy context.
#
# Note: We previously also pre-authorized Location Services by writing to
# /var/db/locationd/clients.plist + launchctl kickstart system/com.apple.locationd.
# That code was removed because SIP blocks the kickstart on production Macs,
# so locationd never re-reads the change until next boot. With proper
# entitlements signed into the bundle (fixed in 1.8.4), the macOS system
# prompt fires correctly on first launch and the user clicks Allow once.

BUNDLE_ID="com.grangerchurch.whichap"
APP_PATH="/Applications/WhichAP.app"

# --- Get the console user ---
LOGGED_IN_USER=$(/usr/bin/stat -f%Su /dev/console)

# --- Set default preferences ---
if [ -n "$LOGGED_IN_USER" ] && [ "$LOGGED_IN_USER" != "root" ] && [ "$LOGGED_IN_USER" != "loginwindow" ]; then
    /usr/bin/su - "$LOGGED_IN_USER" -c "/usr/bin/defaults write '$BUNDLE_ID' truncateAtColon -bool true" 2>/dev/null
fi

# --- Launch the app as the console user ---
if [ -n "$LOGGED_IN_USER" ] && [ "$LOGGED_IN_USER" != "root" ] && [ "$LOGGED_IN_USER" != "loginwindow" ]; then
    echo "Launching WhichAP as ${LOGGED_IN_USER}..."
    /usr/bin/su - "$LOGGED_IN_USER" -c "/usr/bin/open '$APP_PATH'"
fi

echo "WhichAP post-install complete."
exit 0
