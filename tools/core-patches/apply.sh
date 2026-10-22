#!/usr/bin/env bash
# Applies every patch here to the core submodule (one already applied is skipped), sing-tun/ to a copy of sing-tun,
# and sing-box/ to a copy of sing-box.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
core=$root/core/Clash.Meta

# An uninitialised submodule is an empty folder of this repository, and git would check the patches against it.
if ! prefix=$(git -C "$core" rev-parse --show-prefix 2>/dev/null) || [ -n "$prefix" ]; then
  echo "core/Clash.Meta is not checked out: run git submodule update --init core/Clash.Meta first." >&2
  exit 1
fi

for patch in "$root"/tools/core-patches/*.patch; do
  name=$(basename "$patch")
  if git -C "$core" apply --reverse --check "$patch" 2>/dev/null; then
    echo "core patch $name: already applied"
  elif git -C "$core" apply --check "$patch" 2>/dev/null; then
    git -C "$core" apply "$patch"
    echo "core patch $name: applied"
  else
    echo "core patch $name does not apply to core/Clash.Meta at $(git -C "$core" rev-parse --short HEAD)." >&2
    echo "Rebase it on the new core as its row in SHIKOO_PATCHES.md says, before building." >&2
    exit 1
  fi
done

# sing-tun is a module the core downloads, not part of the submodule: core/go.mod replaces the version mihomo pins with
# a patched copy made here, and go mod download checks that version against mihomo's go.sum.
singtun=v0.4.27
pinned=$(go -C "$core" list -m -f '{{.Version}}' github.com/metacubex/sing-tun)
if [ "$pinned" != "$singtun" ]; then
  echo "mihomo pins sing-tun $pinned, but tools/core-patches/sing-tun and core/go.mod are for $singtun." >&2
  echo "Rebase them as row ۳۲ in SHIKOO_PATCHES.md says, before building." >&2
  exit 1
fi
go -C "$core" mod download "github.com/metacubex/sing-tun@$singtun"
rm -rf "$core/shikoo-sing-tun"
cp -r "$(go -C "$core" list -m -f '{{.Dir}}' github.com/metacubex/sing-tun)" "$core/shikoo-sing-tun"
chmod -R u+w "$core/shikoo-sing-tun"
for patch in "$root"/tools/core-patches/sing-tun/*.patch; do
  if ! git -C "$core" apply --directory=shikoo-sing-tun "$patch"; then
    echo "sing-tun patch $(basename "$patch") does not apply to sing-tun $singtun." >&2
    exit 1
  fi
  echo "sing-tun patch $(basename "$patch"): applied to a copy of $singtun"
done

# sing-box, the same way: core/go.mod requires it and replaces it with a patched copy (row ۵۳ in SHIKOO_PATCHES.md).
singbox=v1.14.3
required=$(go -C "$root/core" list -m -f '{{.Version}}' github.com/sagernet/sing-box)
if [ "$required" != "$singbox" ]; then
  echo "core/go.mod requires sing-box $required, but tools/core-patches/sing-box and its replace line are for $singbox." >&2
  echo "Rebase them, or drop them if sing-box fixed it, as row ۵۳ in SHIKOO_PATCHES.md says, before building." >&2
  exit 1
fi
go -C "$root/core" mod download "github.com/sagernet/sing-box@$singbox"
rm -rf "$core/shikoo-sing-box"
cp -r "$(go -C "$root/core" list -m -f '{{.Dir}}' "github.com/sagernet/sing-box@$singbox")" "$core/shikoo-sing-box"
chmod -R u+w "$core/shikoo-sing-box"
for patch in "$root"/tools/core-patches/sing-box/*.patch; do
  if ! git -C "$core" apply --directory=shikoo-sing-box "$patch"; then
    echo "sing-box patch $(basename "$patch") does not apply to sing-box $singbox." >&2
    exit 1
  fi
  echo "sing-box patch $(basename "$patch"): applied to a copy of $singbox"
done

# git keeps the core's embedded CA bundle empty (mihomo's CI fills it), and Android 7 has no root for the SSL.com
# chain of 1.1.1.1, the panel's DNS. Mozilla roots only, never a CA added to this machine. Windows has no such folder,
# so its build is handed the Linux job's bundle in SHIKOO_CA_DIR and embeds the very same roots.
cat "${SHIKOO_CA_DIR:-/usr/share/ca-certificates/mozilla}"/*.crt > "$core/component/ca/ca-certificates.crt"
echo "core CA bundle: $(grep -c BEGIN "$core/component/ca/ca-certificates.crt") roots"
