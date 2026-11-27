#!/usr/bin/env bash
# Materializes the upload keystore from CI secrets and writes android/key.properties.
# The keystore lives in the runner's temp directory and is deleted after the build.
set -euo pipefail

: "${ANDROID_KEYSTORE_BASE64:?missing secret}"
: "${ANDROID_KEYSTORE_PASSWORD:?missing secret}"
: "${ANDROID_KEY_ALIAS:?missing secret}"
: "${ANDROID_KEY_PASSWORD:?missing secret}"

keystore_path="${RUNNER_TEMP:?}/upload-keystore.jks"

umask 077
printf '%s' "$ANDROID_KEYSTORE_BASE64" | base64 --decode > "$keystore_path"

{
  printf 'storeFile=%s\n' "$keystore_path"
  printf 'storePassword=%s\n' "$ANDROID_KEYSTORE_PASSWORD"
  printf 'keyAlias=%s\n' "$ANDROID_KEY_ALIAS"
  printf 'keyPassword=%s\n' "$ANDROID_KEY_PASSWORD"
} > android/key.properties

echo "Release signing configured."
