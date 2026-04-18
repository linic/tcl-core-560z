# Why the cs4236 hacks make sound work on the ThinkPad 560Z

This document explains, change by change, *why* the modifications in
`cs4237b/` allow the ALSA sound driver to bring up the CS4237B chip on a
ThinkPad 560Z, when the upstream driver fails with:

```
cs4236+ chip detected, but control port 0xffffffff is not valid
```

It is written as a reference for a later, cleaner Kconfig-based
integration of the fix.

---

## 1. What the CS4237B actually exposes on the 560Z

The CS4237B datasheet (which is in `cs4237b/CS4237B.PDF` in the repo)
documents four logical PnP devices that a fully-wired board can expose:

| EISA ID   | Logical device                    |
| --------- | --------------------------------- |
| `CSC0000` | Windows Sound System + SBPro      |
| `CSC0001` | Game port                         |
| `CSC0010` | **Control port (C0..C8 regs)**    |
| `CSC0003` | MPU-401 (MIDI)                    |

On the ThinkPad 560Z, only **`CSC0000`** and **`CSC0001`** exist. The
debug dump the author added to the driver confirms this:

```
iter->id->id=CSC0000, iter->name=CS00      <- WSS port (works)
iter->id->id=CSC0001, iter->name=CS01      <- game port
(no CSC0010)                                <- control port missing
(no CSC0003)                                <- MPU-401 missing
```

**This is the root cause.** The stock `snd-cs4236` driver assumes that
`CSC0010` is present because it contains the control registers (`C0`
through `C8`) that the driver uses for master volume, SPDIF output,
3D effects, wavetable control, and — critically — a *version check*.
On the 560Z that device simply does not exist; the BIOS never creates
it. The "quick boot" BIOS setting is sometimes blamed, but disabling it
on the 560Z does not make `CSC0010` appear. The 560Z schematic simply
does not wire the control-register ISAPNP resource.

Everything the hacks do follows from this single fact.

---

## 2. What goes wrong in the stock driver

Walk through what the stock code does during a probe:

1. `snd_cs423x_pnpbios_detect()` is called when the PnP layer finds
   `CSC0000`.
2. It builds a sibling-ID string by copying `pdev->id[0].id` and
   overwriting the last character with `'1'` — so `CSC0000` becomes
   `CSC0010`.
3. It walks the PnP device list looking for a device whose first ID
   matches that `CSC0010`. On the 560Z the loop finishes with
   `cdev == NULL`.
4. `snd_card_cs423x_pnp(dev, acard, pdev, cdev)` is called. Since
   `cdev == NULL`, the `else` branch sets `cport[dev] = -1`.
5. `snd_cs423x_probe()` is entered, which calls `snd_cs4236_create()`
   with `cport = -1`.
6. `snd_cs4236_create()` runs the line:
```c
   if (cport < 0x100 || cport == SNDRV_AUTO_PORT) {
       dev_err(card->dev, "please, specify control port for CS4236+ chips\n");
       return -ENODEV;
   }
```
   This is the first place it would bail out — **but** on the 560Z
   there is also a user-space path where someone passes `cport=0xffff`
   as a module parameter in a last-ditch attempt. That makes it past
   this check, and then:
7. The driver does a two-read version comparison:
```c
   ver1 = snd_cs4236_ctrl_in(chip, 1);   /* reads cport + 3/4 */
   ver2 = snd_cs4236_ext_in(chip, CS4236_VERSION);   /* reads wss port I23/X25 */
   if (ver1 != ver2) {
       dev_err("CS4236+ chip detected, but control port 0x%lx is not valid\n", cport);
       return -ENODEV;
   }
```
   The read from the non-existent control port returns `0xff` (open-bus),
   so `ver1 = 0xff`. The WSS-side extended read returns `0xe8`
   (`Revision E`, chip ID `01000` = CS4237B). They disagree, the
   driver logs the famous error message, and the probe is aborted.

Everything after this never gets a chance to run: no PCM, no mixer, no
DMA, no interrupts, no sound.

---

## 3. The hacks, grouped by *why* they are there

There are four *kinds* of change in the patches. It helps to separate
them because (a) only the first kind is strictly necessary, and (b)
the clean Kconfig rewrite can keep most of the rest out of the shared
code.

