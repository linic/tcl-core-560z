# tools/ revamp journal

Branch: `improving_compile_scripts`

Goal: less duplication, more functions, use of return values — following the same spirit as `/home/code/mes-repertoires-git/rust-i586/tools/build-locally.sh`. End goal: a `build-locally.sh` that can be invoked from inside a booted Tiny Core Linux to rebuild kernel + modules + tczs on the 560Z itself (no Docker).

---

## State of the revamp (starting point, last 4 commits)

Last 4 commits on `improving_compile_scripts`:

- `b18fd35` reorganized source and patches — to be continued
- `bc51b13` simplifying .config and patches picking — to be improved and tested
- `2ae5c5c` reorganized patches — to be tested
- `13723ba` patch for 6.18.8 — to be tested

### What already landed

- `.config-v4.x / v5.x / v6.x` renamed to `.config-4 / -5 / -6`, and `.config-6.18` added (suffix-based naming).
- `cs4237b/` reorganised: `source-<ver>` alongside `patches/patches-<ver>` directories; `generate-patches.sh` writes into `patches/patches-<ver>`.
- `Dockerfile` now `COPY .config-* …` and `COPY cs4237b/patches/` (wildcard copy, no per-version lines).
- `tools/common.sh` grew two helpers:
  - `check_is_digit` (existed, now returns 1 on error instead of `$1`).
  - `triplet_separator` — splits version strings with IFS=".-" and validates digits.
  - `get_suffix` — maps a triplet to the `.config-<suffix>` / `patches-<suffix>` suffix.
- `tools/pick-config.sh` and `tools/pick-patches.sh` rewritten with `usage() / pick_*() / main()` pattern, sourcing `common.sh`, using `get_suffix`.
- `tools/download-kernel.sh` (new) follows the `usage/main` pattern.
- `tools/make-bzImage-modules-tczs.sh` updated to call `pick-patches.sh $KERNEL_VERSION` and `patch-cs4236.sh` (no arg).

### Known bugs / rough edges in the current state

The revamp is only partially wired up. Things I already spotted reading the code:

1. **`common.sh`: bash-isms in a `#!/bin/sh` script.**
   `triplet_separator` uses `OLD_PARAMS=("$@")` (bash array) and later `"${old_params[@]}"` (also lowercase — typo). In ash/dash these will error. Both lines are dead (nothing reads the saved params); safe to delete.

2. **`common.sh`: `[ $2 < 18 ]` is wrong.**
   In `[ ]`, `<` is shell redirection, not a numeric compare. Needs `[ "$2" -lt 18 ]`.

3. **`common.sh`: `triplet_separator` does not propagate parsed digits back.**
   `set -- $KERNEL_VERSION` inside a function sets that function's positional params, not the caller's. So after `triplet_separator "$@"` returns to `get_suffix`, `$1` in `get_suffix` is still the whole version string (e.g. `6.18.8`) — and the `case $1 in 4|5|6)` never matches. `get_suffix` appears to work by coincidence (returns the empty SUFFIX for unknown → error path) but it never actually picks a suffix.
   Fix: have `triplet_separator` set globals (e.g. `MAJOR=$1 MINOR=$2 PATCH=$3`) and have `get_suffix` use those.

4. **`pick-config.sh` / `pick-patches.sh`: quoted glob never expands.**
   `rm -rvf ".config-*"` (literal filename) and `rm -rvf "patches-*"` (literal dir). Need unquoted `rm -rvf .config-*` / `rm -rvf patches-*`.

5. **`pick-patches.sh`: variable name mismatch.**
   Sets `PATCHES_DIR="patches-$SUFFIX"` then runs `mv -v "$PATCH_DIR" "patches"` (singular — undefined). Rename to one form.

6. **`make-bzImage-modules-tczs.sh` still calls `pick-config.sh $KERNEL_BRANCH`** (old `v4.x`/`v5.x`/`v6.x` interface) but the rewritten `pick-config.sh` expects a full triplet. Either update the call site or make pick-config accept both.

7. **`build-all.sh` top-of-file `if [ ! file ]` guards are all broken** — `[ ! <non-empty-string> ]` is always false regardless of file existence. These need `[ ! -f file ]` / `[ ! -d dir ]`. Low urgency (they silently always pass), but noisy noise.

8. **`build-all.sh` + `make-bzImage-modules-tczs.sh` duplicate ~50 lines of arg validation** (IFS split + digit-check loop). Candidate for a `quintuplet_separator` (or a generic `split_and_validate`) in `common.sh`.

