# Release pipeline: branch → PR → CI → main → staging → Promote

> **خلاصه برای سم**
> - **مثل پلتفرم:** هر تغییر از شاخه و PR می‌آید. بعد از ادغام در `main`، گیت‌هاب خودش نسخهٔ آزمایشی (staging) می‌سازد. انتشار برای مشتری فقط با دکمهٔ «Shikoo Promote»، که فقط شما می‌زنید.
> - **یک فرق با پلتفرم:** نشانی سرور و ربات داخل خود اپ ساخته می‌شوند. پس «همان فایل» برای آزمایش و برای مشتری ممکن نیست. به‌جایش هر بار **دو نسخه از یک کامیت، در یک کار** ساخته می‌شود: نسخهٔ آزمایشی (سرور و ربات آزمایشی) و نسخهٔ مشتری. اثر انگشت (sha256) هر دو ثبت می‌شود، و دکمهٔ Promote **همان فایل ثبت‌شدهٔ مشتری** را منتشر می‌کند، بدون ساخت دوباره.
> - **فعلاً همه‌چیز داخل گیت‌هابِ خصوصی می‌ماند:** نسخهٔ آزمایشی یک «پیش‌انتشار» است و نسخهٔ مشتری یک «انتشار». فرستادن به ربات و سایت، و به‌روزرسانی خودکار داخل اپ، قدم ۸ نقشهٔ راه است.
> - **کارهای یک‌باره و تصمیم‌های شما** در بخش ۷ و ۸ آمده‌اند. مهم‌ترینش: روی پلن رایگان گیت‌هاب «تأییدکنندهٔ اجباری» برای مخزن خصوصی وجود ندارد. پس دروازهٔ Promote همان بررسی نام کاربری و انتخاب «PROMOTE» است، مثل پلتفرم.

Design and draft workflows, 2026-10-05, branch `chore/release-pipeline`. **Nothing here has run on GitHub**: Actions is off in
this repository. What was run is in §9.

Files: `.github/workflows/shikoo-ci.yml`, `shikoo-staging.yml`, `shikoo-promote.yml`, `tools/publish_door.sh`.

## 0. What carries over from shikoo-platform, and what does not

The platform's release story (`shikoo-platform/docs/RELEASE.md`) is: green `main` → staging builds ONE artifact and records
it → a person promotes exactly that artifact. Mapped to an APK:

| Platform | Here |
|---|---|
| `Deploy Staging` on `workflow_run` of CI, only `conclusion == success`, `event == push`, `head_branch == main`; builds `workflow_run.head_sha`, never the default checkout | Same four conditions, same explicit sha (`shikoo-staging.yml`) |
| Manual staging redeploy: `workflow_dispatch` with **no inputs**; resolves `main` on the server; `require-ci-run.sh` refuses unless CI passed on that sha as a push to main | Same, in one `gh run list` line instead of a 115-line script. A dispatch from any other ref fails loudly, as the platform's does |
| `approval-gate.sh`: the sha must be a merged PR, plus team/solo review rules | Only the first half: the sha must belong to a merged PR (one `gh api …/commits/{sha}/pulls` line). The review rules are not ported: on GitHub Free nothing enforces reviews, and Promote's owner check is the human gate |
| Staging builds one image and records its digest in an artifact; Promote has no digest input and reads that artifact | Staging builds both APK variants and records their sha256 in a pre-release and in the run summary; Promote has no file, sha or version input and publishes the recorded production APKs after `sha256sum -c` |
| Promote: `main` only, actor allowlist, typed `PROMOTE` choice, `environment: production` | Same. Its one input is that yes/no choice; nothing in it names what ships |
| One concurrency group for staging and Promote, never cancelled | Same (`shikoo-release`) |

Not ported, because an APK has no server to converge: Coolify, image digests, GHCR pruning, release manifests with their own
checksums, `pick-staging-run.sh`, dump attestations, the CI path classifier and the main-provenance proof.

