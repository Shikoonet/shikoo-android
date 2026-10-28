#!/usr/bin/env bash
# Fails if an APK carries Firebase, Crashlytics, ML Kit or Google datatransport again, asks for the ad, camera,
# location, all-packages or battery-exemption permissions, exposes FlClash's files provider or clash:// links, links
# EasyTier into the core, or has a 32-bit Go 1.26.3 or 1.26.4 core, whose runtime exits at start on a kernel release
# like 4.9.37_s5 (golang/go#79612), or an OpenVPN 3 whose mbedTLS blocks on /dev/random. Run it on every APK after
# merging FlClash (SHIKOO_PATCHES.md 5-8, 30 and 35).
#   bash tools/check_apk_clean.sh build/app/outputs/flutter-apk/app-*-release.apk
set -euo pipefail

aapt2=${AAPT2:-$(ls "$ANDROID_HOME"/build-tools/*/aapt2{,.exe} 2>/dev/null | tail -1 || true)}
[ -x "$aapt2" ] || { echo "aapt2 not found: set AAPT2 or ANDROID_HOME" >&2; exit 2; }
[ $# -gt 0 ] || { echo "usage: $0 <apk>..." >&2; exit 2; }

# grep exits 1 for "no match", which is the clean case; any other failure must stop the script
find_in() { grep -iE "$1" <<<"$2" || [ $? -eq 1 ]; }

status=0
for apk in "$@"; do
  # read each listing first: a failing tool must stop the script, not read as "nothing found"
  files=$(unzip -Z1 "$apk")
  badging=$("$aapt2" dump badging "$apk")
  manifest=$("$aapt2" dump xmltree --file AndroidManifest.xml "$apk")
  # the module path is in the core only when EasyTier is linked; mihomo's own no_easytier stub never names it
  core=$(unzip -p "$apk" 'lib/*/libclash.so' |
    { grep -aoE 'github\.com/easytier/[[:alnum:]_-]+(/[[:alnum:]_-]+)?|failed to parse kernel version from uname' || [ $? -eq 1 ]; } | sort -u)
  ovpn=$(unzip -p "$apk" 'lib/*/libovpn3.so' | { grep -aoE '/dev/u?random' || [ $? -eq 1 ]; } | sort -u)
  hits=$(
    set -e
    find_in 'libcrashlytics|transport-|firebase-|mlkit' "$files"
    find_in 'ad_id|adservices|permission\.camera|_location|query_all_packages|get_installed_apps|ignore_battery' "$badging"
    find_in 'firebase|crashlytics|mlkit|datatransport|measurement|GoogleApiActivity|gms\.version|androidx\.camera|FilesProvider|DOCUMENTS_PROVIDER|scheme\(0x[0-9a-f]+\)="(clash|clashmeta|flclash)"|install-config' "$manifest" |
      sed -E 's/ \(Raw: .*//'
    find_in 'easytier|kernel version' "$core" | sed 's/^/libclash.so: /'
    find_in '^/dev/random$' "$ovpn" | sed 's/^/libovpn3.so: /'
  )
  if [ -n "$hits" ]; then
    echo "FAIL $apk"
    sed 's/^ */  /' <<<"$hits"
    status=1
  else
    echo "OK   $apk"
  fi
done
exit $status