9. **CIP naming asymmetry:** patches dir is `patches-4.4.302-cip97` but config is `.config-4`. `get_suffix` returns `4` for any 4.x, so the config lookup works; but `pick-patches.sh` will try `patches-4` and not find it (dir is `patches-4.4.302-cip97`). Needs either a separate lookup for CIP or a symlink. See Q5 below.

---

## Plan of what's missing

Ordered roughly by dependency / risk:

### Phase 1 — fix the existing partial revamp so it runs (quick, safe)

- [x] Write this journal.
- [x] Fix `common.sh`: drop bash-array lines; fix `-lt 18`; make `triplet_separator` export `MAJOR/MINOR/PATCH`; make `get_suffix` use them.
- [x] Fix `pick-config.sh` glob + reflect `get_suffix` API.
- [x] Fix `pick-patches.sh` `$PATCH_DIR`/`$PATCHES_DIR` typo + glob + CIP-aware lookup (see Q5).
- [x] Fix `make-bzImage-modules-tczs.sh` call to `pick-config.sh` (pass `$KERNEL_VERSION`, not `$KERNEL_BRANCH`).
- [x] Replace broken `[ ! file ]` guards in `build-all.sh`.
- [x] Commit (`705eb08`).

### Phase 2 — deduplicate arg parsing (medium, safe)

- [x] Add `quintuplet_separator` to `common.sh` that sets `MAJOR MINOR PATCH TCL_MAJOR ITERATION` as globals.
- [x] Add `cip_number_check` helper to `common.sh`.
- [x] Add `resolve_kernel_urls` helper to `common.sh`.
- [x] Migrate `build-all.sh`, `make-bzImage-modules-tczs.sh`, `download-kernel.sh` to those helpers.
- [ ] **(2b — not done)** Fold the `usage / <verb> / main` skeleton into `build-all.sh` and `make-bzImage-modules-tczs.sh`. They're now shorter but still top-level imperative. This is cosmetic and can wait.
- [x] Commit (`4cd7f5f`).

### Phase 3 — `build-locally.sh` (new)

- [x] New `tools/build-locally.sh`, modelled on `rust-i586/tools/build-locally.sh`.
- [x] Reuses `tce-load-requirements.sh`, `pick-config.sh`, `pick-patches.sh`, `patch-cs4236.sh`, `build-modules-tcz.sh`, `compress-modules.sh`, `edit-modules-dep-order.sh`, `package-core-gz.sh` by chaining through `make-bzImage-modules-tczs.sh`.
- [x] Commit (`f59a322`).
- [ ] **End-to-end run on a booted 560Z** — I can't do this from this workspace. This is the remaining validation work.

### Phase 4 — tidy (optional, not done)

- [ ] Refresh copyright headers from 2025 to 2026 on `build-all.sh`, `build-modules-tcz.sh`, `edit-config.sh`, `make-bzImage-modules-tczs.sh`, `package-core-gz.sh`, `publish.sh`, `trim.sh` (only touched `build-all.sh` and `make-bzImage-modules-tczs.sh` in this revamp; didn't want to churn files I didn't otherwise modify).
- [ ] `trap '…' ERR` in `make-bzImage-modules-tczs.sh` and `package-core-gz.sh` is a bashism — POSIX sh has no ERR trap. Pre-existing, not introduced by this revamp. Worth cleaning up at some point.

## Open items / follow-ups

- **End-to-end build validation**: Nic is building in Docker on his Debian host (not on the 560Z). `make edit` failed because Phase 1 rename missed `Dockerfile.edit-config` and `edit-config.sh` — addressed in Phase 6.
- **Phase 2b (usage/main skeleton in build-all.sh and make-bzImage-modules-tczs.sh)**: not a correctness issue, matches the rust-i586 style — deferred by mutual agreement.
- **New branch for cross-repo build directory convention** (`/home/tc/<repo_name>/release/<version>/` and `/home/tc/<repo_name>/compile/<version>/`): agreed approach, deferred because it touches make-bzImage-modules-tczs.sh + Dockerfile + all three repos (tcl-core-560z, tcl-core-rust-i586, rust-i586) — deserves its own branch.

### Phase 7 — generate-patches.sh moved to tools/ (2026-04-24)

Moved `cs4237b/generate-patches.sh` → `tools/generate-patches.sh`.

