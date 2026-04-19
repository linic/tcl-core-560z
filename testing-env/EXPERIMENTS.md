# Experiment Log — Testing Environment

Chronological log of every test run to validate `tcl-chroot.sh` and explore
unprivileged alternatives. Date: 2026-04-19.

Format for each experiment:
- **Hypothesis:** what we expected
- **Commands:** exact commands run
- **Result:** raw output summary
- **Finding:** what it means

---

## Exp 1 — Is passwordless sudo available?

**Hypothesis:** If `sudo -n` works, we can run the real `./tcl-chroot.sh setup`.

**Commands:**
```sh
sudo -n true; echo "exit=$?"
```

**Result:** `sudo: a password is required` / `exit=1`.

**Finding:** No passwordless sudo. The real `tcl-chroot.sh` flow cannot be
exercised from Claude's shell. Fall back to unprivileged alternatives.

---

## Exp 2 — What unprivileged chroot tools are installed?

**Hypothesis:** `bwrap` or `proot` would let us chroot without sudo.

**Commands:**
```sh
which bwrap proot unshare fakeroot fakechroot
```

**Result:** only `unshare` and `fakeroot` found. No `bwrap`, no `proot`.

**Finding:** We'll have to use `unshare` with user namespaces.

---

## Exp 3 — Are user namespaces enabled?

**Commands:**
```sh
cat /proc/sys/kernel/unprivileged_userns_clone
cat /proc/sys/user/max_user_namespaces
```

**Result:** `1` and `63563`. Enabled.

**Finding:** `unshare --user --map-root-user` is usable.

---

## Exp 4 — Extract rootfs without root

**Hypothesis:** cpio will fail on device-node entries but succeed on the rest.

**Commands:**
```sh
mkdir -p /tmp/tcl-dryrun && cd /tmp/tcl-dryrun
zcat /boottcl/rootfs-17.0.gz | cpio -idm --quiet
```

**Result:** Long list of `cpio: dev/XXX: Cannot mknod: Operation not permitted`
errors. Every non-device file extracted successfully. `bin/busybox` present,
`file` reports it as `ELF 32-bit LSB executable, Intel i386`. Total: 9.4 MB.

**Finding:** Confirms rootfs is 32-bit i386 userspace. mknod requires real root.
For chroot purposes, we can bind-mount the host's `/dev` instead.

---

## Exp 5 — Extract inside a user namespace

**Hypothesis:** `unshare --user --map-root-user` fakes root enough to let mknod
succeed on tmpfs.

**Commands:**
```sh
unshare --user --map-root-user --mount sh -c '
  rm -rf /tmp/tcl-ns && mkdir -p /tmp/tcl-ns && cd /tmp/tcl-ns
  zcat /boottcl/rootfs-17.0.gz | cpio -idm'
```

**Result:** Same mknod errors. Non-device files extract fine.

**Finding:** Kernel blocks device-node creation even inside user namespaces
(security hardening). Must bind-mount `/dev` from host.

---

## Exp 6 — `mount --bind` inside user NS

**Hypothesis:** Bind mounts should work in a mount namespace.

**Commands:**
```sh
unshare --user --map-root-user --mount sh -c '
  cd /tmp/tcl-ns
  mount --bind /proc proc'
```

**Result:** `mount: /tmp/tcl-ns/proc: wrong fs type, bad option, bad superblock on /proc…`

**Finding:** Plain `--bind` fails on pseudo-filesystems (`/proc`, `/sys`, `/dev`)
because their mount records carry flags the unprivileged caller cannot reapply.

---

## Exp 7 — `mount --rbind` instead

**Hypothesis:** Recursive bind avoids the re-flagging issue.

**Commands:**
```sh
unshare --user --map-root-user --mount sh -c '
  cd /tmp/tcl-ns
  mount --rbind /proc proc && echo OK'
```

**Result:** `OK`. Same for `/sys`, `/dev`, `/home/tc`, `/tce`, `/opt`.

**Finding:** Use `--rbind` for pseudo-filesystems. This is a one-line change to
`tcl-chroot.sh` to consider, though the sudo version doesn't need it (real root
works with plain `--bind`).

---

