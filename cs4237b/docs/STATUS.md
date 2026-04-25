# cs4237b — current status (handoff for next session)

Last updated: 2026-04-25

## Step 2 of HANDOFF.md: complete

All six tasks from `HANDOFF.md` §4 Step 2 prompt are done and committed
on branch `cs4237b-clean-driver-wip`. Working tree is clean.

```
4c68c63 cs4237b: add docs/03-cs-family-reorganization.md
978b7ed cs4237b: add integration patch for sound/isa/Makefile
c31c052 cs4237b: add integration patch for sound/isa/Kconfig
fa418ae cs4237b: add cs4237b.c (PnP/ISA bus glue)
125e49c cs4237b: add cs4237b_lib.c (chip create/PCM/mixer, no cport)
c0d0822 cs4237b: add private header for new module
```

The branch is **6 commits ahead of `origin/cs4237b-clean-driver-wip`**
and has **not** been pushed. Per `collaboration/COLLAB.md` §6, push
requires explicit confirmation from Nic.

Push command (when authorized):

```
HOME=/home/linic git -C /home/code/mes-repertoires-git/tcl-core-560z \
    push -u origin cs4237b-clean-driver-wip
```

## Files written this session

- `cs4237b/src/sound/isa/cs4237b/cs4237b.h` — private header
- `cs4237b/src/sound/isa/cs4237b/cs4237b_lib.c` — chip create / PCM /
  mixer; uses `snd_wss_create(..., cport=-1, ...)`; saves/restores
  `image[]` and `eimage[]` only (no `cimage[]`)
- `cs4237b/src/sound/isa/cs4237b/cs4237b.c` — PnP/ISA glue;
  `MODULE_ALIAS("snd-cs4237b")` only; PnP id table is `{ "CSC0000" }`
  only; no card-driver path (that requires CSC0010 sibling)
- `cs4237b/src/integration-patches/sound-isa-Kconfig.patch`
- `cs4237b/src/integration-patches/sound-isa-Makefile.patch`
- `cs4237b/docs/03-cs-family-reorganization.md`

Hard constraint observed: **zero modifications** to `wss_lib.c`,
`wss.h`, or anything under `cs423x/`.

## Step 4 of HANDOFF.md: build-pipeline integration — DONE (2026-04-25)

Build pipeline wired for the new clean-driver approach (branch merged from
main first):

- `Dockerfile`: copies `cs4237b/src/sound/isa/cs4237b/` → container
  `$CS4237B_PATCHES/sound-isa-cs4237b/` and `cs4237b/src/integration-patches/`
  → `$CS4237B_PATCHES/integration/`. Old `cs4237b/patches/` no longer copied.
- `tools/make-bzImage-modules-tczs.sh`: replaces `mv+pick-patches+patch-cs4236`
  with `cp -r sound-isa-cs4237b` + `patch -p1` for both integration patches.
- `tools/build-locally.sh`: same staging update for native-on-560Z builds.
- `.config-6.18`: `CONFIG_SND_CS4236=y` → `=m`, added `CONFIG_SND_CS4237B=m`.
- `Makefile`: ITERATION bumped to 2.

**Blocked on sudo**: `make build` uses `sudo docker compose`. Claude cannot
enter the sudo password in this workspace. Run `make build` from your terminal
to kick off the Docker build.

## Step 3 of HANDOFF.md: blocked on hardware

Compile + boot test on the 560Z is `Step 3` from HANDOFF.md and the
7-point test plan in `02-menuconfig-plan.md` §7. This requires Nic's
participation (the kernel build tree and the actual ThinkPad). Claude
cannot run this unilaterally.

## Step 4 of HANDOFF.md: build-pipeline integration

Once Step 3 passes on hardware, the next mechanical work is in
`02-menuconfig-plan.md` §6:

1. Update `tools/make-bzImage-modules-tczs.sh` — drop
   `patch-cs4236.sh`; instead copy `cs4237b/src/sound/isa/cs4237b/`
   into the kernel tree and apply the two integration patches.
2. Update `.config-v6.18` to add `CONFIG_SND_CS4237B=m`.
3. Ship `/etc/modprobe.d/cs4237b-560z.conf` with
   `blacklist snd_cs4236`.

These are independent of the hardware test — they could be drafted
ahead of time, but it's safer to wait until the source is proven
working, since the build script changes are the most disruptive
(they're what tinycore-560z users actually run).

## Open optional item

Submitting the new driver upstream to the ALSA list. See HANDOFF.md
final paragraph. Not blocking anything.
