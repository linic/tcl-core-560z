# Plan: reorganizing the CS-family ISA drivers for readability

This document is the fourth and last deliverable of the CS4237B
clean-driver work. The first three (`01-why-the-hacks-make-it-work.md`,
`02-menuconfig-plan.md`, and the new `sound/isa/cs4237b/` module
itself) get the 560Z working without touching shared kernel code.
This one is forward-looking: it describes how the CS-family drivers
under `sound/isa/cs423x/` and the shared `sound/isa/wss/` library
could be reorganized later — once the new module is proven and the
560Z is in production — to make them easier to understand, easier
to maintain, and easier to extend to the next "weird" board.

The goal here is *not* to land another big patch. It is to record a
direction so that when an opportunity to push improvements upstream
appears (a kernel cycle with low CS4236 turbulence, a bored ALSA
maintainer, a new board surfacing the same control-port problem),
there is a coherent plan to reach for instead of starting from
scratch.

---

## 0. Where things stand after this branch lands

After the `cs4237b-clean-driver-wip` branch is merged:

- `sound/isa/cs4237b/` exists as a standalone module that handles
  the no-control-port case via WSS-side registers only.
- `sound/isa/cs423x/` (the stock `snd-cs4232` / `snd-cs4236` driver)
  is **unchanged**.
- `sound/isa/wss/` (the shared `snd-wss-lib`) is **unchanged**.
- All the readability improvements, TRD-bit notes, capture-format
  questions, and probe-loop simplifications that exist in the
  legacy `cs4237b/source-*` patch tree remain unmerged.

This is the right place to be: nothing fragile is shipping, and the
shared code that other boards depend on is untouched. The work below
can then be done at leisure, one piece at a time.

---

## 1. Splitting `cs4236.c` into per-chip files

### 1.a Why

Today `sound/isa/cs423x/cs4236.c` and `cs4236_lib.c` cover seven
chip variants:

| WSS_HW symbol      | Marketing name | Distinguishing features                              |
| ------------------ | -------------- | ---------------------------------------------------- |
| `WSS_HW_CS4232`    | CS4232 / 4232A | Older WSS+OPL3+MPU401, no extended registers         |
| `WSS_HW_CS4235`    | CS4235         | Crystal Clear stereo enhancement, 3D space           |
| `WSS_HW_CS4236`    | CS4236         | Like 4232 + extended (eimage) registers              |
| `WSS_HW_CS4236B`   | CS4236B        | Adds control port (cimage), no 3D                    |
| `WSS_HW_CS4237B`   | CS4237B        | Adds 3D enable + space + center + mono + IEC958 out  |
| `WSS_HW_CS4238B`   | CS4238B        | Like 4237B but QSOUND-style 3D                       |
| `WSS_HW_CS4239`    | CS4239         | Like CS4235                                          |

The current code dispatches on `chip->hardware` inside the create
function, the mixer-init function, and the suspend/resume handlers.
Reading the file requires holding all seven variants in your head at
once, even though most boards out there only ever use one.

The 560Z work has already shown that pulling one variant out into
its own file produces something that is *much* easier to read:
`sound/isa/cs4237b/cs4237b_lib.c` is ~700 lines and one variant,
versus ~1000 lines and seven variants for the upstream file.

### 1.b Proposed layout

```
sound/isa/cs423x/
├── cs423x_common.c     <- shared helpers (rate constraint,
│                          divisor_to_rate_register, the generic
│                          ext-register save/restore, etc.)
├── cs423x_common.h
├── cs4232.c            <- CS4232 / CS4232A
├── cs4235.c            <- CS4235 / CS4239
├── cs4236.c            <- CS4236 / CS4236B (extended regs, no 3D)
├── cs4237b.c           <- CS4237B *with* control port
├── cs4238b.c           <- CS4238B
└── Kconfig + Makefile  <- one CONFIG_SND_CS<n> per file
```

(`sound/isa/cs4237b/` from this branch keeps existing as the
no-control-port variant. There is no conflict: `cs423x/cs4237b.c`
would be the *with*-control-port driver — different module name,
different Kconfig symbol.)

### 1.c Coexistence rules

- Each per-chip module registers a PnP id table containing only the
  EISA IDs known to identify that chip. The current
  `snd_cs423x_pnpids` mega-table can be split by chip after
  cross-referencing each entry against the comment that names the
  silicon (already half-done in the existing source).
