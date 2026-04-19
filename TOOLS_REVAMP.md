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

- **Q1-Q7 in this doc** need linic's input for final polish.
- **Phase 3 end-to-end validation** on the 560Z.
- **Q5 (CIP naming)**: the current fallback works; if you prefer renaming `patches-4.4.302-cip97` to `patches-4` we should also adjust `cs4237b/generate-patches.sh` and rerun it.
- **Phase 2b (usage/main skeleton in build-all.sh and make-bzImage-modules-tczs.sh)**: not a correctness issue, but matches the rust-i586 style.

---

## Log (what I completed, in order)

- `2026-04-18` — Wrote this journal, reviewed state, posted clarifying questions. No code changes yet.
- `2026-04-18` — Phase 1 fixes: `common.sh` bash-array lines removed; `[ -lt 18 ]`; `triplet_separator` now exports `MAJOR/MINOR/PATCH`; `get_suffix` uses those and returns non-zero on bad input. `pick-config.sh`: unquoted glob, propagate `get_suffix` failure. `pick-patches.sh`: fix `$PATCH_DIR` → `$PATCHES_DIR`, unquoted glob, add CIP fallback to `patches-$KERNEL_VERSION`. `make-bzImage-modules-tczs.sh`: call `pick-config.sh $KERNEL_VERSION` instead of `$KERNEL_BRANCH`. Smoke-tested pick-config/pick-patches in /tmp with all three cases (6.18.8, 6.12.65, 4.4.302-cip97) and they all picked the correct suffix and cleaned up siblings.
- `2026-04-18` — Phase 2a: added `quintuplet_separator`, `cip_number_check`, `resolve_kernel_urls` helpers to `common.sh`. Migrated `download-kernel.sh`, `make-bzImage-modules-tczs.sh`, `build-all.sh` to use them — the ~50 lines of IFS/digit-check/URL-building boilerplate is now shared. Variable names also unified: `TCL_MAJOR_VERSION_NUMBER`/`ITERATION_NUMBER` → `TCL_MAJOR`/`ITERATION` in shell; docker env var names unchanged. Broken `[ ! filename ]` guards removed from `build-all.sh` (they were no-ops anyway). Smoke-tested the helpers with 6.12.65.17.1 and 4.4.302.16.1 +cip97.
- `2026-04-18` — Phase 3: new `tools/build-locally.sh`. Mirrors the `rust-i586` pattern: arg parsing (same shape as `build-all.sh` minus `TCL_DOCKER_IMAGE_VERSION`), stages the repo's `.config-*`, `cs4237b/patches/`, `tools/` and `cache/` into `/home/tc/{kernel_configs,cs4237b,tools,cache}` (no-op if already staged), exports `TCL_VERSION=$TCL_MAJOR.x` + `TCL_RELEASE_TYPE` so `package-core-gz.sh` can find them, then calls `tce-load-requirements.sh` and `make-bzImage-modules-tczs.sh`. Usage / bad-input paths smoke-tested on host; end-to-end run on the 560Z itself is out of reach from this workspace (Q2/Q3 expected to confirm scope).

### Decisions made without input from linic (Phase 3)

- **Q2 scope:** produces the same artifacts as the Docker build (bzImage + .tcz modules + core-<ver>.gz in `release/<ver>/`). Reused all existing helper scripts so behaviour should match `build-all.sh` / `make-bzImage-modules-tczs.sh`.
- **Q3 args:** `VERSION_QUINTUPLET TCL_RELEASE_TYPE CORE_GZ LOCAL_VERSION [CIP_NUMBER]`. Dropped `TCL_DOCKER_IMAGE_VERSION` (Docker-only). `TCL_VERSION` is derived from the quintuplet (`TCL_MAJOR.x`).

### Decisions made without input from linic (Phase 1)

- **Q5 CIP naming:** did *not* rename `patches-4.4.302-cip97` → `patches-4`. Instead made `pick-patches.sh` fall back to `patches-$KERNEL_VERSION` when the suffix-based dir isn't found. This is reversible and keeps the CIP-specific name visible. If you'd rather rename (option 5a), easy follow-up.
- **Q7 globals:** went ahead with exporting `MAJOR/MINOR/PATCH` from `triplet_separator`. Necessary to fix the current broken `get_suffix`. Reversible.

---

## Clarifying questions for linic

Please answer any you want me to respect. I'll proceed on the ones I'm confident about in the meantime and flag decisions I made unilaterally in the **Log** section above each commit.

**Q1. pick-config.sh / pick-patches.sh input API.**
Currently `make-bzImage-modules-tczs.sh` calls `pick-config.sh $KERNEL_BRANCH` (e.g. `v6.x`) and `pick-patches.sh $KERNEL_VERSION` (e.g. `4.4.302-cip97`). The rewritten scripts expect a triplet. Do you want both scripts to take the same thing (I'd pick `$KERNEL_VERSION` for uniformity), or keep them different?

**Q2. build-locally.sh scope.**
Should it produce the same set of artifacts the Docker build produces (bzImage + alsa/ipv6-netfilter/net/parport/pcmcia/usb/wireless tczs + core.gz + md5 files) in a local release/ directory? Or just bzImage + modules in `/home/tc` so you can test boot it manually?

**Q3. build-locally.sh args.**
Match `build-all.sh`: `VERSION_QUINTUPLET TCL_RELEASE_TYPE core.gz|rootfs.gz LOCAL_VERSION TCL_DOCKER_IMAGE_VERSION [CIP_NUMBER]`? Or simpler?
(Defaults I'd pick: yes to all args except `TCL_RELEASE_TYPE` which is only needed for publish, and except `TCL_DOCKER_IMAGE_VERSION` which is meaningless without Docker.)

**Q4. `.config-<suffix>` mapping.**
`get_suffix` today maps: `4 → 4`, `5 → 5`, `6 & minor<18 → 6`, `6 & minor≥18 → 6.18`. Is that the forever rule, or will more `.config-6.N` variants appear? I'll keep the current rule unless you say otherwise.

**Q5. CIP patches dir naming.**
We have `cs4237b/patches/patches-4.4.302-cip97/` but `source-4/` and `.config-4`. The revamp's `get_suffix` returns `4` for any 4.x, so the patch lookup will miss. Options:
  a) rename the patches dir to `patches-4` (matches source/config),
  b) add a `source-4.4.302-cip97` symlink (keeps the CIP info in the name), or
  c) make `get_suffix` return `4.4.302-cip97` when CIP is given.
I'd go with (a) — simplest, parallel to `source-4`.

**Q6. Shell dialect.**
Stick to `#!/bin/sh` (POSIX) everywhere? Or is it OK to switch scripts that need arrays to `#!/bin/bash`? I'd stay POSIX; Tiny Core's default is busybox ash.

**Q7. `triplet_separator` globals.**
OK to let it export `MAJOR/MINOR/PATCH` as shell globals (no `local` in POSIX sh)? That's the cleanest way to propagate parsed parts back to callers.

---

## Decisions I made unilaterally (record of assumptions)

- (none yet; will append as I go)

---

## Things out of scope / left alone

- `cs4237b/switch-dev_dbg-to-dev_err.sh`, `cs4237b/generate-patches.sh` — not in `tools/`.
- `Dockerfile*`, `docker-compose*.yml` — only touching where needed for revamped scripts.
- Behaviour of what the scripts actually *build* — this revamp is purely about the shell infrastructure.