Improvements:
- Sources `common.sh`; calls `get_suffix` to derive `SUFFIX` from the version triplet
- Source dir lookup: tries `source-$SUFFIX` first, falls back to `source-$1` (full version) if absent — mirrors the CIP fallback in `pick-patches.sh`
- Output dir: `patches/patches-$SUFFIX` (suffix-based, consistent with how `pick-patches.sh` and Dockerfile consume patches)
- Repeated 3-line `sed` header-normalization block extracted into `normalize_patch_header()`;  uses `|` as delimiter to avoid escaping `/` in paths
- `usage()` / `generate_patches()` / `main()` skeleton with `*.*.*)` arg guard
- Invocation from `cs4237b/`: `../tools/generate-patches.sh 6.18.8`

Design doc: `cs4237b/docs/generate-patches-design-v1.0.md`

---

### Phase 6 — catch-up: the other Dockerfile missed by Phase 1 (2026-04-24)

Symptom: `make` → `make edit` → `tools/edit-config.sh` fails at
`COPY --chown=tc:staff .config-v4.x ./.config-v4.x` (and v5.x, v6.x). Those files no longer exist after the Phase 1 rename.

Root causes:
1. `Dockerfile.edit-config` hardcodes the old v-prefixed config filenames.
2. `Dockerfile.edit-config` calls `pick-config.sh $KERNEL_BRANCH` (e.g. `v6.x`) — the rewritten script expects a triplet.
3. `Dockerfile.edit-config` does not COPY `tools/common.sh`, but pick-config.sh now sources it (added in Phase 1). Would fail at runtime even if the COPY issue were fixed.
4. `edit-config.sh` docker-cp's the edited config back as `./.config-v4.x` / `.config-v5.x` / `.config-v6.x` — old names. Also doesn't know about the `6.18` suffix split.

Fixes in this phase:
- [x] `Dockerfile.edit-config`: wildcard `COPY .config-* ./`, add `COPY tools/common.sh`, call `pick-config.sh $KERNEL_VERSION`.
- [x] `edit-config.sh`: after the CIP block, `get_suffix "$KERNEL_VERSION"` and docker-cp back as `.config-$SUFFIX`. Removes the old major-digit cascade and the broken old-name `[ ! .config-v6.x ]` no-op validation.
- [x] Commit (`6fccf12`).
- [x] Validated: `docker compose build` on `docker-compose.edit-config.yml` succeeded end-to-end for `6.18.24.17.1`. Build step 11/12 output confirmed `pick-config.sh 6.18.24` → suffix `6.18` → `.config-6.18` → `.config`, siblings cleaned up. Image `linichotmailca/tcl-core-560z-edit-config:6.18.24.17.1` built. The interactive `make oldconfig` / `make menuconfig` steps that `edit-config.sh` runs after the build still require Nic's TTY.

---

## Log (what I completed, in order)