- The variant-specific control sets (3D for 4237B, output_accu for
  4235, IEC958 for 4237B/4238B) live in their respective per-chip
  files — no more `if (chip->hardware == WSS_HW_CS4237B)` branches.
- The shared helpers (`*_info_single`, `*_get/put_single`,
  `*_get/put_double`, `cs423x_xrate`, etc.) move to
  `cs423x_common.c` and are exported with a `cs423x_` prefix so
  every per-chip module can pull them in via `EXPORT_SYMBOL`.

### 1.d Migration plan

Land the split incrementally — never as one mega-patch:

1. Introduce `cs423x_common.{c,h}` containing only the shared
   helpers, exported. Existing `cs4236.c` / `cs4236_lib.c` keep
   their own (now duplicated) static copies. Build still works.
2. Switch `cs4236_lib.c` to use the shared helpers; delete the
   local copies. One commit.
3. Add `cs4237b.c` (with control port — separate module from the
   one in this branch). Move the 3D / IEC958 / cimage code from
   `cs4236_lib.c` into it. `cs4236.c` keeps the 4236/4236B path.
   `Kconfig` gets a new `SND_CS4237B_FULL` (or whatever name is
   bikesheddable) that selects this variant.
4. Repeat for `cs4238b`, `cs4235`, `cs4232`. Each step is its own
   commit, each compiles, each is reviewable on its own.
5. Remove the dispatch-on-`chip->hardware` code paths from
   `cs4236.c` once nothing reaches them anymore.

This is a multi-cycle effort. Doing it through the upstream ALSA
tree means each step gets one round of review before the next; doing
it as a fork would let it move faster but loses the review and
locks the project into carrying the diff forever.

---

## 2. Pushing `wss_lib.c` improvements upstream

The legacy patch in `cs4237b/source-*` contains a substantial set
of readability and structural improvements to `sound/isa/wss/wss_lib.c`:

- Renaming opaque locals to descriptive names (`reg`,
  `index_register_address`; nameless `timeout` counters; etc.).
- Inline block comments that quote the CS4237B datasheet register
  tables (I8, I14, I15, I16, I23, I25, I28) right next to the
  code that touches them.
- Extraction of `snd_wss_wait_delay()` so `snd_wss_wait()` and
  `snd_wss_dout()` share the wait loop.
- Splitting `decode_version()` out of the probe so the chip-id /
  silicon-revision decode has one well-commented home.
- A named constant `WSS_IA01234_MASK` (`0x1f`) for the 5 LSBs of
  the Index Address Register.

These are genuine improvements. They are also strictly *additions*
to readability — they do not change behaviour. As such they are
good candidates for landing upstream through the ALSA mailing list
without a compatibility story attached.

### 2.a What does *not* belong in this set

The other category of `wss_lib.c` changes from the legacy patch —
the deletions of `WSS_HW_AD1848_MASK` / `WSS_HW_INTERWAVE` /
`WSS_HW_AD1845` / `WSS_HW_OPTI93X` / `WSS_HW_OPL3SA2` /
`WSS_HW_THINKPAD` branches, the removal of `snd_ad1848_probe()`,
the simplified `snd_wss_probe()` with hard-coded
`hardware = WSS_HW_CS4237B` — must NOT be sent upstream. Those
delete code paths that other boards rely on. They were 560Z-only
simplifications, useful as a "is the residual driver minimal?"
exercise but unsafe as a real change.

A useful intermediate is to mark them in the patch series with
`/* 560Z-only: reachable code path on every other WSS board */`
comments, so a future reader doing the same exercise on a different
board does not start by deleting them again.

### 2.b Process

ALSA changes go through `alsa-devel@alsa-project.org` and
`linux-sound@vger.kernel.org`, with Takashi Iwai as the primary
maintainer for `sound/isa/`. The expected sequence:

1. Rebase the readability-only commits from `wss_lib.c` onto a
   recent mainline (`linus/master`).
2. Split into one logical change per commit: rename pass, comment
   pass, helper extraction, named constant. Five-ish commits, each
   with a one-paragraph rationale.
3. Send the series with `git send-email` to the lists above with
   `[PATCH 1/5] ALSA: wss_lib: ...` style subjects.
4. Address review (likely a request to drop or rework some of the
   comment churn — the kernel style guide is allergic to
   block-comment walls).
5. Once merged, those commits flow into the next stable kernel,
   which the tinycore-560z build picks up automatically without
   carrying a fork.

This is a "next quarter" task at the earliest. The 560Z build does
not need any of these changes to work.

---

## 3. Investigating the behavioural-question TODOs

