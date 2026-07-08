#!/bin/sh
# Xcode Cloud: stamp the workflow's auto-incrementing build number into the
# project so every archive uploads a CFBundleVersion TestFlight hasn't seen.
# https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds
#
# The offset keeps new numbers above every build uploaded before Xcode Cloud
# was set up (App Store Connect already has a build numbered above 24).
set -e

buildNumberOffset=1000
newBuildNumber=$((${CI_BUILD_NUMBER:?not set} + buildNumberOffset))

cd "$CI_PRIMARY_REPOSITORY_PATH"
agvtool new-version -all "$newBuildNumber"

# Belt and suspenders: write CFBundleVersion directly too, and show the result
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $newBuildNumber" ParkTrac/Info.plist || true
echo "ci_post_clone: build number set to $newBuildNumber (CI_BUILD_NUMBER=$CI_BUILD_NUMBER)"
grep -A1 CFBundleVersion ParkTrac/Info.plist
