#!/bin/bash
#
# Produces a signed, notarized and stapled DMG of Ciruvo, plus a notarized zip
# for the GitHub release.
#
# Unlike a plain signed build, this one goes through archive + exportArchive.
# Signing the app directly with a Developer ID identity fails here: the app
# carries keychain-access-groups, a restricted entitlement that only a
# provisioning profile can authorise, and a direct build has no profile to
# embed. Export with method "developer-id" fetches one and embeds it.
#
# Credentials are read from scripts/env (git-ignored), which must define:
#   APPLE_ID            Apple ID used for notarisation
#   APPLE_TEAM_ID       10-character team identifier
#   APPLE_APP_PASSWORD  app-specific password from appleid.apple.com
#   SIGN_IDENTITY       "Developer ID Application: … (TEAMID)"
#
# Usage: scripts/build-dmg-signed.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly PROJECT_ROOT
readonly PROJECT="${PROJECT_ROOT}/kouke browser.xcodeproj"

# The Xcode target and scheme still carry the old name; only the product is
# Ciruvo. Renaming the target would rename the Swift module with it, which
# stops the app creating any window at all.
readonly SCHEME="kouke browser"
readonly APP_NAME="Ciruvo"

readonly XCODE_APP="/Applications/Xcode-27.0.0-Beta.5.app"
readonly BUILD_DIR="${PROJECT_ROOT}/build/dist"
readonly ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
readonly EXPORT_DIR="${BUILD_DIR}/export"
readonly APP_PATH="${EXPORT_DIR}/${APP_NAME}.app"

load_credentials() {
    local env_file
    for env_file in "${SCRIPT_DIR}/env" "${SCRIPT_DIR}/.env" "${PROJECT_ROOT}/.env"; do
        if [[ -f "${env_file}" ]]; then
            echo "Loading credentials from ${env_file}"
            set -a
            # shellcheck source=/dev/null
            source "${env_file}"
            set +a
            return 0
        fi
    done

    echo "ERROR: no credentials file found (looked for scripts/env)" >&2
    exit 1
}

require_credentials() {
    local missing=()
    local name
    for name in APPLE_ID APPLE_TEAM_ID APPLE_APP_PASSWORD SIGN_IDENTITY; do
        # Names only — a value must never reach the log.
        [[ -n "${!name:-}" ]] || missing+=("${name}")
    done

    if (( ${#missing[@]} > 0 )); then
        echo "ERROR: missing in credentials file: ${missing[*]}" >&2
        exit 1
    fi
}

require_xcode() {
    if [[ ! -d "${XCODE_APP}" ]]; then
        echo "ERROR: Xcode not found at ${XCODE_APP}" >&2
        echo "Edit XCODE_APP in this script to point at your Xcode installation." >&2
        exit 1
    fi
    export DEVELOPER_DIR="${XCODE_APP}/Contents/Developer"
}

archive_release() {
    echo "Archiving ${SCHEME} (Release)..."
    rm -rf "${ARCHIVE_PATH}" "${EXPORT_DIR}"
    mkdir -p "${BUILD_DIR}"

    xcodebuild \
        -project "${PROJECT}" \
        -scheme "${SCHEME}" \
        -configuration Release \
        -archivePath "${ARCHIVE_PATH}" \
        -destination 'platform=macOS,arch=arm64' \
        -allowProvisioningUpdates \
        -quiet \
        archive \
        ARCHS=arm64 \
        ONLY_ACTIVE_ARCH=NO
}

export_developer_id() {
    local options_plist="${BUILD_DIR}/ExportOptions.plist"

    cat > "${options_plist}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>teamID</key>
	<string>${APPLE_TEAM_ID}</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>destination</key>
	<string>export</string>
</dict>
</plist>
EOF

    echo "Exporting with Developer ID..."
    xcodebuild -exportArchive \
        -archivePath "${ARCHIVE_PATH}" \
        -exportOptionsPlist "${options_plist}" \
        -exportPath "${EXPORT_DIR}" \
        -allowProvisioningUpdates

    if [[ ! -d "${APP_PATH}" ]]; then
        echo "ERROR: export produced no ${APP_NAME}.app" >&2
        exit 1
    fi
}

read_metadata() {
    local info_plist="${APP_PATH}/Contents/Info.plist"
    VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${info_plist}")"
    BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "${info_plist}")"
    DMG_PATH="${BUILD_DIR}/${APP_NAME}-v${VERSION}.dmg"
    ZIP_PATH="${BUILD_DIR}/${APP_NAME}-v${VERSION}.zip"

    echo "Version:   ${VERSION}"
    echo "Bundle ID: ${BUNDLE_ID}"
}

verify_signature() {
    echo "Verifying signature..."
    codesign --verify --deep --strict "${APP_PATH}"

    # Captured rather than piped: the flags are matched below, and a check that
    # cannot show what it saw when it fails is worse than no check at all.
    local details
    details="$(codesign --display --verbose=2 "${APP_PATH}" 2>&1)"

    # Notarisation rejects anything without the hardened runtime, and learning
    # that from the service costs a round trip. The flag travels with others,
    # so the match is on the flags line rather than one exact value.
    case "${details}" in
        *flags=*runtime*) ;;
        *)
            echo "ERROR: hardened runtime is not enabled; notarisation would fail" >&2
            echo "${details}" >&2
            exit 1
            ;;
    esac
}

