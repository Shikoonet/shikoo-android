#!/usr/bin/env bash
# Fails if an APK carries Firebase, Crashlytics, ML Kit or Google datatransport again, or asks for the
# ad, camera or location permissions. Run it on every APK after merging FlClash (SHIKOO_PATCHES.md 5-8).
#   bash tools/check_apk_clean.sh build/app/outputs/flutter-apk/app-*-release.apk
set -euo pipefail

aapt2=${AAPT2:-$(ls "$ANDROID_HOME"/build-tools/*/aapt2{,.exe} 2>/dev/null | tail -1 || true)}
[ -x "$aapt2" ] || { echo "aapt2 not found: set AAPT2 or ANDROID_HOME" >&2; exit 2; }
[ $# -gt 0 ] || { echo "usage: $0 <apk>..." >&2; exit 2; }

status=0
for apk in "$@"; do
  # read each listing first: a failing tool must stop the script, not read as "nothing found"
  files=$(unzip -Z1 "$apk")
  badging=$("$aapt2" dump badging "$apk")
  manifest=$("$aapt2" dump xmltree --file AndroidManifest.xml "$apk")
  hits=$(
    grep -iE 'libcrashlytics|transport-|firebase-|mlkit' <<<"$files"
    grep -iE 'ad_id|adservices|permission\.camera|_location' <<<"$badging"
    grep -iE 'firebase|crashlytics|mlkit|datatransport|measurement' <<<"$manifest" | sed -E 's/ \(Raw: .*//'
  ) || true
  if [ -n "$hits" ]; then
    echo "FAIL $apk"
    sed 's/^ */  /' <<<"$hits"
    status=1
  else
    echo "OK   $apk"
  fi
done
exit $status
