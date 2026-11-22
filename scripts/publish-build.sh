#!/usr/bin/env bash
# Publish a build to an app_updater CI server (or only write app-update.json).
#
#   ./publish-build.sh --endpoint https://updates.example.com \
#     --app watchtower --file build/app.apk --version 1.4.2 --platform android
#
# Environment: APP_UPDATER_CI_TOKEN is used when --token is omitted.
set -euo pipefail

ENDPOINT=""
APP=""
FILE=""
VERSION=""
PLATFORM="android"
CHANNEL="stable"
ABI=""
NOTES=""
NOTES_FILE=""
BUILD_NUMBER=""
MINIMUM_VERSION=""
RELEASE_URL=""
URGENCY="medium"
EXTERNAL_URL=""
TOKEN="${APP_UPDATER_CI_TOKEN:-}"
MANDATORY="false"
WRITE_MANIFEST="false"

usage() {
  sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --endpoint) ENDPOINT="$2"; shift 2 ;;
    --app) APP="$2"; shift 2 ;;
    --file) FILE="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --platform) PLATFORM="$2"; shift 2 ;;
    --channel) CHANNEL="$2"; shift 2 ;;
    --abi) ABI="$2"; shift 2 ;;
    --notes) NOTES="$2"; shift 2 ;;
    --notes-file) NOTES_FILE="$2"; shift 2 ;;
    --build-number) BUILD_NUMBER="$2"; shift 2 ;;
    --minimum-version) MINIMUM_VERSION="$2"; shift 2 ;;
    --release-url) RELEASE_URL="$2"; shift 2 ;;
    --urgency) URGENCY="$2"; shift 2 ;;
    --url) EXTERNAL_URL="$2"; shift 2 ;;
    --token) TOKEN="$2"; shift 2 ;;
    --mandatory) MANDATORY="true"; shift ;;
    --write-manifest) WRITE_MANIFEST="true"; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$APP" && -n "$FILE" && -n "$VERSION" ]] || usage
[[ -f "$FILE" ]] || { echo "File not found: $FILE" >&2; exit 1; }
if [[ -n "$NOTES_FILE" ]]; then NOTES="$(cat "$NOTES_FILE")"; fi

SHA256="$(sha256sum "$FILE" | cut -d' ' -f1)"
SIZE="$(wc -c < "$FILE" | tr -d ' ')"
FILE_NAME="$(basename "$FILE")"

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

json_field() {
  local key="$1" value="$2"
  [[ -n "$value" ]] && printf '"%s": %s, ' "$key" "$(json_escape "$value")"
}

if [[ "$WRITE_MANIFEST" == "true" ]]; then
  MANIFEST_DIR="$(dirname "$FILE")"
  {
    echo "{"
    echo "  \"version\": $(json_escape "$VERSION"),"
    echo "  \"platform\": $(json_escape "$PLATFORM"),"
    echo "  \"channel\": $(json_escape "$CHANNEL"),"
    echo "  \"sha256\": \"$SHA256\","
    echo "  \"size\": $SIZE,"
    echo "  \"publishedAt\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
    echo "}"
  } > "$MANIFEST_DIR/app-update.json"
  echo "Wrote $MANIFEST_DIR/app-update.json"
fi

if [[ -z "$ENDPOINT" ]]; then
  echo "No --endpoint given: manifest written, nothing uploaded."
  exit 0
fi

ENDPOINT="${ENDPOINT%/}"
BODY="{"
BODY+="\"version\": $(json_escape "$VERSION"), "
BODY+="\"platform\": $(json_escape "$PLATFORM"), "
BODY+="\"channel\": $(json_escape "$CHANNEL"), "
BODY+="\"urgency\": $(json_escape "$URGENCY"), "
BODY+="\"mandatory\": $MANDATORY, "
BODY+="$(json_field buildNumber "$BUILD_NUMBER")"
BODY+="$(json_field abi "$ABI")"
BODY+="$(json_field releaseNotes "$NOTES")"
BODY+="$(json_field minimumVersion "$MINIMUM_VERSION")"
BODY+="$(json_field releaseUrl "$RELEASE_URL")"
if [[ -n "$EXTERNAL_URL" ]]; then
  BODY+="$(json_field url "$EXTERNAL_URL")"
else
  BODY+="$(json_field fileName "$FILE_NAME")"
fi
BODY="${BODY%, }"
BODY+="}"

AUTH=()
if [[ -n "$TOKEN" ]]; then AUTH=(-H "Authorization: Bearer $TOKEN"); fi

RESPONSE="$(curl -fsS -X POST "$ENDPOINT/v1/apps/$APP/builds" \
  -H 'Content-Type: application/json' ${AUTH[@]+"${AUTH[@]}"} -d "$BODY")"
BUILD_ID="$(printf '%s' "$RESPONSE" | sed -n 's/.*"buildId":"\([^"]*\)".*/\1/p')"
[[ -n "$BUILD_ID" ]] || { echo "Unexpected response: $RESPONSE" >&2; exit 1; }

if [[ -n "$EXTERNAL_URL" ]]; then
  echo "Published build $BUILD_ID (external URL)"
else
  curl -fsS -X PUT "$ENDPOINT/v1/apps/$APP/builds/$BUILD_ID/artifact" \
    -H "Content-Type: application/octet-stream" \
    -H "X-File-Name: $FILE_NAME" \
    -H "X-Sha256: $SHA256" ${AUTH[@]+"${AUTH[@]}"} --data-binary "@$FILE" > /dev/null
  echo "Published build $BUILD_ID ($FILE_NAME, $SIZE bytes)"
fi
echo "Feed: $ENDPOINT/v1/apps/$APP/latest?platform=$PLATFORM&channel=$CHANNEL"
