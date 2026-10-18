#!/usr/bin/env bash
# Uploads the APKs and the Windows installer listed in <dir>/SHA256SUMS to the app door and publishes them as one release
# (docs/app-update.md). An installer needs its seal beside it, <file>.sig, as shikoo-staging.yml writes it.
#   DOOR_TOKEN=<the door's RELEASE_TOKEN> bash tools/publish_door.sh https://app-dev.chopon.uk out false
set -euo pipefail
set +x
api=${1%/} dir=$2 force=$3
[[ $force == true || $force == false ]] || { echo "::error::force must be true or false, not '$force'"; exit 1; }
[ -n "${DOOR_TOKEN:-}" ] || { echo "::error::DOOR_TOKEN is empty"; exit 1; }
tools=("$ANDROID_HOME"/build-tools/*/aapt2) && aapt2=${tools[-1]}

work=$(mktemp -d) && trap 'rm -rf "$work"' EXIT
(umask 077 && printf 'Authorization: Bearer %s\n' "$DOOR_TOKEN" >"$work/auth")
# ponytail: --retry-all-errors also repeats a 401 or 422 six times, so it fails 30-40 s late; a loop on %{http_code} would stop on 4xx
# A request that stalls with the connection still open is cut after 60 s and retried, instead of waiting for the job's timeout
door() {
  curl -sS --fail-with-body --retry 5 --retry-all-errors --connect-timeout 30 --speed-limit 1024 --speed-time 60 \
    -H @"$work/auth" "$@"
}

rows=() names=()
while read -r sha file <&3; do
  apk=$dir/${file#\*} code='' sig=''
  case $apk in
    *.apk)
      badging=$("$aapt2" dump badging "$apk")
      code=$(sed -n "s/^package: .* versionCode='\([0-9]*\)'.*/\1/p" <<<"$badging")
      name=$(sed -n "s/^package: .* versionName='\([^']*\)'.*/\1/p" <<<"$badging")
      abi=$(sed -n "s/^native-code: '\([^' ]*\)'$/\1/p" <<<"$badging")
      ;;
    *-windows-x64.exe)
      read -r sig <"$apk.sig" || true
      [[ $sig =~ ^[A-Za-z0-9+/]+=*$ ]] || { echo "::error::$apk.sig holds no base64 seal"; exit 1; }
      # Its version code is its build number, the last part of its version name (docs/release-pipeline.md §5)
      name=$(sed -n 's/^ShikooNet-\([0-9.]*\)-.*/\1/p' <<<"${apk##*/}") abi=windows-x64
      code=${name##*.}
      ;;
    *) echo "::error::$apk is neither an APK nor the Windows installer"; exit 1 ;;
  esac
  [ -n "$code" ] && [ -n "$abi" ] || { echo "::error::$apk has no versionCode or more than one ABI"; exit 1; }
  size=$(stat -c %s "$apk")
  for ((off = 0; off == 0 || off < size; off += 8 << 20)); do
    dd if="$apk" of="$work/chunk" bs=1M skip=$((off >> 20)) count=8 status=none
    door -T "$work/chunk" "$api/dl/upload/${apk##*/}?offset=$off" >/dev/null
  done
  echo "uploaded ${apk##*/}: $abi, versionCode $code, $size bytes"
  rows+=("$abi ${apk##*/} $code $sha $sig") names+=("$name")
done 3<"$dir/SHA256SUMS"

[ "${#rows[@]}" -gt 0 ] || { echo "::error::$dir/SHA256SUMS lists no APK"; exit 1; }
[ "$(printf '%s\n' "${names[@]}" | sort -u | wc -l)" -eq 1 ] || { echo "::error::the files carry different versionNames"; exit 1; }
printf '%s\n' "${rows[@]}" | jq -nR --arg name "${names[0]}" --argjson force "$force" \
  '{version_name: $name, force: $force,
    apks: [inputs | split(" ") | {abi: .[0], file: .[1], version_code: (.[2] | tonumber), sha256: .[3]}
      + (if .[4] != "" then {sig: .[4]} else {} end)]}' >"$work/publish.json"
door -H 'Content-Type: application/json' --data-binary @"$work/publish.json" "$api/dl/publish"
echo
