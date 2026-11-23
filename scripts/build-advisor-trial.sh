#!/bin/bash
# Builds dist/GilaMonster Advisor Trial.app: the Advisor page on its own, for trying it on a real server.
# It can't start or change a server (see AdvisorTrial), and its own bundle id keeps its preferences apart from GilaMonster's.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh
trial="dist/GilaMonster Advisor Trial.app"
rm -rf "$trial"
cp -R "dist/GilaMonster.app" "$trial"
plist="$trial/Contents/Info.plist"
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleIdentifier ${GILAMONSTER_TRIAL_BUNDLE_ID:-com.extantape.gilamonster.advisortrial}" \
    -c "Set :CFBundleName GilaMonster Advisor Trial" \
    -c "Set :CFBundleDisplayName GilaMonster Advisor Trial" \
    -c "Add :GilaMonsterAdvisorTrial bool true" \
    "$plist"
codesign --force --deep --sign - "$trial"
echo "Built $trial"