## Exp 8 — Full chroot + `linux32`

**Hypothesis:** Combining the above gives a working 32-bit shell.

**Commands:**
```sh
unshare --user --map-root-user --mount sh -c '
  cd /tmp/tcl-ns
  mount --rbind /tce tce
  mount --rbind /opt opt
  mount --rbind /proc proc
  mount --rbind /sys sys
  mount --rbind /dev dev
  linux32 /usr/sbin/chroot . /bin/sh -c "
    uname -m
    ls /tce/optional/ | wc -l
    head -5 /tce/onboot.lst"'
```

**Result:**
```
i686
197
vim.tcz
tmux.tcz
getlocale.tcz
mylocale.tcz
firmware-amdgpu.tcz
```

**Finding:** **Core goal achieved unprivileged.** 32-bit personality set,
`/tce/optional/` visible at the same path (197 extensions), onboot list visible.
This validates the mechanical design of `tcl-chroot.sh`.

---

## Exp 9 — Run 32-bit binaries from the rootfs

**Commands (inside chroot):**
```sh
/bin/busybox | head -1
/bin/sh -c 'echo hello PID $$'
```

**Result:** `BusyBox v1.36.1 …` / `hello PID 7492`

**Finding:** 32-bit ELF runs fine under the `linux32` personality on the x86_64
host. We can execute anything shipped in the rootfs.

---

## Exp 10 — Access `/home/tc` (the real one)

**Hypothesis:** Bind-mounted `/home/tc` is readable inside the chroot.

**Commands (inside chroot):**
```sh
ls /home/tc
```

**Result:** `ls: can't open '/home/tc': Permission denied`.

**Also tested on host (no chroot):**
```sh
ls -lad /home/tc
# drwxr-s--- 11 1001 staff 4096 Apr 19 07:30 /home/tc
ls /home/tc/
# ls: cannot open directory '/home/tc/': Permission denied
```

**Finding:** `/home/tc` is owned by uid 1001 (tc), gid 50 (staff), mode 0750.
linic (uid 1000) is not in group staff, so *the host shell can't read it either*.
User namespaces cannot bypass this — the kernel checks the **outer** uid/gid for
filesystem access.

**Fix requires sudo:**
- `sudo usermod -aG staff linic` + re-login → gains read access via group
- To also gain **write** access: `sudo chmod g+w /home/tc` (mode 0770).

---

## Exp 11 — Is `tc` defined in the rootfs?

**Commands:**
```sh
grep -E '^tc:|^staff:' /tmp/tcl-ns/etc/passwd /tmp/tcl-ns/etc/group
```

**Result:**
```
/tmp/tcl-ns/etc/passwd:tc:x:1001:50:Linux User,,,:/home/tc:/bin/sh
/tmp/tcl-ns/etc/group:staff:x:50:
```

**Finding:** tc=1001, staff=50 — **identical to host uid/gid**. That's why the
same partition works whether booted from GRUB (tc as uid 1001) or from Debian
(user files have uid 1001 on disk).

---

## Exp 12 — `su - tc` inside the chroot

**Hypothesis:** Becoming the tc user would let us run `tce-load`.

**Commands (inside chroot, as NS-root):**
```sh
su - tc -c 'id; uname -m'
```

**Result:** `su: can't set groups: Operation not permitted`

**Finding:** Inside a user NS, `setgroups(2)` is disabled by default (security
measure). `su` can't drop privileges to tc.

**Workaround would be:** `unshare --user --map-root-user --setgroups allow …`
but `allow` requires real CAP_SETGID in the parent — which we don't have.

**With real sudo-based chroot:** `su - tc` works normally.

---

## Exp 13 — squashfs module available?

**Commands (on host, then inside chroot):**
```sh
ls /lib/modules/$(uname -r)/kernel/fs/squashfs/   # on host
grep squash /proc/filesystems                      # inside chroot
```

**Result:** `squashfs.ko.xz` present on host. Not loaded. Chroot inherits host's
`/proc/filesystems` via `--rbind` — no squashfs entry until it's loaded.

**Finding:** `modprobe squashfs` needs real root; user NS can't load kernel
modules. This means `tce-load` inside an unprivileged chroot will fail to mount
`.tcz` files.