create_dmg() {
    local staging="${BUILD_DIR}/dmg-staging"

    echo "Creating DMG..."
    rm -rf "${staging}" "${DMG_PATH}"
    mkdir -p "${staging}"
    cp -R "${APP_PATH}" "${staging}/"
    ln -s /Applications "${staging}/Applications"

    hdiutil create -volname "${APP_NAME}" \
        -srcfolder "${staging}" \
        -ov -format UDZO \
        -quiet \
        "${DMG_PATH}"

    rm -rf "${staging}"

    codesign --force --sign "${SIGN_IDENTITY}" --timestamp "${DMG_PATH}"
}

create_zip() {
    echo "Creating zip..."
    rm -f "${ZIP_PATH}"
    ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"
}

notarize() {
    local artifact="$1"
    echo "Submitting $(basename "${artifact}") for notarisation..."
    xcrun notarytool submit "${artifact}" \
        --apple-id "${APPLE_ID}" \
        --team-id "${APPLE_TEAM_ID}" \
        --password "${APPLE_APP_PASSWORD}" \
        --wait
}

staple_app() {
    echo "Stapling the ticket to the app..."
    xcrun stapler staple "${APP_PATH}"

    # What Gatekeeper will do on someone else's machine. Before notarisation
    # this same check reports "Unnotarized Developer ID".
    spctl --assess --type execute -v "${APP_PATH}"
}

staple_dmg() {
    echo "Stapling the ticket to the DMG..."
    xcrun stapler staple "${DMG_PATH}"
    spctl --assess --type open --context context:primary-signature -v "${DMG_PATH}"
}

report() {
    echo
    echo "Signed, notarized and stapled:"
    echo "  ${DMG_PATH}"
    echo "  ${ZIP_PATH}"
    echo
    shasum -a 256 "${DMG_PATH}" "${ZIP_PATH}"
}

main() {
    load_credentials
    require_credentials
    require_xcode

    cd "${PROJECT_ROOT}"

    archive_release
    export_developer_id
    read_metadata
    verify_signature

    # The app is notarized first, through a throwaway zip, because a ticket is
    # stapled to the app itself — not to the archive it travelled in. Both
    # artefacts below are then built from an already-stapled app, so each one
    # verifies offline on a machine that has never seen it.
    create_zip
    notarize "${ZIP_PATH}"
    staple_app

    create_zip
    create_dmg
    notarize "${DMG_PATH}"
    staple_dmg

    report
}

main "$@"
