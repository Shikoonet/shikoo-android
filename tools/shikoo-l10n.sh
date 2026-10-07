#!/usr/bin/env bash
# Regenerates lib/shikoo/l10n/generated/ from the ARB files next to it. Run from the repo root, after
# source ~/android-toolchain/env.sh. gen-l10n refuses a project whose pubspec lacks `flutter: generate: true`,
# and adding that to FlClash's pubspec would be one more upstream patch, so a throwaway project carries it.
set -euo pipefail
root=$(pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf 'name: shikoo_l10n\nenvironment:\n  sdk: ">=3.10.0 <4.0.0"\ndependencies:\n  flutter:\n    sdk: flutter\n  flutter_localizations:\n    sdk: flutter\n  intl: any\nflutter:\n  generate: true\n' >"$tmp/pubspec.yaml"
cd "$tmp"
flutter gen-l10n \
  --arb-dir "$root/lib/shikoo/l10n" --template-arb-file shikoo_en.arb \
  --output-dir "$root/lib/shikoo/l10n/generated" --output-localization-file shikoo_l10n.dart \
  --output-class ShikooL10n --no-nullable-getter
dart format "$root/lib/shikoo/l10n/generated"