## 1. CI on pull requests and `main` (`shikoo-ci.yml`)

| Job | Runs on | What |
|---|---|---|
| `checks` | every PR event, every push to `main` | conventional commit messages of the PR's commits (`tool/check_commit_msg.sh`), comment density of the PR's added lines (`tool/check_comment_density.sh`), `dart format`, `flutter analyze --no-fatal-infos`; and, except on drafts, `flutter test` with the native hooks off (the same `yq` switch FlClash's CI uses) |
| `apk` | PRs that are **not drafts** | one release APK of the Shikoo app (`-t lib/shikoo/app/main.dart`), `armeabi-v7a`, then `tools/check_apk_clean.sh` on it |

- **Why only v7a in CI:** it is the ABI Sam's Mi Box needs, and the one FlClash's own CI never compiles before a tag. Staging
  builds all of them anyway.
- **Why no APK on `main` pushes:** staging builds and checks every APK of that commit right after, so a second build would only
  spend minutes.
- **Draft first,** as in the platform's `ci-execution-policy.md`: a draft PR runs the static checks only (about 3 minutes);
  marking it Ready buys the tests and the APK.
- **The entry point matters:** a plain `flutter build apk` builds FlClash's own UI from `lib/main.dart`. The first probe
  build did exactly that (no `shikoo` string in its `libapp.so`), so every build here passes `-t lib/shikoo/app/main.dart`.
- **Commit and comment checks on a PR** run against the PR's own range. Comment density measures uncommitted lines, so the job
  moves `HEAD` back to the base with `git reset --soft` and hands it the changed files.
- **FlClash merges:** a PR from a branch named `upstream/…` skips the two checks above, because FlClash's own commits and
  comments are not ours to rewrite. Everything else still runs.

### FlClash's own `build.yaml` stays off, with no file edit

It runs on every push to every branch and on `v*` tags. Promote creates `v*` tags, but with `GITHUB_TOKEN`, and events made
with that token start no workflows; a `v*` tag pushed by a person would. Turning it off is a repository setting:

```bash
gh workflow disable build.yaml -R Shikoonet/shikoo-android
```

No upstream file changes, so no `SHIKOO_PATCHES.md` row, and FlClash merges never conflict on it. The setting is kept by
workflow file, so a merged newer `build.yaml` stays disabled. It must be run right after Actions is turned on and before the
next push (§7).

### What the Go core costs, and the cache

Measured in WSL on 2026-10-05 with a cold Go build cache, a fresh tree and the build pinned to **2 CPUs** (`taskset -c 0,1`),
the size of a GitHub `ubuntu-latest` runner for a private repository. See §9 for the commands.

| Step, 2 CPUs | Time |
|---|---|
| Go core, cold, per ABI (armeabi-v7a, arm64-v8a, x86_64) | 3:03, 3:06, 3:02 |
| Full cold build of three ABIs (Go core, Rust library, Gradle, Dart AOT) | 1,146 s, about 19 min |
| Second build of the same tree, two ABIs, Go core from the hook's cache | 134–199 s |
| `flutter analyze --no-fatal-infos` | 44 s |
| `flutter test`, native hooks off | 399 s |

Downloads were warm in WSL (pub, Gradle, Go modules, cargo registry), because this machine reaches the internet only through
the proxy; on a runner they come from GitHub's caches or a fast network. So these are build times, not wall times of a run.

The cache (`actions/cache`, key on `core/**`, `build_config.yaml`, `plugins/setup/**`, `plugins/rust_api/rust/**`) holds
FlClash's hook outputs (`libclash/`, `.dart_tool/setup_build_cache`, `.dart_tool/hooks_runner`) and the cargo registry.
`setup-go` caches Go modules and the Go build cache on `core/go.sum`. The hook decides by its own fingerprint whether to
rebuild, so a stale cache costs time, never correctness. Caches saved by staging (on `main`) are readable by every PR; a PR's
own cache is visible only to that PR.

**Minutes:** the organization is on GitHub Free, 2,000 Linux minutes a month for private repositories, shared with
shikoo-platform (which moved its CI to self-hosted runners on 2026-10-01). Estimated from the table, per job and rounded up as GitHub bills:

| Run | Minutes |
|---|---|
| draft PR push (`checks` without tests) | ~3 |
| Ready PR push (`checks` with tests, plus `apk`) | ~10 + ~5 (~10 when the Go core changed) |
| push to `main` (`checks`) | ~10 |
| `Shikoo Staging`, Go core unchanged / changed | ~12 / ~28 |

A typical merged change (three draft pushes, one Ready push, main, staging) is about 45 minutes, so roughly 40 merges a month
fit, if the platform uses none. The tests are the biggest single item. When that is not enough, the lever is the platform's:
a self-hosted runner behind a repository variable (`vars.CI_RUNS_ON` in shikoo-platform's `ci.yml`), not shortcuts in the
checks.

## 2. Staging builds two variants of one commit (`shikoo-staging.yml`)

The app's server and bot are compiled in (`String.fromEnvironment('SHIKOO_API')` in `lib/shikoo/engine/settings.dart`), so
one file cannot serve both testers and customers. One staging run builds both, from the same checkout, in the same job:

| | staging | production |
|---|---|---|
| Server | `https://app-dev.chopon.uk` via `--dart-define=SHIKOO_API` (live, GTS certificate, reachable from Iran without a VPN) | the default in the code, `https://app.chopon.uk` |
| Bot | `shikoodevbot` via `--dart-define=SHIKOO_BOT` (staging's `login/start` returns `t.me/shikoodevbot`) | the default in the code, `shikoonet_bot` |
| applicationId | `com.shikoonet.app.dev` | `com.shikoonet.app` |
| Signed with | the staging key (secret), stable across runs | the release key (secrets) |
| ABIs | armeabi-v7a, arm64-v8a, x86_64 | armeabi-v7a, arm64-v8a |
| Files | `ShikooNet-<version>-staging-<abi>.apk` | `ShikooNet-<version>-<abi>.apk` |

**How the variant is chosen without touching FlClash's signing logic.** `android/app/build.gradle.kts` has no flavors; the
only Shikoo edit there that touches the id or signing is `applicationId = "com.shikoonet.app"` (`SHIKOO_PATCHES.md` row
11; the other is the Firebase removal, row 5). Its
`release` build type already switches on whether `android/app/keystore.jks` and three `local.properties` keys exist: with
them, the release signing config and no suffix; without them, the debug signing config and `applicationIdSuffix = ".dev"`.
Both variants are `flutter build apk --release` (Gradle `assembleRelease`) and land in
`build/app/outputs/flutter-apk/app-<abi>-release.apk`. So the job builds staging first, with no `keystore.jks` and the
staging key placed as `~/.android/debug.keystore`, then writes `keystore.jks` and builds production.
The staging key being stable matters: a fresh runner debug key would make every staging APK a different signer, and testers
would have to uninstall before each update. The keys are deleted at the end of the job, also on failure.

**Guards in the job:**
- the code must read both `SHIKOO_API` and `SHIKOO_BOT` from the build, or the job fails: a define the code ignores would send
  testers to the production bot silently;
- the staging server and bot must not equal the production ones, compared without case, a trailing `/` or a leading `@`;
- the staging APKs share one signer, the production APKs share another, and the two differ (`apksigner verify
  --print-certs`): a production APK signed by the staging key, which the runner also uses as its debug key, is refused;
- every APK passes `tools/check_apk_clean.sh`;
- every staging APK's `libapp.so` contains the staging server and its package is exactly `com.shikoonet.app.dev`; every
  production APK's `libapp.so` lacks it and its package is exactly `com.shikoonet.app` (`APP_ID` in `shikoo-staging.yml`).
  This guard exists because the probe once got it wrong: a production build came out with the `.dev` suffix, debug-signed
  (FlClash's `com.follow.clash.dev`, before the id changed).
  The most likely cause is a `local.properties` that Flutter had written without a final newline, so the appended
  `storePassword=` joined the previous line. The job now writes a newline first; the guard catches it if that was not all.

**What is still not identical, and why that is acceptable.** The two variants differ in compiled constants, applicationId and
signature, so their bytes differ, and what testers ran is not byte-for-byte what customers get. What they share: the commit,
the toolchain, the job, and the native core: the hook builds `libclash.so` once and the second build reuses it (in the
probe the arm64 `libclash.so` of both variants had the same sha256, `b8b1a1a0…`).
The honest gap is the production server and bot themselves, which testers never touch. Sam closes it by installing the
production APK from the same pre-release on his box before pressing Promote (§7, step 8). Rebuilding at promote time would be
worse, not better: these builds are not byte-for-byte reproducible (`.claude/CLAUDE.md`, step 2), so a rebuild is a new,
untested file.

With no release key in the secrets yet, the job builds staging only, warns, and Promote refuses (nothing to promote).

## 3. Where each APK goes

**Now, the smallest thing that works:**
- **Staging:** a GitHub **pre-release** `staging-<version>` in this private repository, holding all five APKs, `SHA256SUMS`
  and, in its notes, the sha256 list and the `aapt2 dump badging` lines of each APK. Testers download from there, so a tester
  needs read access to the repository.
  Unlike the platform's run artifact, a release is editable: anyone with write access can replace an asset and
  `SHA256SUMS` together. The run summary of the staging job keeps the original list, and Promote prints the list it checked,
  so the two can be compared by eye; nothing compares them automatically.
- **Production:** Promote creates the release `v<version>` (marked Latest) with the two production APKs and their
  `SHA256SUMS`. That release is the record of what customers have; customers get the same bytes from the production door.

**Why releases and not Actions artifacts:** GitHub Free gives an organization 500 MB of artifact storage; one staging run is
about 260 MB of APKs (five, about 52 MB each), so two runs inside a retention window fill it and block uploads. Release
assets do not count against that storage.

**The app door, for the in-app update** (`docs/app-update.md`): the app door of each environment serves the APKs itself
(`/dl/<file>`, the stable `/dl/<abi>`, and `/api/v1/app/update`, which the app reads).
- **Staging:** a separate job `door` after `build` downloads the three `-staging-` APKs of `staging-<version>`, checks
  them with `sha256sum -c`, and publishes them to the staging door (`STAGING_API`) with `force=false`. It can be re-run
  alone, without a rebuild. Without `SHIKOO_STAGING_DOOR_TOKEN` it warns and skips; the pre-release stays.
- **Production:** Promote publishes the two production APKs to `https://app.chopon.uk` after `sha256sum -c` and before
  `gh release create`, with its `force` input (`no` by default; `yes` makes every older install update before use). If the
  door step fails, or its token is missing, Promote stops there: no GitHub release, nothing published anywhere.
- **`tools/publish_door.sh <api> <dir> <true|false>`:** for each APK in `<dir>/SHA256SUMS`, versionCode, versionName and
  its one ABI from `aapt2 dump badging`; uploads it in 8 MiB chunks (`PUT /dl/upload/<file>?offset=N`), each retried up to
  5 times on any error, so a lost answer resends the same bytes to the same offset; then `POST /dl/publish` with a body
  built by `jq`. The door hashes every file and refuses a mismatch (422) without changing the live release. The token
  comes only from `DOOR_TOKEN`, goes to curl through a `0600` header file in a temporary folder, and is never on a command
  line or in the log.
- The bot and a website link to `https://app.chopon.uk/dl/armeabi-v7a` and `…/dl/arm64-v8a`, which never change between
  releases (panel rows, `docs/app-update.md` › Bot).

## 4. Signing and door secrets

Secrets, **by name only**. Values are never in the repository, never echoed, and GitHub masks them in logs; the job decodes
them to files and deletes the files at the end.

| Secret | For |
|---|---|
| `SHIKOO_STAGING_KEYSTORE_B64` | staging: `shikoonet-staging.jks`, base64. A debug-format keystore (alias `androiddebugkey`, passwords `android`, as Android's own debug key). The file is the secret; the passwords are public by design |
| `SHIKOO_RELEASE_KEYSTORE_B64` | production: `shikoonet-release.jks`, base64 (PKCS12) |
| `SHIKOO_RELEASE_KEY_ALIAS` | production: `shikoonet` |
| `SHIKOO_RELEASE_STORE_PASSWORD`, `SHIKOO_RELEASE_KEY_PASSWORD` | production: both the same value, the one in `password.txt`; a PKCS12 store has one password |
| `SHIKOO_STAGING_DOOR_TOKEN` | staging `door` job: the `RELEASE_TOKEN` of `shikoo-dev-app`. Unset: the job warns and skips |
| `SHIKOO_PRODUCTION_DOOR_TOKEN` | Promote: the `RELEASE_TOKEN` of `shikoo-prod-app`. Unset: Promote fails before publishing |

Sam makes both keystores and `password.txt` with his `make-signing-key.ps1`, outside this repository. Only
`shikoo-staging.yml` reads the signing secrets: the staging one in its «Staging APKs» step, the four release ones in
«Production APKs». The staging door token is read only by its `door` job, the production door token only by Promote's door
step. CI reads none.

Repository variables, optional (not secrets, they are inside the APK anyway): `SHIKOO_STAGING_API` and `SHIKOO_STAGING_BOT`
override the defaults `https://app-dev.chopon.uk` and `shikoodevbot` in `shikoo-staging.yml`.

**The limit of GitHub Free, stated plainly.** GitHub's documentation puts environments in private repositories on Pro, Team
and Enterprise, and required reviewers in private repositories on Enterprise only. On this Free organization there is no
environment today (`GET …/environments` answers `total_count: 0`; shikoo-platform's answers 404), and shikoo-platform's
deploys run with `environment:` set, so the key does not stop a job. What GitHub records for it here is not tested. So
`environment: production` in Promote protects nothing on Free; it is there for when the plan allows rules. Repository
secrets are readable by any workflow on any branch, so **anyone with write access to this repository can read the release key**
by pushing a workflow, and the door tokens with it. Today that is Sam, arshia and the agents working for them, and agents
never push without permission.
GitHub Team would allow environment secrets limited to `main`; required reviewers on a private repository need Enterprise.

## 5. Versioning

- **versionName** `1.0.<n>` and **versionCode** `<n>`, where `<n>` is the staging workflow's run number; both variants of one
  run share it. CI passes `--build-name` and `--build-number`, so `pubspec.yaml` (FlClash's `0.8.98+2026091401`) stays
  untouched and no upstream row is needed. `1.0` is `VERSION_PREFIX` in `shikoo-staging.yml`; bump it by hand for a bigger
  release.
- Flutter's `--split-per-abi` adds a per-ABI offset to the versionCode: armeabi-v7a `1000 + n`, arm64-v8a `2000 + n`, x86_64
  `4000 + n` (measured: `--build-number=7` gave 1007, 2007, 4007). Within each ABI the code grows with every run, which is
  what an update needs.
- Settings shows versionName (`globalState.packageInfo.version`), so it will read `1.0.<n>` instead of `0.8.98`.
- Two side effects of the version change, both in FlClash code:
  - the subscription User-Agent (`lib/common/package.dart`, with the `appName` constant `'FlClash'` from
    `lib/common/constant.dart`, not the Android label) changes only in its version: `FlClash/v0.8.98 clash-verge
    Platform/android` becomes `FlClash/v1.0.<n> clash-verge Platform/android`. **Not yet tested against the panel.**
  - FlClash's update check compares against FlClash's GitHub releases; `1.0.<n>` is newer than any `0.8.x`, so it never offers
    an update.
- The run number restarts if the workflow file is renamed. Do not rename it, or bump `VERSION_PREFIX` when you do.
- Local WSL builds keep FlClash's `2026091401`-style code and `com.shikoonet.app.dev` signed by the WSL debug key, so they never update
  over a CI build and vice versa.

## 6. ABIs

| ABI | Ships to customers | Why |
|---|---|---|
| armeabi-v7a | yes | Sam's Mi Box and most cheap boxes are 32-bit (`docs/tv-devices.md`) |
| arm64-v8a | yes | phones; some recent phones run no 32-bit code at all |
| x86_64 | staging only | emulators (`shikoo-phone`, `shikoo-tv`) |

Per-ABI APKs, not one universal file: a universal v7a + arm64 APK is about twice the download, which matters on Iranian
networks. The cost is that the bot or site must offer two links («تلویزیون و باکس» → v7a, «گوشی» → arm64); the in-app update
later picks by itself.

## 7. What Sam does by hand, once

1. Decide the items in §8 (at least where the release key lives) before the first production build. Before the first
   Promote, the production door `shikoo-prod-app` must exist with its volume and `RELEASE_TOKEN` (`docs/app-update.md`).
2. Repository ▸ Settings ▸ Actions ▸ General: allow Actions.
3. Immediately, before any push: `gh workflow disable build.yaml -R Shikoonet/shikoo-android`.
4. Settings ▸ Secrets and variables ▸ Actions: add the secrets and variables of §4, from the folder `make-signing-key.ps1`
   wrote. A keystore's base64, in PowerShell, with the full path (`[IO.File]` does not follow PowerShell's current folder):
   `[Convert]::ToBase64String([IO.File]::ReadAllBytes('D:\ShikooNet-signing-key\shikoonet-staging.jks'))`, and the same
   for `D:\ShikooNet-signing-key\shikoonet-release.jks`. The two door tokens are each door's `RELEASE_TOKEN`, copied from
   its Coolify app.
5. Nothing for environments: on GitHub Free a private repository gets no environment rules (§4).
6. Merge this branch (after the prerequisites in §9) and watch the first `Shikoo Staging` run.
7. Give each tester read access to the repository, or decide another way to hand them the staging APK (§8).
8. For every release: install the production APK from the staging pre-release on the box, sign in once, then Actions ▸
   Shikoo Promote ▸ Run workflow ▸ choose `PROMOTE`, and `force` `yes` only when older versions must stop working.

## 8. Sam's decisions (placeholders until then)

| Decision | Placeholder in the files |
|---|---|
| ~~**applicationId**~~ Decided 2026-10-06: `com.shikoonet.app`, staging `com.shikoonet.app.dev`. Final after the first customer install | `APP_ID` in `shikoo-staging.yml`; the id itself in `android/app/build.gradle.kts` on `feat/app` |
| **Where the release key is made and kept**, and who holds the backup. Losing it means every customer reinstalls | `SHIKOO_RELEASE_*` secrets |
| **Who may promote** (GitHub user names) | `PROMOTE_OWNERS: Isusami,arshiajacki`, copied from the platform's `PRODUCTION_OWNERS` |
| **How testers get the staging APK**: repository access, or for example a private Telegram group (one more step) | repository access |
| **First version number** | `VERSION_PREFIX: '1.0'` |
| **Forced update**, per release | Promote's `force` input, default `no` (`docs/app-update.md`, default 1) |
| **Promote while the production door is missing or down** | Promote fails before anything is published (default 4) |
| **Staging with no staging door token** | the `door` job warns and skips; the staging pre-release still appears |

## 9. Evidence, prerequisites, and what is not proven

**Run on 2026-10-05:**

In WSL, with a fresh copy of `feat/app-login` (`08e8aae`, Firebase already removed) as `/root/src/ci-probe`, a fresh `HOME`
(empty Go build cache) and `taskset -c 0,1`. The scripts were throwaway, outside the repository. That tree still had
FlClash's id, so the packages in the table are `com.follow.clash(.dev)`; the last two rows check the guard with the new id.

| What | Result |
|---|---|
| Cold build, three ABIs, staging define `SHIKOO_API=https://staging-probe.invalid` (FlClash entry point by mistake) | exit 0, 1,146 s, three APKs of 52.1, 51.7, 53.7 MB |
| Same tree, Shikoo entry point, arm64, staging (no `keystore.jks`) | exit 0, 154 s: `com.follow.clash.dev`, versionCode 2007, staging URL in `libapp.so` once, `app.chopon.uk` zero times |
| Same tree, `keystore.jks` + three `local.properties` keys (a **copy of the machine's existing debug key**, so no new key was made), arm64 | exit 0, 134 s: `com.follow.clash`, staging URL zero times, `app.chopon.uk` once |
| Same, two ABIs, as the workflow does | exit 0, 153 s: `com.follow.clash` 1007 and 2007 |
| `libclash.so` sha256 of both variants, arm64 | identical, `b8b1a1a0…` |
| `tools/check_apk_clean.sh` on the five APKs of the first build | `OK` five times, exit 0 |
| The staging job's guard loop, with the old `.dev`-suffix package check at the time, on the two arm64 APKs, then on the staging APK renamed as production | PASS, then refused: `is com.follow.clash.dev and carries the staging server 1 times` |
| Promote's sha256 filter and `sha256sum -c`, on dummy files, then after changing one | two lines, OK; then `FAILED`, refused |
| The CI commit-message and comment-density steps on a throwaway clone of `main` | a good subject passes and `Fixed stuff` is refused; a file with 5 comments in 30 added lines is refused (16.7 %) |
| The signer guard (2026-10-06): production signed like staging; then production re-signed with a throwaway key made in a temp directory and deleted; then staging only | refused (`not signed by one release key of their own`); PASS; PASS |
| The server and bot guard on `https://app-dev.chopon.uk/` + `shikoodevbot`, `https://APP.chopon.uk/`, and `@ShikooNet_Bot` | allowed as `https://app-dev.chopon.uk`; refused; refused |
| The same step in WSL (GNU grep 3.11) on `git archive … lib/shikoo` of `feat/app` `7978755`, where `dart format` puts `'SHIKOO_BOT',` on the line after `String.fromEnvironment(`, then of `233a58d`, which has no `SHIKOO_BOT` | the old one-line `grep -F` failed both with no message; the per-file `grep -zP` passes `7978755` and refuses `233a58d` (`lib/shikoo does not read SHIKOO_BOT from the build`) |
| `actionlint` 1.7.12 with `shellcheck` 0.11.0 on the three workflows | exit 0 (one `SC2012` fixed on the way) |
| `flutter test` on 2 CPUs | 399 s, one failure: `NetworkDetection provider ignores a canceled stale check after a newer check succeeds`; the file alone passed three times (2 CPUs twice, all CPUs once), so it is a timing flake under load, in FlClash's tests |
| The guard loop (2026-10-06), cut from the workflow at `5f8c445` (old: `.dev` suffix) and with the exact id, on v7a APKs from `feat/app` local builds: a staging build named as staging; the same named as production; a build without the staging server named as production | both: PASS; refused (`is com.shikoonet.app.dev and carries the staging server 1 times`); refused (`… 0 times`) |
| `tools/publish_door.sh` (2026-10-06) in WSL Ubuntu 24.04 (its curl 8.5.0; jq 1.7.1, the official binary) against a throwaway door on `127.0.0.1:18797` that implements the upload contract, with two 50–52 MB staging APKs, sent in 8 MiB chunks; the door wrote the third chunk of each file (offset 16 MiB) and then answered 502 once | exit 0; the log shows that chunk `502` then `200` for both files; `POST /dl/publish` 200; the door's files pass `sha256sum -c` against `SHA256SUMS` |
| The same door: an offset past the upload; one wrong hash in `SHA256SUMS`; the same release with `force=true`; a wrong token; empty `force` | `409 {"error": "offset", "size": 207}`; exit 22 after `422 {"error": "sha256", "file": …}` and `update.json` unchanged; `min_version_code` = `version_code` for both ABIs; exit 22 on `401`; `::error::force must be true or false` |
| The token in that run: all script output, including two runs under `bash -x`, and the door's log | 0 lines each; no header file left behind |
| The same script, unchanged, against the real door of shikoo-platform PR #700 (WP1), run by the verifier on 2026-10-06: a publish; a wrong sha256; a wrong token; a swapped ABI; a chunk sent twice | as the contract says: published; 422 with the manifest unchanged; 401; the swapped ABI case as expected; the repeated chunk harmless |
| The same two guards where only the package can tell: FlClash's official `com.follow.clash` (sha256 `9a507336…a122a`) named as production; FlClash's WSL debug build named as staging, with `API=chen08209`, a string its `libapp.so` holds 4 times | old: PASS, PASS. Exact id: refused (`is com.follow.clash and carries the staging server 0 times`); refused (`is com.follow.clash.dev and carries the staging server 4 times`) |

**Prerequisites before this can merge green:**
- **The Shikoo app itself on `main`.** `main` (`f08a9fd`) has no `lib/shikoo/` at all, so `-t lib/shikoo/app/main.dart`
  cannot build there. The app is on `feat/app` (in WSL `/root/src/shikoo-phone`) and must be merged first, with the commit that
  sets `applicationId = "com.shikoonet.app"` (`cf8089b` in WSL on 2026-10-06, not yet on GitHub, so its hash may change):
  without it every staging run fails the package guard.
- `tools/check_apk_clean.sh` and the Firebase removal (`chore/remove-firebase`) on `main`; the CI `apk` job and staging call it.
- `lib/shikoo/engine/settings.dart` reading the bot from `String.fromEnvironment('SHIKOO_BOT', defaultValue: 'shikoonet_bot')`
  (flutter-engineer); staging refuses to build until it does. `SHIKOO_API` already exists on `feat/app-login`.

**Not proven:**
- None of the three workflows has run on GitHub. The minutes and times above are from WSL pinned to 2 CPUs, not from a runner.
- That two release builds with a real, different release key sign with it: the probe's "release" key was a copy of the debug
  key, so the signer looked the same either way; only the package name showed which path Gradle took. Sam's keystores are
  PKCS12 under a `.jks` name; Gradle on JDK 17 opens either format by default, but no build has signed with one yet.
- The flaky `NetworkDetection` test may turn a 2-CPU runner red now and then; rerun the job, and report it upstream if it
  keeps happening.
- That the runner's preinstalled clang and libclang serve the Rust hook's bindgen. FlClash's own release job builds Android on
  `ubuntu-latest` with the same steps, which is the reason to expect it.
- That `gh workflow disable` is kept across a FlClash merge that rewrites `build.yaml`.
- The new version in the User-Agent against the panel (§5).
- The door (`docs/app-update.md`, WP1) is shikoo-platform PR #700, not yet merged or deployed; the script met it only in the
  verifier's run above, never on a deployed door (`app-dev.chopon.uk`, `app.chopon.uk`). Upload speed from a GitHub runner to the
  door's host is unmeasured. A failing request is retried five times
  even when it is a 401 or 422, so such a failure takes about half a minute to show.
