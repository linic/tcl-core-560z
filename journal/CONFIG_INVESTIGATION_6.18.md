# Config Investigation — kernel 6.18.24

Branch: `config-investigation-6.18`
Goal: Read `.config-6.18` end-to-end and produce a categorised list of options that are candidates for disabling, while keeping the 560Z's load-bearing subsystems (networking, sound, video, hard drive, USB) functional. Output is a reviewable markdown document that linic can use as input to a future `make menuconfig` slimming pass — no `.config` edits in this branch.

This file is the journal for that investigation, per the `TRY_YOUR_BEST_SHOT.md` protocol.

## Starting point

- Branch was forked from `cs4237b-clean-driver-wip` at commit `338381a` (`cs4237b: STATUS.md — compile succeeded, built-in findings`).
- `.config-6.18` is 3152 lines, 945 `CONFIG_*` lines: 865 `=y`, 2 `=m`, 78 numeric/string, 1373 `# ... is not set`. Mostly built-in; very few modules.
- Current release baseline (`release/6.18.24.17.2/`): `bzImage` 3.8 MiB, `core.gz` 3.7 MiB.
- 560Z hardware envelope (from `README.md`, `CLAUDE.md`, prior memory):
  - Pentium II (MMX, no SSE/SSE2/AVX); ~64 MB RAM; Intel 430TX chipset.
  - ISA + PCI; CS4237B (ISA PnP) sound; PCMCIA/CardBus; USB 1.x UHCI (PIIX4).
  - IDE/ATA hard drive (no SATA, no NVMe, no SCSI hardware).
  - On-board video — NeoMagic NM2160 (assumption, to confirm if it matters for the investigation).
  - Networking is **always external**: USB→Ethernet (Realtek 8152), or USB/PCMCIA wifi (`rtl8192cu` mentioned in README).
- Kernel build is overwhelmingly `=y` (built-in), so anything disabled here goes straight to bzImage size, not module size. Disabling a `# is not set` line has no effect — it is already off.

## Plan

Phased — each phase ends with one commit appending findings to this journal (or a sibling file under `journal/`). Lowest risk first.

- [x] Phase 0 — Journal scaffold. Commit this file.
- [x] Phase 1 — Inventory pass. `.config-6.18` read end-to-end, every section tagged Required / Useful / Surface / Already-good in `journal/CONFIG_INVENTORY_6.18.md`. (this commit)
- [x] Phases 2–6 — Architectural / subsystem / debug / security / FS analyses. Folded directly into the inventory tags (`Required` / `Useful` / `Surface` / `Already-good`) and into the synthesis. The original plan called for separate per-area files; that turned out to be premature decomposition. The inventory + the synthesis are the right level of granularity for a report-only branch.
- [x] Phase 7 — Synthesis. `journal/CONFIG_DISABLE_CANDIDATES_6.18.md` — three buckets (A/B/C) plus a Don't-touch keep-list and a suggested order of operations for a future menuconfig pass.
- [x] Phase 8 — Close-out. This commit. Open items below.

## Log

