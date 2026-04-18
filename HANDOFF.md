# CS4237B clean-driver rewrite — handoff summary

## 1. Initial context

The user maintains [`linic/tcl-core-560z`](https://github.com/linic/tcl-core-560z),
a build pipeline that produces a custom Tiny Core Linux kernel + modules
for an IBM/Lenovo ThinkPad 560Z. The 560Z has a Cirrus Logic CS4237B
sound chip, and the stock upstream `snd-cs4236` driver fails on it with:

```
cs4236+ chip detected, but control port 0xffffffff is not valid
```

The user has been maintaining a working fix as a heavy patch against
`sound/isa/cs423x/cs4236.c`, `sound/isa/cs423x/cs4236_lib.c`,
`include/sound/wss.h`, and `sound/isa/wss/wss_lib.c`. The patch lives in
`cs4237b/` in the repo, with variants for kernel versions 4.4, 5.10, 6.x,
and 6.18.8.

The user asked for four deliverables:

1. **Document *why* the hacks make sound work.**
2. **Plan a proper `menuconfig` / `Kconfig` option** so the fix doesn't
   require patching shared files.
3. **Start file changes** so the fix can coexist cleanly with the
   existing driver.
4. **Plan a reorganization of the CS-family drivers** for readability.

The user then requested these be placed on a new branch named
`cs4237b-clean-driver-wip`, with small incremental commits. The GitHub
MCP connector turned out not to be available in this chat environment,
so all files were dumped into the conversation instead.

## 2. What has been done so far

### Research & understanding

- Cloned the repo and read every patch variant (~2,200 lines of diff
  across 4 kernel versions).
- Read the Dockerfile, `make-bzImage-modules-tczs.sh`, and all tools
  scripts to understand the current build/patch flow.
- Downloaded upstream `sound/isa/Kconfig`, `sound/isa/cs423x/Makefile`,
  and `sound/isa/wss/Makefile` from `torvalds/linux` and identified
  every in-tree driver that uses `SND_WSS_LIB` (confirming why the
  current approach breaks other drivers).
- Identified the **root cause in one sentence**: on the 560Z the
  CS4237B only exposes the WSS PnP logical device (`CSC0000`), not
  the separate Control PnP logical device (`CSC0010`). The stock
  driver assumes `CSC0010` is always present and errors out when it
  isn't. Everything in the patch set follows from this.

### Files produced (dumped in the previous chat turn)

| Path in repo                                      | Status   | Contents                                                                                                                                                                     |
| ------------------------------------------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `cs4237b/docs/01-why-the-hacks-make-it-work.md`   | Complete | Root-cause explanation; stock-driver probe walk-through; classification of every change in the current patch into 4 categories (required / 560Z-only-safe / readability / TODOs). |
| `cs4237b/docs/02-menuconfig-plan.md`              | Complete | Full design for a standalone `sound/isa/cs4237b/` module with its own `CONFIG_SND_CS4237B` (and optional `CONFIG_SND_CS4237B_DEBUG`). Covers Kconfig, Makefile, source-file structure, coexistence with `snd-cs4236`, migration path for the tinycore build, 7-point test plan. |
| `cs4237b/src/sound/isa/cs4237b/Kconfig`           | Complete | Kernel-tree-ready Kconfig file with two config symbols and full help text.                                                                                                   |
| `cs4237b/src/sound/isa/cs4237b/Makefile`          | Complete | Kernel-tree-ready Makefile.                                                                                                                                                  |

### Key design decisions that are now locked in

- **New sibling module, not a patch.** The new driver lives in
  `sound/isa/cs4237b/`, compiled as `snd-cs4237b.ko`. Zero modifications
  to `wss_lib.c`, `wss.h`, or any shared file.
- **Exploits existing library behaviour.** `snd_wss_create()` already
  handles `cport < 0` (skips `devm_request_region()` on the control
  port). No library change is needed — pass `-1`.
- **Coexistence strategy.** Both `snd-cs4236` and `snd-cs4237b` can be
  loaded simultaneously; first to bind wins. Documented blacklist
  recipe for deterministic behaviour on the 560Z.
- **Scope of the new driver.** PCM playback/capture, WSS-side mixer,
  FM synthesis, microphone/line in. **Not** included: SPDIF/IEC958,
  hardware 3D effects, wavetable serial-port toggling — these all
  require the absent control port.

## 3. What's left to do

### Remaining source files (C code)

- **`cs4237b/src/sound/isa/cs4237b/cs4237b.h`** — private header.
  Declares `snd_cs4237b_create()`, `snd_cs4237b_pcm()`,
  `snd_cs4237b_mixer()`. Pulls in `<sound/wss.h>`; does not redeclare
  `struct snd_wss`.
- **`cs4237b/src/sound/isa/cs4237b/cs4237b_lib.c`** — simplified
  descendant of `cs4236_lib.c`. Core function `snd_cs4237b_create()`
  calls `snd_wss_create(card, port, -1, irq, dma1, dma2,
  WSS_HW_DETECT3, 0, &chip)`. Mixer registers only WSS-side controls.
  `suspend`/`resume` save/restore `chip->image[]` and `chip->eimage[]`
  only (no `cimage[]`).
- **`cs4237b/src/sound/isa/cs4237b/cs4237b.c`** — PnP/ISA probe stub.
  `MODULE_ALIAS("snd-cs4237b")` only (does **not** claim `snd_cs4232`).
  PnP ID table contains only `{ "CSC0000", 0 }`. Probe calls
  `snd_cs4237b_create()` with `cport = -1` directly — no sibling-ID
  lookup.

### Integration patches (small, one-line each)

- **`cs4237b/src/integration-patches/sound-isa-Kconfig.patch`** — adds
  a single `source "sound/isa/cs4237b/Kconfig"` line inside `if SND_ISA`
  in `sound/isa/Kconfig`.
- **`cs4237b/src/integration-patches/sound-isa-Makefile.patch`** — adds
  a single `obj-$(CONFIG_SND_CS4237B) += cs4237b/` line to
  `sound/isa/Makefile`.

### The fourth deliverable

- **`cs4237b/docs/03-cs-family-reorganization.md`** — plan for
  eventually splitting `cs4236.c` into per-chip files (CS4232, CS4235,
  CS4236, CS4236B, CS4237B-with-ctrl, CS4238B, CS4239), plus a section
  on pushing the `wss_lib.c` readability improvements upstream through
  the ALSA tree rather than carrying them as a fork.

### Build-pipeline changes (after source files land)

- Update `tools/make-bzImage-modules-tczs.sh` to drop `patch-cs4236.sh`
  and instead copy `sound/isa/cs4237b/` into the kernel tree and apply
  the two one-line integration patches. Details in
  `02-menuconfig-plan.md` section 6.
- Update `.config-v6.x` to add `CONFIG_SND_CS4237B=m` alongside
  `CONFIG_SND_CS4236=m`.
- Ship an `/etc/modprobe.d/cs4237b-560z.conf` with
  `blacklist snd_cs4236`.

### Known investigation items (tracked, not blocking)

From TODO comments in the existing patch — worth revisiting once the
clean driver is in place:

1. TRD-bit preservation during `snd_wss_mce_up/down`.
2. `snd_wss_capture_format()`'s `!PLAYBACK_ENABLE` guard semantics.
3. `chip->image[CS4231_REC_FORMAT]` not being updated in the capture
   path — possible latent bug in upstream.
4. Whether the full-register fill loop in `snd_wss_probe()` is
   necessary or vestigial.
5. Origin of the `mdelay(2)` after register fill.

## 4. How to use the generated files to complete the work

### Step 1: Save what's in the chat

Four files were dumped as the previous turn. Put them in your local
clone on branch `cs4237b-clean-driver-wip`:

```
git clone git@github.com:linic/tcl-core-560z.git
cd tcl-core-560z
git checkout -b cs4237b-clean-driver-wip
mkdir -p cs4237b/docs cs4237b/src/sound/isa/cs4237b
# paste each of the four files from chat into:
#   cs4237b/docs/01-why-the-hacks-make-it-work.md
#   cs4237b/docs/02-menuconfig-plan.md
#   cs4237b/src/sound/isa/cs4237b/Kconfig
#   cs4237b/src/sound/isa/cs4237b/Makefile
git add cs4237b/docs cs4237b/src
git commit -m "cs4237b: add design docs and new-module Kconfig/Makefile scaffold (WIP)"
git push -u origin cs4237b-clean-driver-wip
```

### Step 2: Hand off to Claude Code

From inside the repo directory on the same branch, start a Claude Code
session. Prompt it with something like:

> Read `cs4237b/docs/01-why-the-hacks-make-it-work.md` and
> `cs4237b/docs/02-menuconfig-plan.md`. They describe the current state
> of a clean-driver rewrite for the CS4237B sound chip on the ThinkPad
> 560Z. The Kconfig and Makefile for the new module exist at
> `cs4237b/src/sound/isa/cs4237b/`. Please:
>
> 1. Write `cs4237b/src/sound/isa/cs4237b/cs4237b.h` per section 4.a of
>    the plan.
> 2. Write `cs4237b/src/sound/isa/cs4237b/cs4237b_lib.c` per section
>    4.b of the plan. Base it on the *original* upstream
>    `sound/isa/cs423x/cs4236_lib.c` in Linux 6.18.8 (fetch from
>    kernel.org), not on the patched version in `cs4237b/source-6.18.8/`
>    — we want to start clean, not inherit the wss_lib-coupled edits.
>    Apply the "kind 1" changes from `01-why-the-hacks-make-it-work.md`
>    section 3.a. Do not apply the "kind 2" changes (those belong in a
>    future shared-library cleanup, not here).
> 3. Write `cs4237b/src/sound/isa/cs4237b/cs4237b.c` per section 4.c.
> 4. Write the two integration patches under
>    `cs4237b/src/integration-patches/`. Both should be one-line
>    additions; generate them against upstream Linux 6.18.8 with
>    `diff -u`.
> 5. Commit each file as its own commit on the current branch.
> 6. After all source files compile, write
>    `cs4237b/docs/03-cs-family-reorganization.md` covering the fourth
>    deliverable in the handoff summary.
>
> Do not modify `sound/isa/wss/wss_lib.c`, `include/sound/wss.h`, or
> `sound/isa/cs423x/*` in any of this work — that is the whole point of
> the rewrite.

### Step 3: Build and test

After the files are in place:

```
# From a kernel build tree with the driver dropped in:
make menuconfig   # verify the new entry appears under ISA sound devices
make              # verify it compiles, as =m and as =y
# On a 560Z:
modprobe snd-cs4237b
alsactl init CS4237B
alsamixer         # Master + PCM to ~100
alsactl store CS4237B
aplay /usr/share/sounds/alsa/Front_Center.wav
```

The 7-point test plan in `02-menuconfig-plan.md` section 7 expands on
this.

### Step 4: Integrate into the tinycore-560z build

Once upstream-style changes work, wire the new workflow into the Docker
build per `02-menuconfig-plan.md` section 6. That's the point where
this branch merges to `main` and the old patch-driven approach can be
retired (but kept in the repo history for reference).

---

**One open item for your next session:** decide whether to submit the
new driver upstream to the ALSA mailing list. Nothing in this handoff
requires it, but once the driver is proven clean and non-invasive, it's
a candidate — you'd be the first person in 25 years to get a working
in-tree CS4237B driver for this class of 560Z-like board.
