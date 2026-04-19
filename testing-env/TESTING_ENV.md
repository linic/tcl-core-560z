# Testing Environment for TCL 32-bit Userspace

Branch: `testing-env-setup`
Goal: Run TinyCore Linux's 32-bit userspace on this Debian/Phenom II machine so that
programs compiled for the IBM ThinkPad 560Z can be tested quickly — without a physical
560Z or a full VM per test run.

---

## State at session start

### Key facts discovered

- **UUID = same partition**: The GRUB menuentry's `tce=UUID="ab289eda-4e92-4c53-994d-1b7cfdef0d8e"`
  is `/dev/sda1`, the Debian root. So `/home/tc`, `/tce`, `/opt`, `/boottcl` are all
  plain directories on the live Debian filesystem — not on a separate TCL partition.
  "Same paths" is already true from the storage perspective; the challenge is only
  within the guest/container.

- **rootfs-17.0.gz**: gzip'd cpio archive (~9 MB compressed). 675 files. Contains a
  32-bit busybox userspace with `lib/ld-linux.so.2`, `lib/libc.so.6`,
  and `/usr/bin/tce-load`.

- **vmlinuz64-17.0**: 64-bit kernel (6.18.2-tinycore64). Used as-is for GRUB boot;
  also suitable for a QEMU guest.

- **Tools available on host Debian**: `linux32`, `setarch` (util-linux), `/dev/kvm`
  present, squashfs module at `/lib/modules/$(uname -r)/kernel/fs/squashfs/squashfs.ko.xz`.
  QEMU **not** installed.

- **TCE extensions**: 197 in `/tce/optional/`, 18 in `/tce/onboot.lst` including
  `compiletc.tcz`, `valgrind.tcz`, `cmake.tcz`.

- **`/opt/bootlocal.sh`** exists on host Debian (standard TCL post-boot hook, mostly
  empty). `/opt/bootsync.sh` calls it.

### What is NOT here yet

- No extracted chroot directory
- No QEMU install
- No test scripts

---

## Plan

- [x] Phase 0: Research and journal (this file)
- [ ] Phase 1: chroot setup script (`tcl-chroot.sh`) — low-risk, no new packages needed
- [ ] Phase 2: QEMU guide — needs Q1, Q3 answered (see below); deferred to next session
- [ ] Phase 3: Optional integration into `Makefile` or `daily-tools/`

---

## Approach A — chroot (Phase 1, implemented here)

Extract `rootfs-17.0.gz` once to a persistent directory. Bind-mount the host's
`/home/tc`, `/tce`, `/opt` into the chroot at the same paths. Enter with `linux32 chroot`.

**Why this satisfies "same paths":**
The chroot's `/home/tc` and `/tce` are bind-mounts of the host directories. Any file
written there in the chroot is visible on the host and vice-versa — no syncing needed.

**How to run TCZ extensions inside the chroot:**
`.tcz` files are SquashFS images. `tce-load -i` from the TCL rootfs mounts them and
installs their files. The host squashfs module must be loaded first:
```
sudo /sbin/modprobe squashfs
```
Then inside the chroot, `tce-load -i /tce/optional/compiletc.tcz` should work.

**Caveat:** TCZ extensions that ship kernel modules will mount/copy them into the chroot
but they will interact with the host kernel (same kernel namespace). For userspace-only
extensions this is harmless.

---

## Approach B — QEMU + virtfs (Phase 2, not yet implemented)

Boot TCL in a QEMU VM using the existing kernel and initrd from `/boottcl/`. Share
`/home/tc`, `/tce`, `/opt` into the guest via QEMU's `-virtfs` (9p/VirtFS). The guest
mounts these shares in `bootlocal.sh` at the same canonical paths.

**Why this is better than passing `/dev/sda1` directly:** Two kernels accessing the
same ext4 filesystem simultaneously would risk corruption.

**Sketch of the QEMU command** (once qemu-system-x86 is installed):
```sh
sudo qemu-system-x86_64 \
  -enable-kvm \
  -m 512 \
  -kernel /boottcl/vmlinuz64-17.0 \
  -initrd "/boottcl/rootfs-17.0.gz /boottcl/modules64-17.0.gz" \
  -append "showapps lang=fr_CA.UTF-8 nodhcp" \
  -virtfs local,path=/home/tc,mount_tag=home_tc,security_model=none \
  -virtfs local,path=/tce,mount_tag=tce_share,security_model=none \
  -virtfs local,path=/opt,mount_tag=opt_share,security_model=none \
  -nographic -serial mon:stdio
```

**The `/opt/bootlocal.sh` additions needed in the guest:**
```sh
mount -t 9p -o trans=virtio,version=9p2000.L home_tc /home/tc
mount -t 9p -o trans=virtio,version=9p2000.L tce_share /tce
mount -t 9p -o trans=virtio,version=9p2000.L opt_share /opt
```

**Problem:** If `/opt` is shared via virtfs and TCL reads `bootlocal.sh` from the
guest's in-RAM `/opt` before the 9p mount happens, the mounts won't run at boot.
TCL's `opt=` parameter causes TCL to copy `/opt` from the backing device early in
init — but with 9p there is no `opt=` UUID. A workaround is to embed the mount
commands in a custom initrd overlay. This needs more research and Nic's input (see Q3).

---

## Log

### 2026-04-19 — Session 1

- Researched the environment; all findings recorded under "State at session start".
- Confirmed UUID = sda1 (same-partition insight).
- Phase 1 implemented: `tcl-chroot.sh` committed alongside this journal.
- Phase 2 sketched but deferred — blocked on Q1 and Q3.

---

## Clarifying questions for Nic

**Q1: What is the primary testing use case?**
  (a) Run a compiled binary and check exit code / output
  (b) Test full TCL extension loading (tce-load, onboot.lst)
  (c) Both — need the full TCL experience
  My guess: (a) for now, (c) eventually. Phase 1 covers (a) and partial (b).

**Q2: Persistent chroot directory at `/var/lib/tcl-chroot` — OK?**
The extracted rootfs is ~35 MB. Persistent avoids re-extracting (~5 s) on each
session. Alternative: extract into `/tmp` on every invocation (slower but auto-cleaned).
My guess: persistent is fine; you have plenty of disk.

**Q3: For QEMU — is modifying `/opt/bootlocal.sh` on the Debian host acceptable?**
The QEMU guest would read this file (via virtfs) at boot. Any additions would also be
visible when booting from GRUB (TCL reads `bootlocal.sh` from the partition). If we
want separate behavior, we'd need a different mechanism (e.g., an initrd overlay or
a kernel cmdline env var guard). My guess: a guard (`[ -d /sys/bus/virtio ]`) to
run 9p mounts only inside a VM.

---

## Decisions made without input

1. **Persistent chroot at `/var/lib/tcl-chroot`** — avoids extracting 9 MB on every
   session. Reversible: `sudo rm -rf /var/lib/tcl-chroot` and re-run setup.

2. **Not including QEMU in Phase 1** — too many open questions about `bootlocal.sh`
   interaction. Documenting the sketch here so the next session can pick it up.

3. **Not touching `/opt/bootlocal.sh`** — leaving it unchanged until Q3 is answered.

---

## Things out of scope / left alone

- Kernel module testing (requires physical 560Z or full QEMU boot)
- Cross-compilation changes (handled by existing Docker workflow)
- Network configuration inside the chroot / QEMU guest
- Automating `tce-load` for all `onboot.lst` entries at chroot entry (can be added later)