- `2026-04-18` — Wrote this journal, reviewed state, posted clarifying questions. No code changes yet.
- `2026-04-18` — Phase 1 fixes: `common.sh` bash-array lines removed; `[ -lt 18 ]`; `triplet_separator` now exports `MAJOR/MINOR/PATCH`; `get_suffix` uses those and returns non-zero on bad input. `pick-config.sh`: unquoted glob, propagate `get_suffix` failure. `pick-patches.sh`: fix `$PATCH_DIR` → `$PATCHES_DIR`, unquoted glob, add CIP fallback to `patches-$KERNEL_VERSION`. `make-bzImage-modules-tczs.sh`: call `pick-config.sh $KERNEL_VERSION` instead of `$KERNEL_BRANCH`. Smoke-tested pick-config/pick-patches in /tmp with all three cases (6.18.8, 6.12.65, 4.4.302-cip97) and they all picked the correct suffix and cleaned up siblings.
- `2026-04-18` — Phase 2a: added `quintuplet_separator`, `cip_number_check`, `resolve_kernel_urls` helpers to `common.sh`. Migrated `download-kernel.sh`, `make-bzImage-modules-tczs.sh`, `build-all.sh` to use them — the ~50 lines of IFS/digit-check/URL-building boilerplate is now shared. Variable names also unified: `TCL_MAJOR_VERSION_NUMBER`/`ITERATION_NUMBER` → `TCL_MAJOR`/`ITERATION` in shell; docker env var names unchanged. Broken `[ ! filename ]` guards removed from `build-all.sh` (they were no-ops anyway). Smoke-tested the helpers with 6.12.65.17.1 and 4.4.302.16.1 +cip97.
- `2026-04-18` — Phase 3: new `tools/build-locally.sh`. Mirrors the `rust-i586` pattern: arg parsing (same shape as `build-all.sh` minus `TCL_DOCKER_IMAGE_VERSION`), stages the repo's `.config-*`, `cs4237b/patches/`, `tools/` and `cache/` into `/home/tc/{kernel_configs,cs4237b,tools,cache}` (no-op if already staged), exports `TCL_VERSION=$TCL_MAJOR.x` + `TCL_RELEASE_TYPE` so `package-core-gz.sh` can find them, then calls `tce-load-requirements.sh` and `make-bzImage-modules-tczs.sh`. Usage / bad-input paths smoke-tested on host; end-to-end run on the 560Z itself is out of reach from this workspace (Q2/Q3 expected to confirm scope).
- `2026-04-19` — linic answered Q1–Q7. Q2 (directory convention `/home/tc/<repo_name>/...`) agreed but deferred to new branch; Q5 (a) confirmed. Renamed all version-specific patch dirs to suffix-based names: `patches-4.4.302-cip97` → `patches-4`, `patches-5.10.235` → `patches-5`, `patches-6.18.8` → `patches-6.18` (`patches-6` already correct). Fixed bug in `make-bzImage-modules-tczs.sh`: cache-hit path used `.config-$KERNEL_BRANCH` (old v-prefixed name) instead of `.config-$SUFFIX`; added `get_suffix "$MAJOR.$MINOR.$PATCH"` call after `resolve_kernel_urls` and switched the `cp` to use `$SUFFIX`.
- `2026-04-24` — Phase 6 fix: `Dockerfile.edit-config` and `edit-config.sh` missed by Phase 1 — wildcard COPY for `.config-*`, COPY `common.sh` (pick-config.sh sources it since Phase 1), pass `$KERNEL_VERSION` to `pick-config.sh`, and docker-cp the edited config back as `.config-$SUFFIX`. Validated: `docker compose build` succeeded end-to-end for `6.18.24.17.1`.
- `2026-04-24` — Cosmetic: `make-bzImage-modules-tczs.sh` cache-miss echo still said "md5sum -c .config-$KERNEL_BRANCH.md5.txt" and "this .config-$KERNEL_BRANCH file" — misleading (wrong name, references old v-prefix). Changed to name the real file (`$CACHE/$KERNEL_VERSION/.config.md5.txt`) and use `$SUFFIX`. Informational only — does not affect build behaviour.
- `2026-04-24` — Diagnosis aid: `make build` for 6.18.24.17.1 failed at `make bzImage` (line 102) after ~26 min of compile. The script redirected output to `make.bzImage.log.txt` inside the Docker build layer, which is discarded on failure — so we had no visibility into the actual compiler error. Wrapped `make bzImage` in a failure branch that `tail -200`s the log to stdout so the Docker build output will show the real error on the next rebuild. Not a fix for the underlying build failure — only a visibility improvement so we can diagnose.
- `2026-04-24` — CS4237B driver port fixes for 6.18 (pre-existing bugs that were masked earlier by the invisible log). Edited `cs4237b/source-6.18.8/...` and regenerated patches via `cs4237b/generate-patches.sh 6.18.8` (then moved output to `patches-6.18/`). Four fixes: (1) `cs4236_lib.c` `snd_cs4236_get_singlec` — patch deleted the `chip`/`reg`/`shift` decls but left `guard(spinlock_irqsave)(&chip->reg_lock)` and `ucontrol->... chip->cimage[reg] >> shift ...` still referencing them (upstream converted to `guard()` between 6.12 and 6.18; patches-6 had cleanly deleted the spin_lock/unlock block); removed those two lines; (2) `wss_lib.c` `snd_wss_mce_down` — two stacked `while` loops with one `}` (old `while (wss_inb...)` left next to new `while (i0 & ...)`); deleted the stale one so brace balance is restored; (3) `wss_lib.c` `snd_wss_mce_up` — stray `timeout = wss_inb(chip, CS4231P(REGSEL));` referencing an undeclared `timeout`; deleted (the preceding line already captured the register); (4) `wss_lib.c` `snd_wss_suspend`/`snd_wss_resume` — still referenced `chip->thinkpad_flag` and `snd_wss_thinkpad_twiddle()` after both were removed from wss.h / the driver; deleted the calls (patches-6 had already dropped them). End-to-end `make build` completed cleanly: kernel built, 7 tczs + core.gz + bzImage copied to `release/6.18.24.17.1/` with `.md5.txt` files, cache populated at `cache/6.18.24/`. On-device boot test is pending (needs the physical 560Z, per CLAUDE.md).
- `2026-04-24` — Known issue in `cs4237b/generate-patches.sh`: `mkdir -pv patches-"$1"` (line 11) creates the dir in the wrong place (should be `patches/patches-$1`). The subsequent `diff > patches/patches-$1/...` lines fail unless the target dir already exists. Worked around manually (`mkdir -p patches/patches-<v>` + `rmdir` the stray top-level one). Not fixing here to keep this session tight — flag for a future small cleanup.
- `2026-04-24` — Phase 7: moved `cs4237b/generate-patches.sh` → `tools/generate-patches.sh`. Added `usage/generate_patches/main` skeleton, sourced `common.sh`, calls `get_suffix` for suffix-based output dir (`patches/patches-$SUFFIX`), suffix-first + full-version fallback for source dir lookup, extracted repeated `sed` normalization into `normalize_patch_header()` with `|` delimiter. Old file deleted. Design doc at `cs4237b/docs/generate-patches-design-v1.0.md`.