### 3.a — Kind 1: Required for sound to work on the 560Z

These are the changes without which the probe will always fail. They
all stem from "there is no control port."

| File                 | Change                                                              | Why it is needed                                                    |
| -------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------- |
| `cs4236.c`           | Stop building a `cid` and searching for `CSC0010` in the PnP list.  | `CSC0010` is never there on the 560Z; the loop is wasted work.      |
| `cs4236.c`           | `snd_card_cs423x_pnp()` no longer takes a `cdev` argument.          | There is no cdev to pass; removing the parameter removes confusion. |
| `cs4236.c`           | `snd_cs423x_probe()` does not check `cport[dev] == SNDRV_AUTO_PORT`. | That check forced a `-EINVAL` before probe could continue.          |
| `cs4236.c`           | `snd_cs4236_create()` is called without `cport[dev]`.               | Propagates from the signature change in `cs4236_lib.c`.             |
| `cs4236_lib.c`       | `snd_cs4236_create()` no longer takes `cport` and does not validate it. | Removes the `"please, specify control port"` early-out.              |
| `cs4236_lib.c`       | `snd_cs4236_create()` does **not** compare `ver1 = ctrl_in(1)` with `ver2 = ext_in(CS4236_VERSION)`. | Removes the `"control port 0x%lx is not valid"` early-out.           |
| `cs4236_lib.c`       | `snd_cs4236_create()` does not write default values to `C0..C8`.    | Those writes would go to an invalid I/O range — undefined behaviour. |
| `cs4236_lib.c`       | `snd_cs4236_suspend()` / `snd_cs4236_resume()` no longer snapshot or restore `C2..C8`. | The registers do not exist. Reading is harmless, writing is not.    |
| `cs4236_lib.c`       | `snd_cs4236_put_iec958_switch()` no longer toggles `C4` bits.       | Same reason.                                                        |
| `cs4236_lib.c`       | `snd_cs4236_get_singlec()` / `snd_cs4236_put_singlec()` do not access `cimage`. | `cimage` is the software shadow of the non-existent control regs.   |
| `wss.h`              | `cport`, `res_cport`, `cimage[16]` removed from `struct snd_wss`.   | Fields only used by the code above — now dead.                      |
| `wss.h`              | `snd_wss_create()` signature drops `cport`.                         | Propagates.                                                         |
| `wss_lib.c`          | `snd_wss_create()` no longer requests `res_cport` or stores `cport`. | Propagates.                                                         |

**The minimum viable fix** is *only* the above. Without touching
any other WSS behaviour, the CS4237B on the 560Z will come up and
play sound through the main WSS-side volume/mixer registers.

### 3.b — Kind 2: Simplifications that happen to be safe on the 560Z

These changes are in `wss_lib.c` and `cs4236_lib.c`. They delete code
paths that are unreachable on the 560Z's hardware, so removing them does
not break the 560Z — **but they do break every other board that uses
the same file**. That is why they must not go into shared code in the
clean rewrite.

| File        | Removed/simplified code           | Why it is safe on the 560Z *only*                                       |
| ----------- | --------------------------------- | ----------------------------------------------------------------------- |
| `wss_lib.c` | All `WSS_HW_AD1848_MASK` branches | The 560Z is a CS4237B, not an AD1848/CS4248.                            |
| `wss_lib.c` | `WSS_HW_INTERWAVE` branches       | The 560Z is not an InterWave.                                           |
| `wss_lib.c` | `WSS_HW_AD1845` branches          | The 560Z is not an AD1845.                                              |
| `wss_lib.c` | `WSS_HW_OPTI93X` branches         | Not applicable.                                                         |
| `wss_lib.c` | `WSS_HW_OPL3SA2` branches         | Not applicable.                                                         |
| `wss_lib.c` | `WSS_HW_CS4235` / `CS4239` formats clamp | Not applicable; CS4237B supports more formats.                   |
| `wss_lib.c` | `thinkpad_flag`, `snd_wss_thinkpad_twiddle()` | The 560Z is *not* one of the 360/750/755 machines that needed a magic enable bit on `0x15e8`/`0x15e9`. It is detected as a genuine `WSS_HW_CS4237B`, not `WSS_HW_THINKPAD`. |
| `wss_lib.c` | `single_dma` branches             | The 560Z advertises dma1=1, dma2=3 — two channels.                       |
| `wss_lib.c` | `snd_ad1848_probe()`              | Only called from `snd_wss_probe()`; on the 560Z we bypass that path anyway. |
| `wss_lib.c` | `snd_wss_probe()` hardware-detection loop | Author hard-coded `hardware = WSS_HW_CS4237B` and verified the X25 read matches `0x08 | revE`. |

