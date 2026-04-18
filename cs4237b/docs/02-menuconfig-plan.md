# Plan: a dedicated Kconfig option for the 560Z CS4237B driver

## 0. Why we need this

Today the fix lives as a **diff against the shared `snd-cs4236` driver
and the shared `snd-wss-lib`**. That has two big problems:

1. **It breaks every other board using `wss_lib.c`.** Modifying
   `wss_lib.c` is not optional in the current layout — the library is
   linked by `snd-ad1848`, `snd-cs4231`, `snd-cs4236`, `snd-sc6000`,
   `snd-gusmax`, `snd-interwave`, `snd-opti9xx`, `snd-sscape`,
   `snd-azt1605`, `snd-azt2316`, `snd-cmi8328`, `snd-cmi8330`,
   `snd-miro`, plus more. Any change there is a lottery ticket for a
   regression on hardware you don't have.
2. **It can't coexist with the stock driver.** Every upgrade of the
   560Z build requires re-applying the patches. There is no way to
   pick the 560Z driver via `make menuconfig`.

What we want is: a standalone module `snd-cs4237b` (a descriptive name;
the 560Z is just the *first* board it happens to rescue) that:

- Has its own `CONFIG_SND_CS4237B` Kconfig entry, visible in `make
  menuconfig` under **Device Drivers → Sound → ALSA → ISA sound
  devices**.
- Compiles from its own source files under `sound/isa/cs4237b/`.
- Calls into **unmodified** `snd-wss-lib` via `snd_wss_create()` with
  `cport = -1` (which the existing library already supports).
- Does *not* touch `wss_lib.c`, `wss.h`, or any file shared with
  another driver.
- Can be selected as `=m` (module) or `=y` (built-in) independently.
- Can be loaded alongside `snd-cs4236`; first to bind wins for a given
  PnP device, and the user can blacklist the other to force the choice.

## 1. High-level design

```
sound/isa/
├── ad1816a/          <- unchanged
├── cs423x/           <- unchanged (snd-cs4231, snd-cs4236)
│   ├── cs4231.c
│   ├── cs4236.c
│   ├── cs4236_lib.c
│   ├── Makefile
│   └── Kconfig-fragment in ../Kconfig
├── cs4237b/          <- NEW
│   ├── cs4237b.c          (PnP/ISA stub, like cs4236.c but minimal)
│   ├── cs4237b_lib.c      (create/suspend/resume/mixer, no cport)
│   ├── cs4237b.h          (private header — only what this module needs)
│   ├── Documentation/
│   │   └── cs4237b.rst    (kernel-doc format)
│   ├── Makefile
│   └── Kconfig
├── wss/              <- unchanged
└── ...
```

The existing files under `cs423x/` and `wss/` are not modified at all.

## 2. Kconfig entries

### 2.a The new option

Add this to a new `sound/isa/cs4237b/Kconfig`:

```
# SPDX-License-Identifier: GPL-2.0-only

config SND_CS4237B
	tristate "Cirrus Logic CS4237B (no control port) driver"
	depends on PNP
	select ISAPNP
	select SND_WSS_LIB
	select SND_MPU401_UART
	help
	  Say Y or M here to include support for CS4237B chips on boards
	  where the separate "Control" PnP logical device (EISA ID
	  CSC0010) is not exposed by the BIOS.

	  The best-known example is the IBM/Lenovo ThinkPad 560Z, on
	  which the stock snd-cs4236 driver fails with:

	      cs4236+ chip detected, but control port 0xffffffff is not valid

	  This driver talks to the chip only through the WSS-side
	  registers and therefore works without CSC0010 being present.
	  As a consequence, features that live exclusively behind the
	  control port are NOT available:

	    * S/PDIF (IEC958) output
	    * Hardware 3D effects (3D Space / 3D Center / 3D Mono)
	    * Wavetable synthesis serial-port toggling (C8)

	  PCM playback, PCM capture, FM synthesis (if wired), mixer
	  volume, microphone in and line in all work.

	  If you also have CONFIG_SND_CS4236 enabled, only one of the
	  two modules can bind to a given card at a time. On boards
	  that do expose CSC0010 you probably want the stock driver;
	  on boards that do not, you want this one. Use modprobe.d
	  blacklist entries if necessary.

	  To compile this driver as a module, choose M here: the module
	  will be called snd-cs4237b.
```

Then include this sub-directory's Kconfig from the parent. Add the
line in the right alphabetical spot in `sound/isa/Kconfig`, inside
`if SND_ISA`:

```
source "sound/isa/cs4237b/Kconfig"
```

This is a **single-line addition** to a shared file; it does not
change any existing option. See `integration-patches/` for the diff.

### 2.b Optional debug sub-option

For developers continuing the investigation, add below the main entry:

```
config SND_CS4237B_DEBUG
	bool "Verbose debug output for CS4237B driver"
	depends on SND_CS4237B
	help
	  When enabled, the CS4237B driver logs detailed messages at
	  KERN_ERR level (not KERN_DEBUG, so they show up without
	  dynamic debug being turned on) covering:

	    * each register write during probe
	    * MCE up/down state transitions
	    * IRQ status decode
	    * chip version decode

	  Useful for bring-up on new boards; leave off for normal use.
```

This replaces the one-shot `switch-dev_dbg-to-dev_err.sh` in the
current workflow with a proper configuration knob.

## 3. Makefile entries

### 3.a New Makefile under `sound/isa/cs4237b/`

```
# SPDX-License-Identifier: GPL-2.0-only
#
# Makefile for the ALSA CS4237B (no-control-port) driver.
#

snd-cs4237b-y := cs4237b.o cs4237b_lib.o

obj-$(CONFIG_SND_CS4237B) += snd-cs4237b.o
```

### 3.b Parent Makefile

Add to `sound/isa/Makefile`:

```
obj-$(CONFIG_SND_CS4237B)        += cs4237b/
```

Again, a single-line addition — doesn't change any existing line.

## 4. Source files

### 4.a `cs4237b.h`

Private header. Declares:

```c
int snd_cs4237b_create(struct snd_card *card,
                       unsigned long port,
                       int irq, int dma1, int dma2,
                       struct snd_wss **rchip);

int snd_cs4237b_pcm(struct snd_wss *chip, int device);
int snd_cs4237b_mixer(struct snd_wss *chip);
```

We do **not** re-declare `struct snd_wss` — we include `<sound/wss.h>`.
That means the `cport`, `res_cport`, `cimage[]` fields are *present in
the struct* but we simply don't touch them. They take a few bytes of
memory per card; that's the whole cost of staying out of the shared
header. The upstream kernel has worse examples of driver-specific dead
fields.

### 4.b `cs4237b_lib.c`

A heavily simplified descendant of `cs4236_lib.c`:

- `snd_cs4237b_create()`: calls `snd_wss_create(card, port, -1, irq,
  dma1, dma2, WSS_HW_DETECT3, 0, &chip)`. `snd_wss_create()` already
  supports `cport < 0` and will skip `devm_request_region()` on the
  control port. No modification to `wss_lib.c` needed.
- After `snd_wss_create()` succeeds, read `CS4236_VERSION` via
  `snd_cs4236_ext_in()` (WSS-side access, works fine) and assert it's
  `(chip_id & 0x1f) == 0x08` (CS4237B).
- Mixer controls: use **only** `snd_cs4236_ext_in`/`_ext_out` (WSS-side
  indirect — works) and `snd_wss_out`/`_in` (WSS-side direct — works).
  The SPDIF controls, 3D controls, and wavetable-enable switch are
  simply not registered. This mirrors what the current patch does in
  effect.
- `snd_cs4237b_suspend`/`_resume`: save and restore `chip->image[]`
  and `chip->eimage[]` only. No `cimage[]`, no control-port touching.

### 4.c `cs4237b.c`

The PnP/ISA stub:

- `MODULE_ALIAS("snd-cs4237b")` only. Does **not** claim `snd_cs4232`
  (which the stock driver does); that keeps userland `modprobe
  snd_cs4232` pointing at the stock driver and prevents accidental
  binding.
- PnP ID table contains only `{ "CSC0000", 0 }` (the WSS logical
  device). It deliberately does **not** claim `CSC0010` — that's the
  whole point.
- `snd_cs4237b_pnpbios_detect()`: on match, do *not* build a sibling-ID
  string and search for it. Just call `snd_cs4237b_create()` with
  `cport=-1`.
- `alsa_card_cs4237b_init()` registers a PnP driver and, optionally,
  an ISA driver for non-PnP fallback.

### 4.d Coexistence with `snd-cs4236`

Both drivers will register a PnP match for `CSC0000`. The PnP core
hands the device to the first driver whose `.probe` succeeds. With
both loaded at once, whichever loads first wins.

To make the choice deterministic:

- **If the user wants `snd-cs4237b`**: put `blacklist snd_cs4236`
  in `/etc/modprobe.d/cs4237b.conf`. This is documented in the
  Kconfig help text.