### Decisions made without input from linic (Phase 3)

- **Q2 scope:** produces the same artifacts as the Docker build (bzImage + .tcz modules + core-<ver>.gz in `release/<ver>/`). Reused all existing helper scripts so behaviour should match `build-all.sh` / `make-bzImage-modules-tczs.sh`.
- **Q3 args:** `VERSION_QUINTUPLET TCL_RELEASE_TYPE CORE_GZ LOCAL_VERSION [CIP_NUMBER]`. Dropped `TCL_DOCKER_IMAGE_VERSION` (Docker-only). `TCL_VERSION` is derived from the quintuplet (`TCL_MAJOR.x`).

### Decisions made without input from linic (Phase 1)

- **Q5 CIP naming:** did *not* rename `patches-4.4.302-cip97` → `patches-4`. Instead made `pick-patches.sh` fall back to `patches-$KERNEL_VERSION` when the suffix-based dir isn't found. This is reversible and keeps the CIP-specific name visible. If you'd rather rename (option 5a), easy follow-up.
- **Q7 globals:** went ahead with exporting `MAJOR/MINOR/PATCH` from `triplet_separator`. Necessary to fix the current broken `get_suffix`. Reversible.

---

## Clarifying questions for linic (answered 2026-04-19)

**Q1. ✓** Uniformize on `$KERNEL_VERSION` for both pick-config.sh and pick-patches.sh. Done in Phase 1.

**Q2. ✓ (deferred)** Convention: release files go to `/home/tc/<repo_name>/release/<version>/`, compilation files to `/home/tc/<repo_name>/compile/<version>/`. Apply to Docker builds too. Agreed — deferred to a new branch because it touches make-bzImage-modules-tczs.sh + Dockerfile + all three repos.

**Q3. ✓** `VERSION_QUINTUPLET TCL_RELEASE_TYPE CORE_GZ LOCAL_VERSION [CIP_NUMBER]` — no `TCL_DOCKER_IMAGE_VERSION`. Done in Phase 3.

**Q4. ✓** More `.config-6.N` variants may appear when cs4237b patches need updating for new kernel.org changes. `get_suffix` hardcodes known mappings; a new entry will be added when a new variant appears.

**Q5. ✓** Option (a): renamed all version-specific patch dirs to suffix-based names (`patches-4`, `patches-5`, `patches-6.18`). Extended to `patches-5.10.235` → `patches-5` and `patches-6.18.8` → `patches-6.18` (same principle, same inconsistency). `generate-patches.sh` should be called with the suffix (e.g. `4`) — `SOURCE="source-$1"` and `PATCH="patches/patches-$1"` then both resolve correctly.

**Q6. ✓** Keep `#!/bin/sh` POSIX throughout. busybox ash is the target.

**Q7. ✓** Globals (`MAJOR`/`MINOR`/`PATCH`) are fine. Done in Phase 1.

---

## Decisions made without input from linic (2026-04-19)

- **Q5 extended to all version-specific patch dirs:** Q5 asked specifically about `patches-4.4.302-cip97`. Also renamed `patches-5.10.235` → `patches-5` and `patches-6.18.8` → `patches-6.18` since they have the same inconsistency with the suffix convention. Reversible via git.

---

## Things out of scope / left alone

- `cs4237b/switch-dev_dbg-to-dev_err.sh` — not in `tools/`.
- `Dockerfile*`, `docker-compose*.yml` — only touching where needed for revamped scripts.
- Behaviour of what the scripts actually *build* — this revamp is purely about the shell infrastructure.