### 3.c — Kind 3: Readability / documentation

These are zero-functional-change edits that make the driver easier
to understand:

- Renaming local variables (`reg` → `index_register_address`,
  `timeout` → descriptive names, etc.).
- Adding very detailed block comments quoting the CS4237B datasheet
  register tables inline (I8, I14, I15, I16, I23, I25, I28).
- Extracting `snd_wss_wait_delay()` so that `snd_wss_wait()` and
  `snd_wss_dout()` share one wait loop instead of duplicating it.
- Splitting `decode_version()` out of the probe so the chip-ID and
  silicon-revision decode has one well-commented home.
- Adding a named constant `WSS_IA01234_MASK` (`0x1f`) for the 5 least-
  significant bits of the Index Address Register R0.

These are good — keep them — but do them in the *new* module so the
original stays pristine.

### 3.c.1 — `dev_dbg` → `dev_err` switch

`switch-dev_dbg-to-dev_err.sh` converts every `dev_dbg` call in the
source to `dev_err`, to force debug messages into the kernel log
without needing `DEBUG` or dynamic debug. This is useful during
bring-up but should not ship enabled by default. In the clean rewrite
this is either reverted or wrapped in a CONFIG_SND_CS4237B_DEBUG-style
toggle.

### 3.d — Kind 4: Behavioural questions flagged by the author

The author marked several places with `TODO` comments indicating things
they were unsure about. These deserve follow-up before upstreaming:

1. **TRD bit in R0 during `snd_wss_mce_up/down`.** `chip->mce_bit`
   is OR'd into the value written to R0, but R0 also contains TRD
   (Transfer Request Disable). The current code might toggle TRD on
   each MCE write. Sound works on the 560Z, so either TRD toggling
   is harmless here or by luck lands on the right value. This needs
   a careful read-modify-write using `WSS_IA01234_MASK` and an explicit
   preservation of the upper bits.

2. **`snd_wss_capture_format()`: the `!PLAYBACK_ENABLE` guard.**
   The author copied the MCE-up / MCE-down sequence into the capture
   path but flagged it as suspicious — the original code did
   `mce_down → mce_up` between writing the playback and record
   format only if playback was already running. Worth re-reading
   the datasheet section on "Playback Mode Change Enable (PMCE)"
   and "Capture Mode Change Enable (CMCE)" in I16.

3. **`chip->image[CS4231_REC_FORMAT]` not updated in
   `snd_wss_capture_format()`.** Pre-existing bug? Or intentional
   because the shadow is updated elsewhere?

4. **Register fill loop in `snd_wss_probe()`.** Writes all 32
   indirect registers from `chip->image`. Author suspects many are
   redundant; datasheet confirms some are read-only or reserved.

5. **`mdelay(2)` after the register fill.** Unknown origin. Possibly
   belt-and-suspenders.

These should be investigated but do **not** block the clean rewrite —
they are pre-existing questions about the original driver that the
author is now in a better position to answer.

---

## 4. What "it works" looks like

After the patched module loads, running:

```
sudo alsactl init CS4237B
alsamixer   # bring Master and PCM to ~100
sudo alsactl store CS4237B
mpg123 some.mp3
```

produces audible playback. After a reboot, `alsactl init` + `alsactl
restore` are required again; without them the default register values
from the BIOS-programmed chip leave the output attenuators in a state
where nothing comes out of the speaker. The sticky-after-reboot part
is an ALSA userland story, not a kernel bug.

---

## 5. One-sentence summary for the commit message

> On the 560Z the CS4237B only exposes the WSS PnP device (`CSC0000`),
> not the separate Control PnP device (`CSC0010`), so the stock
> `snd-cs4236` driver errors out in version-check-against-control-port;
> a sibling driver that uses only WSS-side access (and lacks the
> features that require the control port, principally S/PDIF) probes
> cleanly and gives working PCM playback/capture.