- 2026-04-28 — Phase 0: branch `config-investigation-6.18` created off `cs4237b-clean-driver-wip`. Journal scaffold committed. No `.config` changes in this branch.
- 2026-04-28 — Phase 1: full inventory in `journal/CONFIG_INVENTORY_6.18.md`. Key takeaways: the config is already very lean (one of the leanest mainline `=y` configs I've seen for x86) — most of the cheap wins are already taken (no SMP, no HIGHMEM, no DRM, no FTRACE, no KASAN, no IO_URING, no KALLSYMS, `-Os`, SLUB_TINY). The remaining size budget lives in: BPF/perf/tracing scaffolding, namespaces, the asymmetric-crypto subtree pulled in by signed-regdb, AES-NI dead code, and a handful of dma-buf / NVMEM / sound-of-the-art helpers that are referenced by nothing.
- 2026-04-28 — Phases 2–7: synthesised into `journal/CONFIG_DISABLE_CANDIDATES_6.18.md`. Three buckets: A (high-confidence dead code), B (probably safe, verify on boot), C (big-ticket conditional trades — signed regdb being the largest single knob). Don't-touch keep-list at the end.
- 2026-04-28 — Phase 8 close-out. This commit. No `.config` was modified in this branch; the deliverable is two markdown files under `journal/`.

## Clarifying questions for linic

Numbered so you can reply "Q3: option b" without ambiguity. Best guess included so the AI can default if you don't get to it before the usage window closes.

**Q1.** Is the goal "smaller bzImage on disk" (boot media space), or "less RAM at runtime" (more headroom for `init`), or both? They overlap heavily but not perfectly — e.g. trimming `=m` modules saves disk but not boot-time RAM, while trimming `=y` saves both.
- Best guess: **both, with runtime RAM as the primary motivation** (the README explicitly says the 560Z hits init-OOM on stock TCL).

**Q2.** "Video" on the must-keep list — does that mean *framebuffer console + Xorg-able display* (i.e. the 560Z can run the desktop the way `tools/desktop.sh` expects), or just text console? They imply different keep-sets (DRM/fbdev/efifb vs. just VGA/VT).
- Best guess: **framebuffer console + whatever Xorg's `vesa`/generic driver needs**. No KMS/DRM hard requirement on a NeoMagic chip from 1998.

**Q3.** "Networking" — must we keep both the on-PCMCIA-card wireless path *and* the USB-Ethernet path? Or is USB-Ethernet the only really-supported path now and PCMCIA wireless is a nice-to-have?
- Best guess: **keep both for now**, since `rtl8192cu` and PCMCIA show up in `tools/` scripts and existing `*-modules-*.tcz` artifacts. Mark PCMCIA wireless as a candidate to revisit if we need to claw back more space later.

**Q4.** Are you OK with this investigation producing **only** a markdown report (no `.config` edits, no menuconfig session, no rebuild)? The TRY_YOUR_BEST_SHOT framing suggests yes, but I want to confirm before I leave a branch with zero `.config` deltas.
- Best guess: **yes, report-only is the deliverable for this branch**; the actual `.config` edit lives in a future branch where you can drive `make menuconfig` interactively.

**Q5.** For Phase 5 (security/namespaces/cgroups): TinyCore *itself* doesn't use namespaces or cgroups, but `extensions` you load might (e.g. some Docker-ish extensions). Should I treat namespaces/cgroups as "safe to disable" or "verify with what extensions you actually use"?
- Best guess: **safe to disable on a 560Z** — you've never mentioned running containerised workloads on the 560Z, and the RAM budget would not allow it anyway.

**Q6.** `# CONFIG_INPUT_EVDEV is not set`. Modern Xorg uses `evdev` to read `/dev/input/event*`. With evdev off, the desktop relies on the legacy `INPUT_MOUSEDEV` (`/dev/input/mice`) + AT keyboard interface. Does the 560Z desktop currently work without `evdev`, or has nobody noticed because everything you launch in `tools/desktop.sh` happens to use the legacy interfaces?
- Best guess: **it works because TCL's Xorg is configured for legacy mouse/kbd, not evdev.** Worth verifying though.

**Q7.** `# CONFIG_USB_STORAGE is not set` and `# CONFIG_HID_SUPPORT is not set`. Both are intentional, I assume — but worth confirming. Disabling USB-storage means no install-from-USB-stick; disabling HID means no USB keyboards/mice/joysticks.
- Best guess: **both intentional**, given how lean the rest of the config is. Just flagging.

**Q8.** SQUASHFS compressors enabled: `ZLIB`, `LZ4`, `ZSTD`. Which compressors do the `.tcz` files you actually use require? Stock TCL has historically been zlib/gzip; some newer builds use LZ4. ZSTD on `.tcz` would be unusual. If ZSTD is unused, dropping `SQUASHFS_ZSTD` plus the underlying `ZSTD_DECOMPRESS`/`ZSTD_COMMON` is a real win.
- Best guess: **drop ZSTD**, keep ZLIB+LZ4.

**Q9.** The biggest single trade is C1: drop `CONFIG_CFG80211_REQUIRE_SIGNED_REGDB`. Are you OK shipping an unsigned regdb file on the 560Z? It removes the entire asymmetric-crypto subtree (RSA/DH/ECC/X.509/PKCS7) from the kernel. This is the highest-impact knob in the whole report.
- Best guess: **yes, fine for a personal box on a known network**. But this is the most consequential decision — wouldn't dare flip it without your sign-off.

**Q10.** Does the 560Z run with PCMCIA wifi at all in your current setup, or has it been USB-only for a while? `# CONFIG_PCCARD is not set` already, so the kernel can't do PCMCIA today — just wanting to confirm that's intentional and not something I should re-add.
- Best guess: **USB-only is fine** — the README's recent sections all reference USB-Ethernet and `rtl8192cu` (which is USB-attached).

## Decisions made without input (record of assumptions)

(Empty so far. Each unilateral call lands here as the analysis proceeds, with a one-line reason and a note on reversibility.)

## Things out of scope / left alone

- No `.config-6.18` edits in this branch. Edits happen in a future branch via `make menuconfig`.
- No rebuild / no boot test — those need the 560Z and are out of this session's scope anyway.
- No changes to `cs4237b/`, the trim pipeline, or any tools.
- `.config-4`, `.config-5`, `.config-6` are not analysed. The 6.18 line is the live one; older lines are kept for historical comparison only.
- No analysis of which `=m` modules to drop from the `*-modules-*.tcz` packaging. That's a separate problem (disk size of `.tcz`, not bzImage size).