Doc `01-why-the-hacks-make-it-work.md` §3.d lists five open
questions the original author flagged in the patch with `TODO`
comments. With the clean driver in place, they can be revisited
without the pressure of "is the 560Z working?":

1. **TRD bit preservation in `snd_wss_mce_up/down`**. Currently
   `chip->mce_bit` is OR'd into the value written to R0, but R0
   also carries TRD (Transfer Request Disable). The fix is a
   read-modify-write using `WSS_IA01234_MASK` and explicit
   preservation of the upper bits. Test: load on a 560Z, capture
   register state across MCE up/down with an analyzer, confirm TRD
   remains stable.
2. **`snd_wss_capture_format()`'s `!PLAYBACK_ENABLE` guard**.
   Re-read the datasheet sections on PMCE and CMCE in I16; build a
   small test that triggers playback+capture format changes in
   every order and verifies no audible artifact.
3. **`chip->image[CS4231_REC_FORMAT]` not updated in
   `snd_wss_capture_format()`**. Almost certainly a latent
   upstream bug; worth a 3-line patch with a Fixes: tag.
4. **Register fill loop in `snd_wss_probe()`**. The loop writes
   all 32 indirect registers from `chip->image` at probe time;
   datasheet says some are read-only or reserved. Worth a
   per-register audit and a comment-annotated "minimum necessary"
   list.
5. **Origin of the `mdelay(2)` after the register fill**. Likely
   belt-and-suspenders. Bisect-style: try removing it on a 560Z
   and a 4236B board, see if anything breaks.

These all flow through `alsa-devel`, same process as §2.b.

---

## 4. Optional: probe-ordering for cleaner coexistence

`02-menuconfig-plan.md` §4.d documents the current coexistence
behaviour: both `snd-cs4236` and `snd-cs4237b` register a PnP
match for `CSC0000`, and whichever loads first wins. The user
makes the choice deterministic with a `modprobe.d` blacklist.

A cleaner alternative — proposed there but punted to here:

> Add a probe-ordering mechanism where `snd-cs4237b` only binds if
> `snd-cs4236` has already failed for the same device.

This would be a module parameter on `snd-cs4237b`:

```
modparam: only_if_no_cdev=1   (default 0)
```

When set, `snd_cs4237b_pnpbios_detect()` would scan the PnP
device list for a sibling `CSC0010`, and return `-ENODEV` if one
is present. That lets `snd-cs4236` handle every "normal" board it
can, and `snd-cs4237b` only steps in when the control device
genuinely is not exposed.

The implementation is straightforward — the existing stock driver
already has the sibling-search code, which we deliberately removed
from the clean driver but could re-add behind this module
parameter. It is not necessary for the 560Z (the blacklist works),
but it is the right behaviour for a driver shipped in a generic
distro kernel where the user has not configured a blacklist.

---

## 5. Suggested sequencing

A reasonable order to attack the work above:

1. **Now (this branch)**: ship the no-control-port driver.
   Production-deploy it on the 560Z, run for a few weeks, confirm
   no regressions. (Done by this branch + the
   `02-menuconfig-plan.md` §6 build wiring.)
2. **+1 month**: send the `wss_lib.c` readability-only series to
   `alsa-devel`. Iterate on review.
3. **+2-3 months**: add the `only_if_no_cdev=1` module parameter
   to `snd-cs4237b` and propose the new module upstream as a
   sibling driver. Use the production deployment as evidence of
   stability. (See HANDOFF.md "One open item.")
4. **+6 months**: start the per-chip split of `sound/isa/cs423x/`.
   Land it incrementally over a couple of cycles.
5. **Opportunistically**: address the §3 behavioural-question
   TODOs whenever there is a compelling test case or a regression
   report that intersects with one of them.

Nothing in this list blocks anything else in this list — they can
all be picked up independently when time permits.

---

## 6. What is deliberately *not* in this plan

- **Forward-porting the legacy `wss_lib.c` deletions** as-is.
  Section 2.a covers why; the short version is "they break every
  other board".
- **Renaming the upstream `snd-cs4236` module** or otherwise
  disturbing the existing build for users who do not have a 560Z.
  All proposals here are additive: new files, new options,
  per-chip splits with the old monolith staying functional until
  every variant has migrated.
- **Removing `cport`/`res_cport`/`cimage[]` from `struct snd_wss`**.
  This was done in the legacy patch but breaks ABI for every
  board with a working control port. Keep the fields; let the
  no-control-port driver simply not touch them.