- **If the user wants the stock driver**: don't build `snd-cs4237b`,
  or blacklist it. Default behaviour if both `=m`: whichever udev
  loads first. On a 560Z the stock driver will error out and unbind,
  so our driver gets a second chance via `modprobe snd_cs4237b`.

A cleaner alternative (future work): add a probe-ordering mechanism
where `snd-cs4237b` only binds if `snd-cs4236` has *already failed*
for the same device. This is doable via a module parameter
`only_if_no_cdev=1` that makes the probe scan the PnP device list for
a sibling `CSC0010` and return `-ENODEV` if one is found, letting
`snd-cs4236` handle the "normal" boards. That parameter is proposed
in `REORGANIZATION-PLAN.md`.

## 5. Visibility in `make menuconfig`

With the additions above, the option tree reads:

```
Device Drivers
  └── Sound card support
      └── Advanced Linux Sound Architecture
          └── ISA sound devices
              ├── Analog Devices SoundPort AD1816A
              ├── Generic AD1848/CS4248 driver
              ├── Aztech AZT1605 Driver
              ├── ...
              ├── Generic Cirrus Logic CS4231 driver
              ├── Generic Cirrus Logic CS4232/CS4236+ driver
              ├── Cirrus Logic CS4237B (no control port) driver   <-- NEW
              │   └── Verbose debug output for CS4237B driver      <-- NEW
              └── ...
```

The user gets the new entry without any existing entry moving.

## 6. Migration path for the tinycore-560z build

In `tools/make-bzImage-modules-tczs.sh`, replace the current patching
step:

```
mv $CS4237B_PATCHES/* .
$TOOLS/pick-patches.sh $KERNEL_VERSION
$TOOLS/patch-cs4236.sh
```

with:

```
# Add the new driver sub-tree
cp -r $CS4237B_PATCHES/sound-isa-cs4237b sound/isa/cs4237b
# Integrate it into the build
patch -p1 < $CS4237B_PATCHES/integration/sound-isa-Kconfig.patch
patch -p1 < $CS4237B_PATCHES/integration/sound-isa-Makefile.patch
# (no more cs4236/cs4236_lib/wss/wss.h patches)
```

And in the `.config-v6.x` kernel config, replace:

```
CONFIG_SND_CS4236=m
```

with:

```
CONFIG_SND_CS4236=m       # keep it around; harmless when blacklisted
CONFIG_SND_CS4237B=m
```

Then in the core.gz, ship an `/etc/modprobe.d/cs4237b-560z.conf`:

```
# 560Z has no CSC0010 control device; prefer the CS4237B-only driver
blacklist snd_cs4236
```

## 7. Test plan

Minimum set of verifications before merging:

1. **Build under allyesconfig** — catches missing selects and symbol
   typos.
2. **Build with `CONFIG_SND_CS4237B=n` and everything else = y** —
   confirms no stray symbol references that would break when the
   option is off.
3. **Build with `CONFIG_SND_CS4237B=m` + `CONFIG_SND_CS4236=m`** —
   confirms modules coexist without symbol collisions. Key names to
   check: no duplicates of `snd_cs4237b_*`; no `snd_cs4236_*` symbol
   is re-exported from the new module.
4. **Load both modules on a 560Z with `snd_cs4236` *not* blacklisted.**
   Expect: `snd_cs4236` fails for `CSC0000` (control-port error),
   `snd_cs4237b` picks it up and probes successfully.
5. **Load both modules with `snd_cs4236` blacklisted.** Expect:
   `snd_cs4237b` binds first try.
6. **Load only `snd_cs4237b`.** Expect: `aplay /usr/share/sounds/.../
   front_center.wav` plays back audibly after `alsactl init CS4237B`
   and `alsamixer` Master/PCM up.
7. **`rmmod snd_cs4237b` then `modprobe` again.** Confirm clean
   teardown with no oops.

## 8. What is deliberately left out

The following are **not** in the scope of this plan; they belong to
the separate reorganization plan in `REORGANIZATION-PLAN.md`.

- Splitting `cs4236.c` into per-chip files (CS4232, CS4235, CS4236,
  CS4236B, CS4237B-with-ctrl, CS4238B, CS4239).
- Making `wss_lib.c` more readable (the author's refactorings in
  `wss_lib.c` are genuine improvements, but shared-code changes need
  to be landed through the upstream ALSA tree, not via this patch
  set).
- Adding the behavioural-question fixes from the `TODO` comments
  (TRD-bit handling, capture-format MCE sequence).
