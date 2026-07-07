#!/bin/sh
# Xcode Cloud: stamp the workflow's auto-incrementing build number into the
# project so every archive uploads a CFBundleVersion TestFlight hasn't seen.
# https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds
#
# The offset keeps new numbers above builds that were uploaded before Xcode
# Cloud was set up (highest manual upload was 3).
set -e

buildNumberOffset=10
newBuildNumber=$((CI_BUILD_NUMBER + buildNumberOffset))

cd "$CI_PRIMARY_REPOSITORY_PATH"
agvtool new-version -all "$newBuildNumber"
