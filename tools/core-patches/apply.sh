#!/usr/bin/env bash
# Applies every patch here to the core submodule; one already applied is skipped.
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

# git keeps the core's embedded CA bundle empty (mihomo's CI fills it), and Android 7 has no root for the SSL.com
# chain of 1.1.1.1, the panel's DNS. Mozilla roots only, never a CA added to this machine. Windows has no such folder,
# so its build is handed the Linux job's bundle in SHIKOO_CA_DIR and embeds the very same roots.
cat "${SHIKOO_CA_DIR:-/usr/share/ca-certificates/mozilla}"/*.crt > "$core/component/ca/ca-certificates.crt"
echo "core CA bundle: $(grep -c BEGIN "$core/component/ca/ca-certificates.crt") roots"