---

## Exp 14 — Direct squashfs mount attempt

**Commands (inside chroot):**
```sh
mount -t squashfs /tce/optional/bash.tcz /tmp/squash-test
```

**Result:** `mount: permission denied (are you root?)`

**Finding:** Even as NS-root, mounting filesystem types requires CAP_SYS_ADMIN
in the *init* user NS for this kind of mount source. No go without real root.

---

## Exp 15 — `tce-load` self-check

**Commands (inside chroot, as NS-root):**
```sh
tce-load -i /tce/optional/bash.tcz
```

**Result:** `Don't run this as root.`

**Finding:** TCL's `tce-load` explicitly refuses root. It's designed to run as
the tc user. Combined with Exp 12 (`su - tc` blocked in user NS), this is a
second reason tce-load won't work unprivileged.

---

## Exp 16 — Substitute `/home/linic` for `/home/tc`

**Hypothesis:** If we bind-mount `/home/linic` (which linic owns) as `/home/tc`
inside the chroot, write operations succeed.

**Commands:**
```sh
mount --rbind /home/linic /tmp/tcl-ns/home/tc
# chroot
touch /home/tc/.tcl-chroot-write-test && rm /home/tc/.tcl-chroot-write-test
```

**Result:** Write succeeded.

**Finding:** Useful as a dev-loop trick. **But it breaks the "same paths" goal**:
the chroot's `/home/tc` no longer mirrors what TCL-from-GRUB sees. Only a valid
workaround for mechanical testing of scripts that don't need the real tc home.

---

## Exp 17 — Any compiler in the base rootfs?

**Commands (inside chroot):**
```sh
which gcc cc
```

**Result:** Both missing.

**Finding:** As expected — `compiletc.tcz` ships gcc. So `build-locally.sh` can't
run end-to-end in this environment without loading that .tcz, which needs real
root (Exp 13/14/15). Unprivileged mode can only validate shell scripts and
run pre-compiled 32-bit binaries.

---

## Summary table

| Need                                 | Works unprivileged? | Requires sudo? |
|--------------------------------------|---------------------|----------------|
| Extract rootfs (non-dev files)       | ✓                   | —              |
| Bind-mount host dirs                 | ✓ (`--rbind`)       | —              |
| `chroot` + `linux32` → i686 shell    | ✓                   | —              |
| Run 32-bit binaries from rootfs      | ✓                   | —              |
| Read/write `/home/tc` (real)         | ✗                   | yes (see §fix) |
| `mknod /dev/*`                       | ✗                   | yes            |
| `modprobe squashfs`                  | ✗                   | yes            |
| `mount -t squashfs …`                | ✗                   | yes            |
| `tce-load -i foo.tcz`                | ✗                   | yes            |
| Compile via `compiletc.tcz`          | ✗ (needs tce-load)  | yes            |
| Run `build-locally.sh` end-to-end    | ✗                   | yes            |

## §fix — unblocking the real smoke test

Two options:

**Option A — Run the real script as root (simplest):**
```sh
sudo /home/code/mes-repertoires-git/tcl-core-560z/testing-env/tcl-chroot.sh setup
sudo /home/code/mes-repertoires-git/tcl-core-560z/testing-env/tcl-chroot.sh enter
# inside: su - tc, then run build-locally.sh
```

**Option B — Give linic read/write access to /home/tc (per Nic's suggestion):**
```sh
sudo usermod -aG staff linic           # add linic to staff group
sudo chmod g+w /home/tc                # also grant write (setgid already set)
# log out + log back in so linic's processes pick up the new group
# then the unshare approach above works end-to-end as linic
```

Option B keeps everything unprivileged once set up, but still can't load TCZ
extensions (squashfs mount needs real root). So for `build-locally.sh` which
calls `tce-load`, Option A is the only complete path.

## Cleanup after experiments

```sh
# The /tmp/tcl-ns dir used throughout has kernel mounts that will survive
# the unshare exit (user NS reaps them, but the dir persists). Clean up:
rm -rf /tmp/tcl-ns /tmp/tcl-dryrun /tmp/rootfs-peek
```
