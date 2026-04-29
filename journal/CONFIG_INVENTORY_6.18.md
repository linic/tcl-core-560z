# Config Inventory — `.config-6.18`

Phase 1 of the investigation in `journal/CONFIG_INVESTIGATION_6.18.md`. This file inventories every `=y` line in `.config-6.18` by subsystem, with a one-line note on the 560Z relevance. No "disable / keep" judgements here yet — that's Phase 7.

Conventions used below:
- **Required** = Disabling will break a 560Z must-keep subsystem (networking, sound, video, hard drive, USB) or boot.
- **Useful** = Probably needed for the way TCL is used on the 560Z, but not load-bearing in an obvious way.
- **Surface** = Code is included but the 560Z has no hardware or workload that exercises it.
- **Already-good** = Already off / set sensibly; mentioned only because it matters for the conclusion.

A `?` next to the tag means I'm not confident, and the symbol is a Phase 7 candidate to recheck against the kernel docs.

## Toolchain / build / `=y` totals

865 `=y`, 2 `=m` (`CONFIG_SND_CS4236`, `CONFIG_SND_CS4237B`), 1373 `is not set`. Useful structural facts:

- `CONFIG_MODULES is not set` (line 670) — the kernel is **monolithic**. So the only `=m` paths in this `.config` would normally not produce modules at all; they only build because Phase 5 of the tools revamp special-cases the cs4237b out-of-tree build (see `cs4237b/docs/STATUS.md`). For the bzImage-shrink question, treat `=m` as effectively absent.
- `CONFIG_KALLSYMS is not set` — Already-good, big win already taken.
- `CONFIG_DEBUG_INFO_NONE=y` — Already-good, no DWARF.
- `CONFIG_CC_OPTIMIZE_FOR_SIZE=y` — Already-good, `-Os`.
- `CONFIG_SLUB_TINY=y` — Already-good, the small-kernel SLUB path.
- `CONFIG_FRAME_POINTER=y` — Useful for backtraces. **Surface? candidate** — a 560Z has no kernel-debug workflow.
- `CONFIG_GCC_PLUGINS=y` — framework only; no plugin selected. **Surface candidate** — saves the plugin support code.

## Processor / platform — already very lean

