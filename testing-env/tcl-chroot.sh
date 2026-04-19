#!/bin/sh
# Run TinyCore Linux 32-bit userspace in a chroot on this x86_64 Debian host.
# /home/tc, /tce, /opt are bind-mounted from the host so paths are identical
# whether you are inside this chroot or booted into TCL from GRUB.
#
# Usage (all commands require root / sudo):
#   sudo ./tcl-chroot.sh setup     — one-time: extract rootfs to CHROOT_DIR
#   sudo ./tcl-chroot.sh mount     — bind-mount host dirs into chroot
#   sudo ./tcl-chroot.sh enter     — chroot as 32-bit (auto-mounts if needed)
#   sudo ./tcl-chroot.sh umount    — release all bind mounts
#   sudo ./tcl-chroot.sh destroy   — umount + delete CHROOT_DIR (destructive)

set -e

ROOTFS=/boottcl/rootfs-17.0.gz
CHROOT_DIR=/var/lib/tcl-chroot
BIND_DIRS="/home/tc /tce /opt"

# Sentinel: if this path exists the cpio has already been extracted
SENTINEL="$CHROOT_DIR/bin/busybox"

die() { echo "ERROR: $*" >&2; exit 1; }

require_root() {
    [ "$(id -u)" -eq 0 ] || die "This command must be run as root (use sudo)."
}

is_mounted() {
    # Return 0 if $1 is a mountpoint inside the chroot
    grep -q " $CHROOT_DIR$1 " /proc/mounts
}

cmd_setup() {
    require_root
    [ -f "$ROOTFS" ] || die "Rootfs not found at $ROOTFS"
    if [ -f "$SENTINEL" ]; then
        echo "Chroot already extracted at $CHROOT_DIR — skipping extraction."
        echo "Run 'destroy' first if you want a fresh extraction."
        return
    fi
    mkdir -p "$CHROOT_DIR"
    echo "Extracting $ROOTFS into $CHROOT_DIR …"
    ( cd "$CHROOT_DIR" && zcat "$ROOTFS" | cpio -idm --quiet )
    # Ensure mount-point dirs exist (TCL rootfs may not ship them)
    mkdir -p "$CHROOT_DIR/proc" "$CHROOT_DIR/sys" "$CHROOT_DIR/dev"
    for d in $BIND_DIRS; do
        mkdir -p "$CHROOT_DIR$d"
    done
    echo "Setup complete. Run 'enter' to start the 32-bit shell."
}

cmd_mount() {
    require_root
    [ -f "$SENTINEL" ] || die "Chroot not set up yet — run 'setup' first."

    # squashfs needed for tce-load inside the chroot
    if ! grep -q squashfs /proc/filesystems 2>/dev/null; then
        /sbin/modprobe squashfs 2>/dev/null || echo "Warning: could not load squashfs module (tce-load may not work)"
    fi

    for d in $BIND_DIRS; do
        if is_mounted "$d"; then
            echo "$d already mounted, skipping."
        else
            mount --bind "$d" "$CHROOT_DIR$d"
            echo "Mounted $d"
        fi
    done

    for d in /proc /sys /dev; do
        if is_mounted "$d"; then
            echo "$d already mounted, skipping."
        else
            mount --bind "$d" "$CHROOT_DIR$d"
        fi
    done
}

cmd_enter() {
    require_root
    [ -f "$SENTINEL" ] || die "Chroot not set up yet — run 'setup' first."
    is_mounted "/proc" || cmd_mount
    echo "Entering 32-bit TCL chroot at $CHROOT_DIR"
    linux32 chroot "$CHROOT_DIR" /bin/sh
}

cmd_umount() {
    require_root
    # Unmount in reverse dependency order
    for d in /dev /sys /proc $(echo "$BIND_DIRS" | tr ' ' '\n' | tail -r 2>/dev/null || echo "$BIND_DIRS" | awk '{for(i=NF;i>=1;i--) printf $i" "}'); do
        target="$CHROOT_DIR$d"
        if grep -q " $target " /proc/mounts 2>/dev/null; then
            umount "$target" && echo "Unmounted $target" || echo "Warning: could not unmount $target"
        fi
    done
}

cmd_destroy() {
    require_root
    cmd_umount
    if [ -d "$CHROOT_DIR" ]; then
        rm -rf "$CHROOT_DIR"
        echo "Deleted $CHROOT_DIR"
    else
        echo "$CHROOT_DIR does not exist, nothing to delete."
    fi
}

cmd_status() {
    if [ ! -d "$CHROOT_DIR" ]; then
        echo "Status: not set up (run setup)"
        return
    fi
    if [ ! -f "$SENTINEL" ]; then
        echo "Status: directory exists but rootfs not extracted"
        return
    fi
    echo "Chroot dir: $CHROOT_DIR"
    echo "Rootfs:     extracted"
    echo ""
    echo "Bind mounts:"
    for d in $BIND_DIRS /proc /sys /dev; do
        if is_mounted "$d"; then
            echo "  $d  [mounted]"
        else
            echo "  $d  [not mounted]"
        fi
    done
}

case "${1:-}" in
    setup)   cmd_setup ;;
    mount)   cmd_mount ;;
    enter)   cmd_enter ;;
    umount)  cmd_umount ;;
    destroy) cmd_destroy ;;
    status)  cmd_status ;;
    *)
        cat <<EOF
Usage: sudo $0 <command>

Commands:
  setup    Extract rootfs-17.0.gz to $CHROOT_DIR (one-time)
  mount    Bind-mount /home/tc, /tce, /opt, /proc, /sys, /dev into chroot
  enter    Enter the 32-bit shell (runs mount automatically if needed)
  umount   Release all bind mounts
  destroy  Release mounts and delete $CHROOT_DIR
  status   Show whether chroot is set up and which dirs are mounted

Typical workflow:
  sudo $0 setup          # once
  sudo $0 enter          # each session; drops you into a 32-bit /bin/sh
  sudo $0 umount         # when done

Inside the chroot, to load TCZ extensions:
  tce-load -i /tce/optional/compiletc.tcz
EOF
        exit 1
        ;;
esac
