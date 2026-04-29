# Config Disable Candidates — `.config-6.18`

Synthesis of phases 2–7 of the investigation in `journal/CONFIG_INVESTIGATION_6.18.md`. Each candidate below is keyed off the inventory in `journal/CONFIG_INVENTORY_6.18.md`. **No `.config` edits — this branch is report-only.**

Three buckets, in increasing risk:

1. **A — High confidence, dead code on this hardware.** Should be safe to disable, with an explanation of why the 560Z has no path that exercises the symbol. Defer the obvious caveat: the kernel build may pull a symbol back in through a `select`. Always verify in `make menuconfig` that the option is actually selectable.
2. **B — Probably safe, verify on next boot.** The 560Z workload doesn't appear to need it; risk is "some specific tool stops working" rather than "kernel won't boot". Disable, then watch for fallout.
3. **C — Big-ticket, structural. Conditional on a deliberate trade.** Disabling these requires agreeing to a trade-off (e.g. drop signed-regdb verification → can drop the whole asymmetric-crypto stack). Each item names the trade.

The five must-keep subsystems (networking USB-Ethernet + RTL8192CU wifi, CS4237B sound, NeoMagic + VESA framebuffer, IDE on PIIX4 ATA, USB UHCI) and the inferred Required symbols are listed at the end as a **Don't-touch list**.

---

## Bucket A — High confidence, dead code on the 560Z