- `CONFIG_X86_32=y`, `# CONFIG_64BIT is not set`, `CONFIG_MPENTIUMII=y`, `CONFIG_NR_CPUS=1`, `# CONFIG_SMP is not set`, `# CONFIG_HIGHMEM4G is not set`, `# CONFIG_HYPERVISOR_GUEST is not set`, `# CONFIG_X86_EXTENDED_PLATFORM is not set`, `# CONFIG_X86_MCE is not set`, `# CONFIG_CPU_MITIGATIONS is not set`, `# CONFIG_X86_PAT is not set`, `# CONFIG_X86_PMEM_LEGACY is not set`, `# CONFIG_RELOCATABLE is not set`, `# CONFIG_X86_MSR is not set`, `# CONFIG_X86_CPUID is not set`, `# CONFIG_TOSHIBA is not set`. **Already-good.**
- `CONFIG_HPET_TIMER=y`, `CONFIG_HPET_EMULATE_RTC=y`. **Useful** (HPET on the 430TX path is fine; emulation is the safer setting on this generation).
- `CONFIG_X86_PAE=y`, `CONFIG_VMSPLIT_3G=y`. **Useful**, default for 32-bit. PAE is technically redundant on a P-II with ≤4 GB RAM but disabling cascades into other choices — leave alone.
- `CONFIG_MICROCODE=y`, `CONFIG_MICROCODE_INITRD32=y`. P-II has no Intel microcode updates available. **Surface candidate** — saves a small loader path.
- `CONFIG_X86_LOCAL_APIC=y`, `CONFIG_X86_IO_APIC=y`, `CONFIG_X86_UP_APIC=y`. The 560Z has no I/O APIC (it's PIC-only). `X86_UP_APIC` and `X86_LOCAL_APIC` are needed by the boot code. `X86_IO_APIC` is **Surface? candidate** — verify the 560Z BIOS doesn't actually expose one (probably not on a 1998 ThinkPad).
- `CONFIG_MTRR=y`, `CONFIG_MTRR_SANITIZER=y`. **Useful** — fbdev wants MTRR write-combining for the framebuffer aperture.

## Power / ACPI

- `CONFIG_ACPI=y`. The 560Z has ACPI 1.0; the BIOS DSDT is ancient and minimal. **Useful for boot path**, plus PNPACPI hooks. Most ACPI submodules already off.
- `# CONFIG_SUSPEND is not set`, `# CONFIG_HIBERNATION is not set`, `# CONFIG_CPU_FREQ is not set`, `# CONFIG_CPU_IDLE is not set`, `# CONFIG_ACPI_PROCESSOR is not set`, `# CONFIG_ACPI_BATTERY is not set`, `# CONFIG_ACPI_AC is not set`, `# CONFIG_ACPI_BUTTON is not set`, `# CONFIG_ACPI_DOCK is not set`. **Already-good.**
- `CONFIG_ACPI_HOTPLUG_IOAPIC=y`. Same I/O APIC question as above — **Surface? candidate**.
- `CONFIG_PM=y`, `CONFIG_PM_CLK=y`. Required by quite a few drivers — keep.

## Bus / PNP / DMA

- `CONFIG_PCI=y`, `CONFIG_PCI_BIOS=y`, `CONFIG_PCI_DIRECT=y`, `CONFIG_PCI_MMCONFIG=y`, `CONFIG_PCI_QUIRKS=y`. **Required.**
- `# CONFIG_PCIEPORTBUS is not set`, `# CONFIG_PCIEASPM is not set`, `# CONFIG_PCI_MSI is not set`, `# CONFIG_VGA_ARB is not set`, `# CONFIG_HOTPLUG_PCI is not set`, `# CONFIG_PCCARD is not set` (PCMCIA off). **Already-good** (PCMCIA off is a deliberate trade — see Q3 in the journal).
- `CONFIG_ISA_BUS=y`, `CONFIG_ISA=y`, `CONFIG_ISA_DMA_API=y`, `CONFIG_GENERIC_ISA_DMA=y`. **Required for cs4237b.**
- `CONFIG_PNP=y`, `CONFIG_ISAPNP=y`, `CONFIG_PNPBIOS=y`, `CONFIG_PNPACPI=y`. **Required for cs4237b.** ISAPNP and PNPBIOS could probably overlap on this hardware — Q for menuconfig pass.
- `CONFIG_ZONE_DMA=y`. **Required** for ISA DMA buffers (cs4237b again).
- `CONFIG_GENERIC_PCI_IOMAP=y`, `CONFIG_PCI_DOMAINS=y`. **Required.**

## Memory / scheduler

- `CONFIG_FLATMEM=y`, `CONFIG_SLUB_TINY=y`, `CONFIG_COMPACTION=y`, `CONFIG_KSM=y`. **Useful** on a small-RAM box (KSM in particular).
- `CONFIG_NO_HZ_IDLE=y`, `CONFIG_HZ_300=y`, `CONFIG_HIGH_RES_TIMERS=y`, `CONFIG_PREEMPT_VOLUNTARY=y`. **Useful**, default-ish for a desktop-class workload.
- `CONFIG_NAMESPACES=y` and friends (`UTS_NS`, `TIME_NS`, `IPC_NS`, `USER_NS`, `PID_NS`, `NET_NS`). **Surface candidate** on a 560Z — no containers, no nspawn, no sandboxing daemon I'm aware of. `USER_NS` in particular is a known size cost.
- `CONFIG_USERFAULTFD=y`. **Surface candidate** — only useful for live-migration / CRIU userspace.
- `CONFIG_SECRETMEM=y`. **Surface candidate** — designed for cloud HSM-ish workloads.
- `CONFIG_SECCOMP=y`, `CONFIG_SECCOMP_FILTER=y`. **Useful?** — only matters if you run a sandboxing daemon. busybox doesn't need it; some `tce-load`d apps might.
- `CONFIG_FUTEX=y`, `CONFIG_FUTEX_PI=y`, `CONFIG_EPOLL=y`, `CONFIG_TIMERFD=y`, `CONFIG_EVENTFD=y`, `CONFIG_SIGNALFD=y`, `CONFIG_AIO=y`, `CONFIG_SHMEM=y`. **Required** by glibc / TCL userspace.
- `CONFIG_POSIX_MQUEUE=y`, `CONFIG_SYSVIPC=y`. **Required** by some legacy apps; safer to keep.
- `# CONFIG_IO_URING is not set`. **Already-good** — io_uring is a big subsystem and 560Z workloads do not benefit.
- `# CONFIG_TRANSPARENT_HUGEPAGE is not set`, `# CONFIG_HUGETLBFS is not set`, `# CONFIG_CMA is not set`. **Already-good.**
- `# CONFIG_AUDIT is not set`, `# CONFIG_PROFILING is not set`, `# CONFIG_CGROUPS is not set`, `# CONFIG_CHECKPOINT_RESTORE is not set`. **Already-good.**

## Tracing / perf / debug instrumentation

- `CONFIG_BPF=y`, `CONFIG_BPF_SYSCALL=y`. **Surface candidate** — no eBPF tooling in TCL on a 560Z.
- `CONFIG_PERF_EVENTS=y`, `CONFIG_HAVE_PERF_EVENTS=y`. **Surface candidate** — no `perf` use case on this box.
- `CONFIG_TASKSTATS=y`, `CONFIG_TASK_DELAY_ACCT=y`, `CONFIG_BSD_PROCESS_ACCT=y`, `CONFIG_BSD_PROCESS_ACCT_V3=y`. **Surface candidates.**
- `CONFIG_RELAY=y`. **Surface candidate** (used by blktrace, kvm-trace, a few drivers).
- `# CONFIG_FTRACE is not set`, `# CONFIG_KPROBES is not set`, `# CONFIG_KGDB is not set`, `# CONFIG_DEBUG_FS is not set`, `# CONFIG_KASAN is not set`, `# CONFIG_KFENCE is not set`, `# CONFIG_UBSAN is not set`, `# CONFIG_MAGIC_SYSRQ is not set`, `# CONFIG_DYNAMIC_DEBUG is not set`. **Already-good** — the heavy debug surface is already off.
- `CONFIG_DEBUG_KERNEL=y`. Just enables the submenu; tiny on its own. Could be flipped off as a final cosmetic pass.
- `CONFIG_FRAME_POINTER=y`, `CONFIG_UNWINDER_FRAME_POINTER=y`. **Surface candidates** — only matters for backtraces on panic. `UNWINDER_GUESS` is the smaller alternative.

## Kexec / crash

- `CONFIG_KEXEC_CORE=y`, `CONFIG_KEXEC=y`, `CONFIG_VMCORE_INFO=y`. **Surface candidates** — no kexec-tools workflow on the 560Z.

## Block / storage

- `CONFIG_BLOCK=y`, `CONFIG_BLOCK_LEGACY_AUTOLOAD=y`. **Required.**
- `CONFIG_BLK_DEV=y`, `CONFIG_BLK_DEV_LOOP=y`. **Required** — loop is how `tce-load` mounts `.tcz` (squashfs) extensions.
- `CONFIG_BLK_DEV_BSG_COMMON=y`, `CONFIG_BLK_DEV_BSGLIB=y`, `CONFIG_BLK_DEV_BSG=y`. **Surface candidates** — SCSI generic; useful for `sg3_utils`, not for booting TCL.
- `CONFIG_BLK_DEV_INTEGRITY=y`. **Surface candidate** — only matters for T10 PI on enterprise SAS/NVMe.
- `CONFIG_BLK_WBT=y`, `CONFIG_BLK_WBT_MQ=y`. **Useful?** — writeback throttling is generic; could try off.
- `# CONFIG_MQ_IOSCHED_DEADLINE is not set`, `# CONFIG_MQ_IOSCHED_KYBER is not set`, `# CONFIG_IOSCHED_BFQ is not set`. **Already-good** (uses none scheduler).
- `# CONFIG_BLK_DEV_NVME is not set`, `# CONFIG_BLK_DEV_RAM is not set`, `# CONFIG_BLK_DEV_FD is not set` (no floppy!), `# CONFIG_ZRAM is not set`. **Already-good.**
- `# CONFIG_MD is not set`, `# CONFIG_TARGET_CORE is not set`, `# CONFIG_FUSION is not set`, `# CONFIG_FIREWIRE is not set`. **Already-good.**

### ATA / SCSI for IDE on 430TX

- `CONFIG_SCSI_MOD=y`, `CONFIG_SCSI=y`, `CONFIG_SCSI_DMA=y`, `CONFIG_SCSI_COMMON=y`. **Required** — libata exposes IDE disks via SCSI core (`/dev/sda`).
- `CONFIG_BLK_DEV_SD=y`. **Required.**
- `# CONFIG_CHR_DEV_ST is not set`, `# CONFIG_BLK_DEV_SR is not set`, `# CONFIG_CHR_DEV_SG is not set`, `# CONFIG_SCSI_LOWLEVEL is not set`, `# CONFIG_SCSI_PROC_FS is not set`. **Already-good.**
- `CONFIG_ATA=y`, `CONFIG_SATA_HOST=y`, `CONFIG_ATA_SFF=y`, `CONFIG_ATA_BMDMA=y`, `CONFIG_ATA_PIIX=y`. The 560Z's IDE controller is on the PIIX4 — `ATA_PIIX` is the right driver. `SATA_HOST` is selected by `ATA` and is **Surface candidate? technically** — no SATA hardware exists on this machine; `# CONFIG_SATA_AHCI is not set` already, but `SATA_HOST` is still pulled in by Kconfig. Verify whether it's actually unselectable when `ATA_PIIX` requires the SFF path; if it has a separate Kconfig knob, drop it.
- All `# CONFIG_PATA_* is not set` (~40 chips). **Already-good.**

## Filesystems

- `CONFIG_EXT4_FS=y`, `CONFIG_EXT4_USE_FOR_EXT2=y`, `CONFIG_JBD2=y`. **Required** for the TCE persistence partition (and the boot partition is typically ext4 or ext2 served by the same driver).
- `# CONFIG_EXT2_FS is not set`. **Already-good** — ext4 covers ext2 via the unified driver.
- `# CONFIG_FS_POSIX_ACL is not set`? — actually `CONFIG_FS_POSIX_ACL=y` is set. **Useful?** — TCL doesn't usually need ACLs. Could disable.
- `CONFIG_SQUASHFS=y` + `CONFIG_SQUASHFS_ZLIB=y`, `CONFIG_SQUASHFS_LZ4=y`, `CONFIG_SQUASHFS_ZSTD=y`. **Required** for `.tcz`. Question: which compressors do TCL `.tcz` files actually use? Only `zlib`/`gzip` historically, plus `lz4` for newer builds. **Surface candidate**: drop `SQUASHFS_ZSTD` if tcz files don't use it. (Q for linic.)
- `CONFIG_TMPFS=y`. **Required.** `# CONFIG_TMPFS_POSIX_ACL is not set`. Already-good.
- `CONFIG_PROC_FS=y`, `CONFIG_SYSFS=y`, `CONFIG_KERNFS=y`. **Required.**
- `CONFIG_PROC_KCORE=y`, `CONFIG_PROC_PAGE_MONITOR=y`, `CONFIG_PROC_CHILDREN=y`. **Useful?** — `/proc/kcore` adds a small amount; the others are cheap.
- `CONFIG_FUSE_FS=y`, `CONFIG_FUSE_PASSTHROUGH=y`. **Useful?** — needed for `ntfs-3g`, `sshfs`, etc. if you ever load them. Otherwise **Surface candidate**.
- `# CONFIG_VFAT_FS is not set`, `# CONFIG_MSDOS_FS is not set`, `# CONFIG_NTFS3_FS is not set`, `# CONFIG_ISO9660_FS is not set`, `# CONFIG_UDF_FS is not set`, `# CONFIG_HFS_FS is not set`, all the rare-FS items. **Already-good.**
- `# CONFIG_OVERLAY_FS is not set`, `# CONFIG_QUOTA is not set`, `# CONFIG_AUTOFS_FS is not set`, `# CONFIG_CRAMFS is not set`. **Already-good.**
- `# CONFIG_NETWORK_FILESYSTEMS is not set` (NFS, CIFS, etc.). **Already-good.**
- `CONFIG_RESCTRL_FS=y`, `CONFIG_RESCTRL_FS_PSEUDO_LOCK=y`. **Surface candidate** — Intel CAT/CDP, only on Skylake-X server class.
- NLS: `NLS_CODEPAGE_437`, `NLS_CODEPAGE_850`, `NLS_ISO8859_1`, `NLS_ISO8859_15`, `NLS_UTF8`, `NLS_ASCII`. Without VFAT/CIFS, NLS modules are mostly unreferenced. **Surface candidates** if VFAT etc. stay disabled.

## Networking core

- `CONFIG_NET=y`, `CONFIG_PACKET=y`, `CONFIG_UNIX=y`, `CONFIG_INET=y`, `CONFIG_IPV6=y`. **Required.**
- `CONFIG_AF_UNIX_OOB=y`. **Useful** (fine to keep).
- `# CONFIG_NETFILTER is not set`. **Already-good** for the bzImage. Filter-pkg goes via the separate `ipv6-netfilter-*-tcz` artifact (which I have not analysed here).
- `# CONFIG_IP_MULTICAST is not set`. **Already-good.** Note: kills mDNS, IGMP. If avahi/Bonjour matters, this would have to come back. Q for linic.
- `# CONFIG_IP_ADVANCED_ROUTER is not set`, `# CONFIG_IP_PNP is not set`, `# CONFIG_INET_DIAG is not set`, `# CONFIG_TCP_CONG_ADVANCED is not set`. **Already-good.**
- `# CONFIG_BRIDGE is not set`, `# CONFIG_VLAN_8021Q is not set`, `# CONFIG_NET_SCHED is not set`. **Already-good.**
- `CONFIG_TCP_CONG_CUBIC=y`. **Required** (default congestion algo).
- `CONFIG_NET_INGRESS=y`, `CONFIG_NET_EGRESS=y`, `CONFIG_NET_XGRESS=y`, `CONFIG_NET_DEVMEM=y`. Pulled in by other selects; **Useful?** — DEVMEM in particular is for zero-copy NIC paths and probably surface, but it's auto-selected.
- `CONFIG_NET_RX_BUSY_POLL=y`, `CONFIG_BQL=y`, `CONFIG_PAGE_POOL=y`, `CONFIG_NET_SOCK_MSG=y`, `CONFIG_NET_SELFTESTS=y`. Mostly auto-selected by NET. `NET_SELFTESTS` is **Surface candidate.**
- `# CONFIG_RFKILL is not set`. **Already-good.**

## Wireless / WLAN

- `CONFIG_WIRELESS=y`, `CONFIG_CFG80211=y`, `CONFIG_MAC80211=y`. **Required** for `rtl8192cu`.
- `CONFIG_CFG80211_REQUIRE_SIGNED_REGDB=y`, `CONFIG_CFG80211_USE_KERNEL_REGDB_KEYS=y`, `CONFIG_CFG80211_CRDA_SUPPORT=y`. The signed-regdb path pulls in the full asymmetric crypto stack (`X509_CERTIFICATE_PARSER`, `PKCS7_MESSAGE_PARSER`, `CRYPTO_RSA`, etc.). **Surface candidate? big**: turning off `CFG80211_REQUIRE_SIGNED_REGDB` would let the asym-crypto subtree go away. Tradeoff: an unsigned regdb file would still work — it just becomes the user's responsibility.
- `# CONFIG_CFG80211_WEXT is not set`. **Already-good.**
- `CONFIG_MAC80211_RC_DEFAULT=""`, `# CONFIG_MAC80211_RC_MINSTREL is not set`. The kernel comment warns "Some wireless drivers require a rate control algorithm." `rtl8192cu` uses the in-driver rate control, so this is intentional and **Already-good** — but worth noting.
- `CONFIG_WLAN=y`, `CONFIG_WLAN_VENDOR_REALTEK=y`, `CONFIG_RTL_CARDS=y`, `CONFIG_RTL8192CU=y`, `CONFIG_RTLWIFI=y`, `CONFIG_RTLWIFI_USB=y`, `CONFIG_RTL8192C_COMMON=y`. **Required** for the wifi adapter linic uses.

## Ethernet (USB-only path)

- `CONFIG_NETDEVICES=y`, `CONFIG_ETHERNET=y`, `CONFIG_NET_CORE=y`. **Required.**
- All `NET_VENDOR_*` are unset — **Already-good.** No PCI Ethernet drivers (the 560Z has no built-in Ethernet anyway).
- `CONFIG_MII=y`, `CONFIG_MDIO_BUS=y`, `CONFIG_PHYLIB=y`, `CONFIG_SWPHY=y`, `CONFIG_FIXED_PHY=y`. Pulled in by USB ethernet drivers — **Required** but worth checking whether `SWPHY`/`FIXED_PHY` are actually exercised.
- All `*_PHY` drivers — **Already-good** (none selected).
- `CONFIG_FWNODE_MDIO=y`, `CONFIG_ACPI_MDIO=y`. Auto-selected.
- `CONFIG_DUMMY=y`. **Surface candidate** — `dummy0` interface; useful for testing, not for daily use.
- `# CONFIG_PPP is not set`, `# CONFIG_SLIP is not set`, `# CONFIG_TUN is not set`, `# CONFIG_BONDING is not set`, `# CONFIG_NET_TEAM is not set`, `# CONFIG_MACVLAN is not set`, `# CONFIG_VETH is not set`, `# CONFIG_VXLAN is not set`. **Already-good.**

### USB-based Ethernet

- `CONFIG_USB_NET_DRIVERS=y`, `CONFIG_USB_USBNET=y`, `CONFIG_USB_RTL8152=y`, `CONFIG_USB_RTL8153_ECM=y`, `CONFIG_USB_NET_CDCETHER=y`. **Required** (RTL8152 is the USB ethernet adapter linic uses).
- All other `USB_NET_*` drivers and `USB_CATC` / `USB_KAWETH` / `USB_PEGASUS` / `USB_RTL8150` are unset. **Already-good.**

## Sound (CS4237B path)

- `CONFIG_SOUND=y`, `CONFIG_SND=y`, `CONFIG_SND_TIMER=y`, `CONFIG_SND_PCM=y`, `CONFIG_SND_HWDEP=y`, `CONFIG_SND_RAWMIDI=y`, `CONFIG_SND_PROC_FS=y`, `CONFIG_SND_SUPPORT_OLD_API=y`, `CONFIG_SND_PCM_TIMER=y`. **Required.**
- `CONFIG_SND_DMA_SGBUF=y`. **Useful.**
- `CONFIG_SND_CTL_FAST_LOOKUP=y`. **Useful.**
- `# CONFIG_SND_OSSEMUL is not set`, `# CONFIG_SND_HRTIMER is not set`, `# CONFIG_SND_DYNAMIC_MINORS is not set`, `# CONFIG_SND_VERBOSE_PROCFS is not set`, `# CONFIG_SND_SEQUENCER is not set`, `# CONFIG_SND_DEBUG is not set`. **Already-good.**
- `CONFIG_SND_WSS_LIB=y`, `CONFIG_SND_ISA=y`, `CONFIG_SND_OPL3_LIB=y`, `CONFIG_SND_MPU401_UART=y`. **Required** (cs4236 family uses WSS+OPL3+MPU401).
- `CONFIG_SND_CS4236=m`, `CONFIG_SND_CS4237B=m`. **Required.**
- All other ISA drivers (SB16, GUS, ES1688, …): **Already-good** (unset).
- `# CONFIG_SND_PCI is not set`, `# CONFIG_SND_USB is not set`, `# CONFIG_SND_SOC is not set`, `# CONFIG_SND_DRIVERS is not set`. **Already-good.**
- `CONFIG_SND_X86=y`. **Useful** (umbrella for x86-specific sound bits).
- `# CONFIG_SND_HDA_ACPI is not set`. **Already-good.**

## Video / framebuffer

- `CONFIG_VIDEO=y` (top-level), `CONFIG_FB=y`, `CONFIG_FB_CORE=y`, plus the helpers `CONFIG_FB_NOTIFY=y`, `CONFIG_FB_DEVICE=y`, `CONFIG_FB_CFB_FILLRECT=y`, `CONFIG_FB_CFB_COPYAREA=y`, `CONFIG_FB_CFB_IMAGEBLIT=y`, `CONFIG_FB_IOMEM_FOPS=y`, `CONFIG_FB_IOMEM_HELPERS=y`, `CONFIG_FB_MODE_HELPERS=y`. **Required** for fb console + Xorg `fbdev`.
- `CONFIG_FB_VESA=y`, `CONFIG_FB_NEOMAGIC=y`. **Required** — VESA is the safety fallback, NeoMagic is the native driver for the 560Z's NM2160.
- `CONFIG_BOOT_VESA_SUPPORT=y`. **Required.**
- `CONFIG_VGA_CONSOLE=y`, `CONFIG_FRAMEBUFFER_CONSOLE=y`, `CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY=y`, `CONFIG_DUMMY_CONSOLE=y`. **Required.**
- `# CONFIG_DRM is not set`, `# CONFIG_AGP is not set`, `# CONFIG_VGA_ARB is not set`. **Already-good** — no DRM/KMS for a NeoMagic from 1998.
- All other `FB_*` chip drivers (Cirrus, Matrox, Radeon, etc.). **Already-good.**
- `# CONFIG_LOGO is not set`. **Already-good** (no Tux on boot).
- `CONFIG_FONT_8x8=y`, `CONFIG_FONT_8x16=y`. **Required** for the framebuffer console.
- `CONFIG_VGASTATE=y`, `CONFIG_FIRMWARE_EDID=y`. **Useful** — VESA fb path uses these.
- `CONFIG_APERTURE_HELPERS=y`, `CONFIG_SCREEN_INFO=y`. Auto-selected.
- `# CONFIG_BACKLIGHT_CLASS_DEVICE is not set`, `# CONFIG_LCD_CLASS_DEVICE is not set`. **Already-good** for our purposes (the 560Z's brightness is BIOS-controlled via Fn keys, not via the kernel backlight class).

## Input

- `CONFIG_INPUT=y`, `CONFIG_INPUT_KEYBOARD=y`, `CONFIG_KEYBOARD_ATKBD=y`, `CONFIG_INPUT_MOUSE=y`, `CONFIG_MOUSE_PS2=y`, `CONFIG_MOUSE_PS2_SYNAPTICS=y`, `CONFIG_MOUSE_PS2_TRACKPOINT=y`, `CONFIG_INPUT_MOUSEDEV=y`, `CONFIG_INPUT_MOUSEDEV_PSAUX=y`. **Required.**
- `CONFIG_SERIO=y`, `CONFIG_SERIO_I8042=y`, `CONFIG_SERIO_SERPORT=y`, `CONFIG_SERIO_LIBPS2=y`. **Required.**
- `CONFIG_INPUT_PCSPKR=y`, `CONFIG_INPUT_VIVALDIFMAP=y`. **Useful** — PC speaker for the boot beep.
- `# CONFIG_INPUT_EVDEV is not set`. **Question** — Xorg evdev driver wants `/dev/input/event*`. With this off, only the legacy mouse/keyboard interfaces work. If the desktop currently works on the 560Z, evdev is somehow not needed. Worth flagging — Q for linic.
- `# CONFIG_INPUT_JOYDEV is not set`, `# CONFIG_INPUT_JOYSTICK is not set`, `# CONFIG_INPUT_TABLET is not set`, `# CONFIG_INPUT_TOUCHSCREEN is not set`. **Already-good.**
- All non-AT-keyboard / non-PS2-mouse drivers. **Already-good.**

## USB host

- `CONFIG_USB_SUPPORT=y`, `CONFIG_USB=y`, `CONFIG_USB_PCI=y`, `CONFIG_USB_COMMON=y`. **Required.**
- `CONFIG_USB_OHCI_HCD=y`, `CONFIG_USB_OHCI_HCD_PCI=y`, `CONFIG_USB_UHCI_HCD=y`. **Required** — PIIX4 USB is UHCI; OHCI is for non-Intel chips. `OHCI` is **Surface candidate** if linic confirms only PIIX4 USB ports are used (no OHCI add-on cards on the 560Z).
- `CONFIG_USB_OHCI_LITTLE_ENDIAN=y`. Auto-selected.
- `# CONFIG_USB_XHCI_HCD is not set`, `# CONFIG_USB_EHCI_HCD is not set`. **Already-good** — no USB 2.0/3.0 hardware on a 560Z.
- `# CONFIG_USB_STORAGE is not set`. **Question for linic** — no USB drives means no install-via-USB-stick. Intentional?
- `# CONFIG_USB_HID is not set` (HID_SUPPORT off). **Question** — USB keyboards/mice, USB game controllers, etc., all dead. If linic only uses the built-in keyboard + USB ethernet/wifi, this is fine.
- `# CONFIG_USB_SERIAL is not set`, `# CONFIG_USB_PRINTER is not set`, `# CONFIG_USB_ACM is not set`, `# CONFIG_USB_OTG is not set`. **Already-good.**

## Security / crypto

- `CONFIG_KEYS=y`, `CONFIG_KEYS_REQUEST_CACHE=y`. Auto-selected by signed regdb / asymmetric keys path.
- `# CONFIG_SECURITY is not set`, `# CONFIG_SECURITYFS is not set`. **Already-good.**
- `CONFIG_HARDENED_USERCOPY=y`, `CONFIG_HARDENED_USERCOPY_DEFAULT_ON=y`. **Useful** (size cost is small, safety win is real).
- `CONFIG_INIT_STACK_ALL_ZERO=y`. **Useful** (small but real safety win).
- `# CONFIG_FORTIFY_SOURCE is not set`. Already chosen-not.
- `# CONFIG_STACKPROTECTOR is not set`. Already chosen-not.

### Crypto subtree

- `CONFIG_CRYPTO=y`, `CONFIG_CRYPTO_MANAGER=y`, `CONFIG_CRYPTO_HASH/AEAD/SKCIPHER/RNG/AKCIPHER/KPP/SIG/ACOMP*=y`. **Required** by anything that uses crypto.
- Pulled in by **wifi (mac80211 / WPA-CCMP)**: `CRYPTO_AES`, `CRYPTO_CCM`, `CRYPTO_GCM`, `CRYPTO_CTR`, `CRYPTO_CMAC`, `CRYPTO_HMAC`, `CRYPTO_SHA1`, `CRYPTO_SHA256`, `CRYPTO_ARC4`, `CRYPTO_GHASH`, `CRYPTO_MICHAEL_MIC` (TKIP). All **Required.**
- Pulled in by **signed regdb / asymmetric keys**: `CRYPTO_RSA`, `CRYPTO_DH`, `CRYPTO_ECC`, `CRYPTO_ECDH`, `X509_CERTIFICATE_PARSER`, `PKCS7_MESSAGE_PARSER`, `ASYMMETRIC_KEY_TYPE`, `ASYMMETRIC_PUBLIC_KEY_SUBTYPE`, `SYSTEM_TRUSTED_KEYRING`. **Surface candidate as a group** — these all become removable iff `CFG80211_REQUIRE_SIGNED_REGDB` is turned off. Big-ish win.
- `CONFIG_CRYPTO_AES_NI_INTEL=y`. **Surface candidate, certain** — Pentium II has no AES-NI; this is dead code on the 560Z.
- `CONFIG_CRYPTO_BLAKE2B=y`, `CONFIG_CRYPTO_SHA3=y`, `CONFIG_CRYPTO_XXHASH=y`, `CONFIG_CRYPTO_SHA512=y`. **Surface candidates** — SHA-512 is referenced by SHA-256 lib path? need to check; the others are typically used by btrfs / kernel module signing.
- `CONFIG_CRYPTO_DRBG=y`, `CONFIG_CRYPTO_DRBG_HMAC=y`, `CONFIG_CRYPTO_JITTERENTROPY=y`. **Surface candidates** — kernel `/dev/random` already has a chacha20 backend; DRBG is FIPS-y.
- `CONFIG_CRYPTO_CBC=y`, `CONFIG_CRYPTO_ECB=y`, `CONFIG_CRYPTO_CTS=y`, `CONFIG_CRYPTO_LRW=y`, `CONFIG_CRYPTO_XTS=y`, `CONFIG_CRYPTO_ESSIV=y`. **Surface candidates** if `dm-crypt`/disk-encryption isn't used. (TCL doesn't use dm-crypt by default.)
- `CONFIG_CRYPTO_DEFLATE=y`, `CONFIG_CRYPTO_LZO=y`, `CONFIG_CRYPTO_ZSTD=y`. **Surface candidates** — pulled in by zswap (off) and IPCOMP (off). Probably removable.
- `CONFIG_CRYPTO_USER_API=y` and friends. **Surface candidates** — only if userspace `AF_ALG` is used (TCL doesn't, AFAIK).
- `CONFIG_CRYPTO_DES=y`. **Surface candidate** — only used by old stuff (NTLM, IPSec). Wifi doesn't need DES.
- `CONFIG_CRYPTO_MD4=y`, `CONFIG_CRYPTO_MD5=y`. MD5 is used by some legacy hashing in the network stack, MD4 less so. **Probably-keep MD5, surface MD4.**

## Drivers / misc

- `CONFIG_FW_LOADER=y` and family. **Required** — `rtlwifi` needs `rtlwifi/rtl8192cufw_TMSC.bin` from `/lib/firmware`.
- `CONFIG_FW_LOADER_USER_HELPER=y`, `CONFIG_FW_LOADER_USER_HELPER_FALLBACK=y`. **Useful?** — old userspace-helper firmware loading; can probably be off if all firmware is direct-load.
- `CONFIG_FW_LOADER_COMPRESS=y`. **Surface candidate** — only useful if firmware is compressed on disk.
- `CONFIG_HW_RANDOM=y`, `CONFIG_HW_RANDOM_TIMERIOMEM=y`. **Surface candidate** — none of the named device drivers (`HW_RANDOM_INTEL`, `HW_RANDOM_VIA`, etc.) are enabled; the umbrella `HW_RANDOM` plus `TIMERIOMEM` is producing nothing usable on a 560Z.
- `CONFIG_RTC_CLASS=y`, `CONFIG_RTC_DRV_CMOS=y`, `CONFIG_RTC_HCTOSYS=y`. **Required.**
- `CONFIG_DEVMEM=y`, `CONFIG_NVRAM=y`, `CONFIG_DEVPORT=y`. **Useful** — Xorg sometimes wants `/dev/mem` and `/dev/port`.
- `# CONFIG_HPET is not set` (this is the `/dev/hpet` userspace device, not the kernel HPET timer — different switch). **Already-good.**
- `# CONFIG_TCG_TPM is not set`. **Already-good.**
- `# CONFIG_HID_SUPPORT is not set` — already noted.
- `# CONFIG_MMC is not set`, `# CONFIG_MEMSTICK is not set`, `# CONFIG_NEW_LEDS is not set`, `# CONFIG_HWMON is not set`, `# CONFIG_THERMAL is not set`, `# CONFIG_WATCHDOG is not set`. **Already-good.**
- `# CONFIG_PARPORT is not set`. **Already-good** (parport for the 560Z is in the separate `parport-modules-*-tcz`, not in the bzImage).
- `CONFIG_DMA_SHARED_BUFFER=y`, `CONFIG_SYNC_FILE=y`, `CONFIG_UDMABUF=y`. **Surface candidates** — these are the dma-buf framework, used by DRM/V4L2/V4L2-mem; with `CONFIG_DRM=n` and `CONFIG_MEDIA_SUPPORT=n`, they're unreferenced.
- `CONFIG_REGMAP=y`, `CONFIG_REGMAP_MMIO=y`. Auto-selected.
- `CONFIG_HAVE_CLK=y`, `CONFIG_COMMON_CLK=y`. Auto-selected.
- `CONFIG_NVMEM=y`. **Surface candidate** — common-NVMEM framework, no NVMEM provider drivers selected.
- `CONFIG_CONNECTOR=y`, `CONFIG_PROC_EVENTS=y`. **Surface candidate** — used for proc-event notifications by some daemons (forkstat, audit-light, …). Not used by busybox.
- `CONFIG_DMIID=y`, `CONFIG_DMI_SYSFS=y`, `CONFIG_DMI=y`, `CONFIG_FIRMWARE_MEMMAP=y`. **Useful** for hardware probing.
- `CONFIG_SYSFB=y`, `# CONFIG_SYSFB_SIMPLEFB is not set`. **Useful.**
- `CONFIG_EEPROM_93CX6=y`. **Required?** — selected by `RTL8192CU`/`RTLWIFI_USB`. Keep.

## Final-pass smaller items

- `CONFIG_LEGACY_TIOCSTI=y`. Old `TIOCSTI` semantics. **Surface candidate** (modern userland doesn't depend on it).
- `CONFIG_MULTIUSER=y`, `CONFIG_UID16=y`, `CONFIG_HAVE_UID16=y`. Single-user systems can sometimes drop `MULTIUSER` (not really, but `UID16` could go). **Surface candidate**, small.
- `CONFIG_SGETMASK_SYSCALL=y`. Obsolete. **Surface candidate.**
- `CONFIG_FHANDLE=y`, `CONFIG_KCMP=y`, `CONFIG_RSEQ=y`, `CONFIG_MEMBARRIER=y`, `CONFIG_CACHESTAT_SYSCALL=y`, `CONFIG_ADVISE_SYSCALLS=y`. Modern syscalls; some glibc versions use them. **Useful?** — verify.

## end of inventory
