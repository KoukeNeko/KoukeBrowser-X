#!/bin/bash
#
# Repeatable command-line build for kouke browser.
#
# Two things make a plain `xcodebuild` invocation fail on this machine:
#   1. xcode-select points at CommandLineTools, so DEVELOPER_DIR must be set
#      explicitly (changing the global selection would need sudo).
#   2. The YouTubeKit Swift package only resolves when building via -scheme,
#      which in turn requires an explicit -derivedDataPath.
#
# The build is signed with the real team identity rather than ad-hoc. The
# data protection keychain — and therefore iCloud sync — needs the
# application-identifier entitlement, which only a provisioning profile grants;
# an ad-hoc build gets errSecMissingEntitlement (-34018) instead. Carrying
# keychain-access-groups on an ad-hoc signature is worse than useless: the
# system kills the process on launch.
#
# Usage: scripts/build.sh [Debug|Release]

set -euo pipefail

readonly CONFIGURATION="${1:-Debug}"
readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PROJECT="${PROJECT_ROOT}/kouke browser.xcodeproj"
readonly SCHEME="kouke browser"
readonly DERIVED_DATA="${PROJECT_ROOT}/build/DerivedData"

readonly XCODE_APP="/Applications/Xcode-27.0.0-Beta.5.app"

if [[ ! -d "${XCODE_APP}" ]]; then
    echo "ERROR: Xcode not found at ${XCODE_APP}" >&2
    echo "Edit XCODE_APP in this script to point at your Xcode installation." >&2
    exit 1
fi

export DEVELOPER_DIR="${XCODE_APP}/Contents/Developer"

echo "Building '${SCHEME}' (${CONFIGURATION})..."

build_log="$(mktemp -t kouke-build)"
trap 'rm -f "${build_log}"' EXIT

if xcodebuild \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -derivedDataPath "${DERIVED_DATA}" \
    -destination 'platform=macOS,arch=arm64' \
    -allowProvisioningUpdates \
    -quiet \
    build \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    > "${build_log}" 2>&1
then
    echo "BUILD SUCCEEDED"
    echo "App: ${DERIVED_DATA}/Build/Products/${CONFIGURATION}/${SCHEME}.app"
    exit 0
fi

echo "BUILD FAILED" >&2
echo >&2
grep -E "error:" "${build_log}" | sort -u >&2 || cat "${build_log}" >&2
exit 1