| Symbol | Why it's dead on the 560Z |
|---|---|
| `CONFIG_CRYPTO_AES_NI_INTEL` | AES-NI is a Westmere-and-newer instruction. Pentium II has no SSE2, let alone AES-NI. The CPU feature check at runtime would always disable it; the code is uselessly compiled in. |
| `CONFIG_X86_DECODER_SELFTEST` | already off; mentioned only as the canonical example of "instruction-decoder selftests aren't a 560Z workload" — none of the *_SELFTEST options are on. **No action.** |
| `CONFIG_BPF`, `CONFIG_BPF_SYSCALL` | TinyCore on a 560Z has no eBPF tooling (no `bpftool`, no XDP, no socket filters wired to userspace). Disabling removes the syscall, the verifier, and the JIT-control plumbing. |
| `CONFIG_PERF_EVENTS` (and the `HAVE_PERF_*` selects under it) | No `perf` userland on this machine; no PMU on a P-II that's worth profiling either. |
| `CONFIG_KEXEC`, `CONFIG_KEXEC_CORE`, `CONFIG_VMCORE_INFO` | No kexec workflow on the 560Z (and the kernel-loading code path is sizeable). Also removes `CONFIG_ARCH_SUPPORTS_KEXEC*` references downstream. |
| `CONFIG_USERFAULTFD` | Userspace page-fault handling is a CRIU / live-migration feature. Useless on a 560Z. |
| `CONFIG_SECRETMEM` | `memfd_secret(2)` for cloud HSM-ish workloads. Not relevant. |
| `CONFIG_RELAY` | Kernel relay channels — used by blktrace and a couple of debug paths. Nothing references it in this build. |
| `CONFIG_NAMESPACES`, `CONFIG_UTS_NS`, `CONFIG_IPC_NS`, `CONFIG_PID_NS`, `CONFIG_USER_NS`, `CONFIG_NET_NS`, `CONFIG_TIME_NS` | TinyCore on a 560Z has no containers, no `unshare`-style sandboxing daemon. `USER_NS` in particular is one of the more expensive options to keep. (Note: a few daemons assume `CLONE_NEWNS` works; busybox doesn't.) |
| `CONFIG_TASKSTATS`, `CONFIG_TASK_DELAY_ACCT`, `CONFIG_BSD_PROCESS_ACCT`, `CONFIG_BSD_PROCESS_ACCT_V3` | Process accounting; no userspace consumes it on this box. |
| `CONFIG_GCC_PLUGINS` | No plugin selected (`# CONFIG_GCC_PLUGIN_LATENT_ENTROPY is not set`). The framework adds plumbing for the plugin runtime that nothing exercises. |
| `CONFIG_CONNECTOR`, `CONFIG_PROC_EVENTS` | proc-event netlink notifications. busybox doesn't use it. |
| `CONFIG_RESCTRL_FS`, `CONFIG_RESCTRL_FS_PSEUDO_LOCK` | Intel Cache-Allocation Technology pseudo-FS. Skylake-X server feature. Not on a P-II. |
| `CONFIG_X86_CPU_RESCTRL`, `CONFIG_ARCH_HAS_CPU_RESCTRL`, `CONFIG_PROC_CPU_RESCTRL` | Same family as above — CAT/CDP plumbing. Verify these auto-disable when `RESCTRL_FS` goes; if the symbol is hand-set, drop. |
| `CONFIG_X86_VMX_FEATURE_NAMES` | Names of VT-x feature bits in `/proc/cpuinfo`. P-II has no VMX. (May be auto-selected by something — confirm in menuconfig.) |
| `CONFIG_HAVE_ATOMIC_IOMAP` | x86-32 atomic-iomap for HIGHMEM. With `# CONFIG_HIGHMEM4G is not set`, this should be selectable away. |
| `CONFIG_NET_DEVMEM` | NIC device-memory zero-copy. Auto-selected from `CONFIG_NET=y` paths; if `make menuconfig` exposes a knob, drop. |
| `CONFIG_DUMMY` | The `dummy0` virtual interface; useful for debugging routing. Not used in the boot path. |
| `CONFIG_NVMEM` | NVMEM framework with no provider drivers selected. Should be selectable away once `RTC_NVMEM=y` is reconciled (RTC_NVMEM is a tiny `select`; can be turned off too — not used by anything in TCL on a 560Z). |
| `CONFIG_DMA_SHARED_BUFFER`, `CONFIG_SYNC_FILE`, `CONFIG_UDMABUF` | dma-buf framework. Nothing references it: no DRM, no V4L2, no V4L2-mem. |
| `CONFIG_HW_RANDOM`, `CONFIG_HW_RANDOM_TIMERIOMEM` | None of the actual HW RNG drivers are enabled, and a 560Z has no on-chip RNG. The umbrella + TIMERIOMEM produce nothing usable. |
| `CONFIG_BLK_DEV_BSG`, `CONFIG_BLK_DEV_BSGLIB`, `CONFIG_BLK_DEV_BSG_COMMON` | SCSI generic block-SG. No `sg3_utils` workflow here. |
| `CONFIG_BLK_DEV_INTEGRITY` | T10 PI for enterprise SAS/NVMe. No 560Z disk supports it. |
| `CONFIG_SATA_HOST` (if disentangleable) | The 560Z has no SATA hardware; `# CONFIG_SATA_AHCI is not set` already. `SATA_HOST` appears as a side-effect of `CONFIG_ATA=y`. Verify in menuconfig whether it's user-selectable; if so, drop. |
| `CONFIG_FRAME_POINTER`, `CONFIG_UNWINDER_FRAME_POINTER` | Backtrace quality on panic. Switching to `CONFIG_UNWINDER_GUESS=y` removes per-function prologue overhead. Code-size win throughout the kernel. |
| `CONFIG_DEBUG_KERNEL` | Submenu enabler. With every actual debug option already off, flipping this off is just cosmetic / safer-by-default and removes a tiny amount of conditionally-compiled init code. |
| `CONFIG_HARDENED_USERCOPY_DEFAULT_ON` (debatable) | Keep the protection but flip the default off → most copies skip the check at runtime. Modest savings; trades a small safety margin. **Only if linic explicitly OKs it.** Better default: leave on. |

Code-size impact for Bucket A is realistically in the range of **100–400 KiB** of compressed bzImage, mostly driven by the BPF/perf/namespaces/USER_NS group. It's hard to predict without rebuilding.

## Bucket B — Probably safe, verify after rebuild

These are areas where I'm not 100% sure nothing on the 560Z's userspace path uses them. Disable, rebuild, boot, and watch for "feature X stopped working".

| Symbol | What might break |
|---|---|
| `CONFIG_SECCOMP`, `CONFIG_SECCOMP_FILTER` | If you run a daemon that calls `seccomp(2)` (Chromium, OpenSSH `UsePrivilegeSeparation=sandbox`, etc.), that daemon will refuse to start. busybox doesn't care. |
| `CONFIG_FUSE_FS`, `CONFIG_FUSE_PASSTHROUGH` | `ntfs-3g`, `sshfs`, `gvfs` etc. Disable if you don't load any FUSE-backed extension. |
| `CONFIG_CRYPTO_USER_API` and family | `AF_ALG`-based userspace crypto. Nothing in TCL uses it by default. |
| `CONFIG_CRYPTO_DRBG`, `CONFIG_CRYPTO_DRBG_HMAC`, `CONFIG_CRYPTO_JITTERENTROPY` | The kernel's `/dev/random` works without DRBG (chacha20 RNG core). FIPS-y deployments need it; nothing else does. |
| `CONFIG_CRYPTO_DEFLATE`, `CONFIG_CRYPTO_LZO`, `CONFIG_CRYPTO_ZSTD` (the crypto-side compressors) | Pulled in by zswap (off) and IPCOMP (off). Verify nothing else selects them. |
| `CONFIG_CRYPTO_DES`, `CONFIG_CRYPTO_MD4` | NTLM, very old IPSec. Wifi/WPA2 doesn't use them. |
| `CONFIG_CRYPTO_BLAKE2B`, `CONFIG_CRYPTO_SHA3`, `CONFIG_CRYPTO_XXHASH` | btrfs / kernel module signing / a couple of niche FS. Nothing on 560Z uses them. |
| `CONFIG_CRYPTO_SHA512` | Verify nothing pulls it (some PKI / IKEv2 paths do). With C → applies anyway if asym keys go. |
| `CONFIG_FW_LOADER_USER_HELPER`, `CONFIG_FW_LOADER_USER_HELPER_FALLBACK`, `CONFIG_FW_LOADER_COMPRESS` | Old `udevd hotplug` firmware-loading. Direct-path firmware loading from `/lib/firmware/` works without this. **Verify rtlwifi loads `rtl8192cufw_TMSC.bin` after disabling — that's the regression risk.** |
| `CONFIG_FS_POSIX_ACL` | If anything mounts a filesystem with `acl` and expects to enforce ACLs, it'll silently degrade. TCL doesn't ship with that workflow. |
| `CONFIG_LEGACY_TIOCSTI` | `TIOCSTI` ioctl is mostly used by archaic `tput`/`ed`-style code. Modern `agetty`/`busybox` don't need it. |
| `CONFIG_PROC_KCORE` | `/proc/kcore` (reading kernel memory through `/proc`). Used by `crash`, `gdb` — neither runs on a 560Z. |
| `CONFIG_LDISC_AUTOLOAD` | Auto-load of TTY line disciplines on first use. Modern kernels deprecate it; busybox doesn't trigger autoload. |
| `CONFIG_INPUT_VIVALDIFMAP` | "Vivaldi" function-key mapping for newer Chromebook keyboards. Pre-2020 hardware doesn't see it. **Almost certainly safe to disable.** Bumped from A to B because I'm not sure if it's auto-selected somewhere. |
| `CONFIG_LEGACY_PTYS` | Already off — mentioned to confirm it is fine to stay off. **No action.** |
| `CONFIG_FANOTIFY` | inotify's privileged sibling, used by `auditd` and some antivirus daemons. busybox/TCL don't ship those. |
| `CONFIG_PROC_PAGE_MONITOR` | `/proc/<pid>/pagemap`, `/proc/kpagecount`, `/proc/kpageflags`. Used by very specific tooling. |
| `CONFIG_NLS_CODEPAGE_437`, `CONFIG_NLS_CODEPAGE_850` | NLS code pages used by VFAT/CIFS for filename translation. With `# CONFIG_VFAT_FS is not set` and `# CONFIG_NETWORK_FILESYSTEMS is not set`, these are unused. `NLS_UTF8` and `NLS_ISO8859_1` are still useful for `cdrom`/general locale. |
| `CONFIG_KEYS` (and the asym subtree) | See bucket C. |

## Bucket C — Big-ticket, conditional on a trade

Each item here removes a meaningful amount of code, but only if you accept a specific trade-off. I'd suggest leaving these for after Bucket A+B has been measured.

### C1. Drop signed-regdb verification

**Trade:** the kernel can no longer verify the signature on the wireless regulatory database. In practice, you'd ship the unsigned one and the kernel takes you at your word.

**What turns off:**
- `CONFIG_CFG80211_REQUIRE_SIGNED_REGDB`
- `CONFIG_CFG80211_USE_KERNEL_REGDB_KEYS`
- `CONFIG_ASYMMETRIC_KEY_TYPE`
- `CONFIG_ASYMMETRIC_PUBLIC_KEY_SUBTYPE`
- `CONFIG_X509_CERTIFICATE_PARSER`
- `CONFIG_PKCS7_MESSAGE_PARSER`
- `CONFIG_CRYPTO_RSA`, `CONFIG_CRYPTO_DH`, `CONFIG_CRYPTO_ECC`, `CONFIG_CRYPTO_ECDH`, `CONFIG_CRYPTO_AKCIPHER`, `CONFIG_CRYPTO_AKCIPHER2`, `CONFIG_CRYPTO_KPP`, `CONFIG_CRYPTO_KPP2`, `CONFIG_CRYPTO_SIG`, `CONFIG_CRYPTO_SIG2`, `CONFIG_SYSTEM_TRUSTED_KEYRING`
- `CONFIG_KEYS` (probably; some other things may still pull it)
- `CONFIG_OID_REGISTRY`, `CONFIG_MPILIB`

This subtree alone is **easily 100–200 KiB compressed**. Big single-knob win.

### C2. Drop OHCI USB

**Trade:** any USB host controller chip that's OHCI-only stops working. The 560Z's onboard USB is UHCI (PIIX4), so the built-in ports are unaffected. You'd lose support for any add-on PCI USB card from a non-Intel vendor.

**What turns off:** `CONFIG_USB_OHCI_HCD`, `CONFIG_USB_OHCI_HCD_PCI`, `CONFIG_USB_OHCI_LITTLE_ENDIAN`.

If you've never plugged a non-Intel-USB add-on card into the 560Z, this is free.

### C3. Drop process namespaces entirely

Already in Bucket A, but worth restating: turning off the entire NS group is the largest single non-controversial savings. The trade is that any container-y workflow becomes impossible. On the 560Z, you don't have one anyway.

### C4. Drop FUSE entirely (Bucket B item, but listed here as a conscious package)

If you commit to "no FUSE on the 560Z", drop `CONFIG_FUSE_FS`, `CONFIG_FUSE_PASSTHROUGH`. Several KiB and removes a subsystem.

### C5. Drop `CONFIG_KEYS` plus dependents

Together with C1, this lets the entire keys infrastructure go. Some peculiar uses of keyring (`request-key`, `dns_resolver`, NFS) would break, but those aren't on TCL anyway.

### C6. Drop the IO APIC code

`CONFIG_X86_IO_APIC=y`, `CONFIG_ACPI_HOTPLUG_IOAPIC=y`. The 560Z's chipset (430TX) doesn't have an I/O APIC; interrupts are routed through the PIIX4 PIC. **But** PCI/ACPI is fussy; this is a "verify with a build & boot" item, not a one-line drop. Listed in C because it's structural. The test is `cat /proc/interrupts` after boot — no `IO-APIC` entries should be there even with `X86_IO_APIC=y` today; if so, dropping the option costs nothing.

---

## Don't-touch list (load-bearing for the five must-keep subsystems)

These are confirmed-required by reading the inventory. Listed so the menuconfig pass has a reference.

**Networking (USB-Ethernet + Realtek wifi):**
- `NET`, `PACKET`, `UNIX`, `INET`, `IPV6`, `TCP_CONG_CUBIC`
- `WIRELESS`, `CFG80211`, `MAC80211`, `WLAN`, `WLAN_VENDOR_REALTEK`, `RTL_CARDS`, `RTL8192CU`, `RTLWIFI`, `RTLWIFI_USB`, `RTL8192C_COMMON`
- `NETDEVICES`, `ETHERNET`, `NET_CORE`, `MII`, `MDIO_BUS`, `PHYLIB`, `SWPHY`, `FIXED_PHY`
- `USB_NET_DRIVERS`, `USB_USBNET`, `USB_RTL8152`, `USB_RTL8153_ECM`, `USB_NET_CDCETHER`
- `EEPROM_93CX6`, `FW_LOADER` (firmware blobs for rtlwifi)
- WPA2 crypto: `CRYPTO_AES`, `CRYPTO_CCM`, `CRYPTO_GCM`, `CRYPTO_CTR`, `CRYPTO_HMAC`, `CRYPTO_CMAC`, `CRYPTO_SHA1`, `CRYPTO_SHA256`, `CRYPTO_ARC4`, `CRYPTO_GHASH`, `CRYPTO_MICHAEL_MIC`

**Sound (CS4237B):**
- `SOUND`, `SND`, `SND_TIMER`, `SND_PCM`, `SND_HWDEP`, `SND_RAWMIDI`, `SND_PROC_FS`, `SND_SUPPORT_OLD_API`, `SND_PCM_TIMER`, `SND_DMA_SGBUF`, `SND_CTL_FAST_LOOKUP`
- `SND_WSS_LIB`, `SND_ISA`, `SND_OPL3_LIB`, `SND_MPU401_UART`
- `SND_CS4236=m`, `SND_CS4237B=m` (out-of-tree bridge, see `cs4237b/`)
- ISA bus: `ISA_BUS`, `ISA`, `ISA_DMA_API`, `GENERIC_ISA_DMA`, `ZONE_DMA`
- PNP: `PNP`, `ISAPNP`, `PNPBIOS`, `PNPACPI`

**Video (NeoMagic + VESA framebuffer console):**
- `VIDEO`, `FB`, `FB_CORE`, `FB_NOTIFY`, `FB_DEVICE`
- `FB_CFB_FILLRECT`, `FB_CFB_COPYAREA`, `FB_CFB_IMAGEBLIT`, `FB_IOMEM_FOPS`, `FB_IOMEM_HELPERS`, `FB_MODE_HELPERS`
- `FB_VESA`, `FB_NEOMAGIC`, `BOOT_VESA_SUPPORT`
- Console: `VT`, `VT_CONSOLE`, `VT_HW_CONSOLE_BINDING`, `VGA_CONSOLE`, `FRAMEBUFFER_CONSOLE`, `FRAMEBUFFER_CONSOLE_DETECT_PRIMARY`, `DUMMY_CONSOLE`
- Fonts: `FONT_SUPPORT`, `FONT_8x8`, `FONT_8x16`
- Helpers: `VGASTATE`, `FIRMWARE_EDID`, `APERTURE_HELPERS`, `SCREEN_INFO`, `SYSFB`
- `MTRR` (write-combining for the FB aperture)

**Hard drive (IDE on PIIX4):**
- `BLOCK`, `BLOCK_LEGACY_AUTOLOAD`, `BLK_DEV`, `BLK_DEV_LOOP` (squashfs/.tcz!)
- `SCSI_MOD`, `SCSI`, `SCSI_DMA`, `SCSI_COMMON`, `BLK_DEV_SD`
- `ATA`, `ATA_SFF`, `ATA_BMDMA`, `ATA_PIIX`
- `MSDOS_PARTITION`, `PARTITION_ADVANCED`
- Filesystems: `EXT4_FS`, `EXT4_USE_FOR_EXT2`, `JBD2`, `FS_MBCACHE`, `SQUASHFS` (+`SQUASHFS_ZLIB` and `SQUASHFS_LZ4` at minimum), `TMPFS`, `PROC_FS`, `SYSFS`, `KERNFS`

**USB (built-in PIIX4 UHCI):**
- `USB_SUPPORT`, `USB`, `USB_PCI`, `USB_COMMON`, `USB_UHCI_HCD`
- `USB_OHCI_HCD` is C2-conditional (drop if you don't use non-Intel USB host)

**Input (keyboard, trackpoint, PS/2 trackpad — built-in):**
- `INPUT`, `SERIO`, `SERIO_I8042`, `SERIO_SERPORT`, `SERIO_LIBPS2`
- `INPUT_KEYBOARD`, `KEYBOARD_ATKBD`
- `INPUT_MOUSE`, `MOUSE_PS2`, `MOUSE_PS2_SYNAPTICS`, `MOUSE_PS2_TRACKPOINT`
- `INPUT_MOUSEDEV`, `INPUT_MOUSEDEV_PSAUX`
- `INPUT_PCSPKR` (for the boot beep)

**Boot / userspace fundamentals:**
- `BLK_DEV_INITRD`, `RD_GZIP`, `INITRAMFS_PRESERVE_MTIME`
- `MULTIUSER`, `FUTEX`, `EPOLL`, `TIMERFD`, `SIGNALFD`, `EVENTFD`, `AIO`, `SHMEM`, `POSIX_TIMERS`, `PRINTK`, `BUG`, `BINFMT_ELF`, `BINFMT_SCRIPT`, `MMU`
- `SYSCTL`, `SYSCTL_EXCEPTION_TRACE`, `SYSFS_SYSCALL`
- `RTC_CLASS`, `RTC_DRV_CMOS`, `RTC_HCTOSYS`
- `MICROCODE` (debatable — see Bucket A discussion)

---

## Approach for the eventual menuconfig pass

The kernel's `make menuconfig` is the only authoritative way to know which symbols are actually selectable: many Bucket A items are auto-selected by parents and the menu will refuse to let you toggle them. Suggested order:

1. Make a `.config-6.18.bak` copy.
2. Apply all of Bucket A first. Build. Boot. Time to first prompt.
3. Apply C2 (OHCI), C3 (namespaces — already in A), and C6 (IO APIC). Build. Boot. Test wifi, USB ethernet, sound, X server.
4. Apply C1 (signed-regdb). Build. Boot. Test wifi specifically — `cfg80211` will log if it can't verify the regdb.
5. Apply Bucket B in two halves: the crypto half first (least risky), then the FS/proc half.
6. After all that, measure `bzImage` size and `core.gz` size delta.

Each step is a separate iteration commit on a separate branch (not this one — this one is report-only).

---

## Things deliberately not investigated

- The **modules-only** kernel build that produces `alsa-modules-*-tcz`, `ipv6-netfilter-*-tcz`, `wireless-*-tcz`, etc. That has a different `.config` (or a different invocation of `make modules`) and a separate trim opportunity.
- The userspace contents of `core.gz` (`busybox` symlinks, `/etc`, `/lib`, etc.) — different problem.
- The `cs4237b/` source-level surface — out of scope for this branch (and `cs4237b-clean-driver-wip` is the active branch for that).
- Whether `make oldconfig` from 6.18 → 6.19 changes any of the assumptions above. It probably will; revisit per kernel bump.
