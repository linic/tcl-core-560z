# generate-patches.sh — design v1.0

## Goal

Move `cs4237b/generate-patches.sh` to `tools/generate-patches.sh`, improve it
to follow the same conventions as the other revamped tools (`pick-patches.sh`,
`pick-config.sh`), and fix the source-dir / patch-dir naming mismatch.

## Background

The revamp (Phases 1–3, TOOLS_REVAMP.md) introduced suffix-based naming for
both `.config-*` and `patches-*` directories. `generate-patches.sh` was left
out of scope. The last commit on `improving_compile_scripts` (994b51b) fixed a
mkdir path bug but noted:

> "the output dir still gets named by the full source version (e.g.
> patches-6.18.8) while the build now reads from the suffix (patches-6.18).
> Aligning those is a separate concern."

The patch-dir names in `cs4237b/` were renamed to suffix form (patches-4,
patches-5, patches-6.18) in the 2026-04-19 session. The source dirs currently
include `source-6.18.8` (full version) alongside `source-4`, `source-5`,
`source-6` (suffix form).

## Invocation

Called manually from inside `cs4237b/` after editing the source files:

```sh
../tools/generate-patches.sh 6.18.8
```

The script is never called from automated flows (Docker, Makefile). No caller
changes required.

## Interface

```
generate-patches.sh <VERSION_TRIPLET>
```

`VERSION_TRIPLET` is a full kernel version like `6.18.8` or `6.12.65`. The
script calls `get_suffix` from `common.sh` to derive `SUFFIX` internally.

## Directory resolution (source and patches)

Input source dir lookup — suffix-first with full-version fallback, mirroring
the CIP fallback in `pick-patches.sh`:

```
SOURCE="source-$SUFFIX"
if [ ! -d "$SOURCE" ] && [ -d "source-$1" ]; then
    SOURCE="source-$1"
fi
```

Output patches dir — suffix-only (matches how `pick-patches.sh` and
Dockerfile consume patches):

```
PATCH="patches/patches-$SUFFIX"
```

`mkdir -pv "$PATCH"` creates it if absent.

## normalize_patch_header helper

The current script repeats this 3-line `sed` block once per patched file (×4):

```sh
sed -i '1,2s/<from-path>.orig/<a-relative-path>/g' <file>
sed -i '1,2s/<from-path>/<b-relative-path>/g'      <file>
sed -i '1,2s/\([^ ]*\)\t.*/\1/'                    <file>
```

Extract into:

```sh
normalize_patch_header() {
  FILE=$1
  ORIG_PATH=$2   # e.g. sound/isa/wss/wss_lib.c
  sed -i "1,2s|.*/${ORIG_PATH}\.orig|a/${ORIG_PATH}|g" "$FILE"
  sed -i "1,2s|.*/${ORIG_PATH}|b/${ORIG_PATH}|g"       "$FILE"
  sed -i '1,2s/\([^ ]*\)\t.*/\1/' "$FILE"
}
```

Using `|` as the sed delimiter avoids escaping the `/` in paths.

The four calls become:

```sh
normalize_patch_header "$PATCH/wss_lib.c.patch"    "sound/isa/wss/wss_lib.c"
normalize_patch_header "$PATCH/cs4236_lib.c.patch" "sound/isa/cs423x/cs4236_lib.c"
normalize_patch_header "$PATCH/cs4236.c.patch"     "sound/isa/cs423x/cs4236.c"
normalize_patch_header "$PATCH/wss.h.patch"        "sound/isa/include/sound/wss.h"
```

OQ-1: The existing `sed` for `wss.h.patch` targets `include/sound/wss.h` in
the file but the path argument passed to normalize is `include/sound/wss.h`,
not `sound/include/sound/wss.h`. The actual `diff -u` header will contain
`source-$SUFFIX/include/sound/wss.h.orig` and `source-$SUFFIX/include/sound/wss.h`.
The `.*` prefix in the sed pattern matches everything up to and including the
last `/` before the target path, so this should work regardless — confirm.

## Skeleton

```sh
#!/bin/sh
# Copyright header
. "$(dirname "$0")/common.sh"

usage() { ... }

normalize_patch_header() { FILE=$1; ORIG_PATH=$2; ... }

generate_patches() {
  if ! get_suffix "$@"; then return 1; fi

  SOURCE="source-$SUFFIX"
  if [ ! -d "$SOURCE" ] && [ -d "source-$1" ]; then
    SOURCE="source-$1"
  fi
  if [ ! -d "$SOURCE" ]; then
    echo "No source dir for $1 (tried source-$SUFFIX and source-$1)"
    return 1
  fi

  PATCH="patches/patches-$SUFFIX"
  mkdir -pv "$PATCH"

  diff -u $SOURCE/sound/isa/wss/wss_lib.c.orig       $SOURCE/sound/isa/wss/wss_lib.c       > $PATCH/wss_lib.c.patch
  diff -u $SOURCE/sound/isa/cs423x/cs4236_lib.c.orig $SOURCE/sound/isa/cs423x/cs4236_lib.c > $PATCH/cs4236_lib.c.patch
  diff -u $SOURCE/sound/isa/cs423x/cs4236.c.orig     $SOURCE/sound/isa/cs423x/cs4236.c     > $PATCH/cs4236.c.patch
  diff -u $SOURCE/include/sound/wss.h.orig            $SOURCE/include/sound/wss.h           > $PATCH/wss.h.patch

  normalize_patch_header "$PATCH/wss_lib.c.patch"    "sound/isa/wss/wss_lib.c"
  normalize_patch_header "$PATCH/cs4236_lib.c.patch" "sound/isa/cs423x/cs4236_lib.c"
  normalize_patch_header "$PATCH/cs4236.c.patch"     "sound/isa/cs423x/cs4236.c"
  normalize_patch_header "$PATCH/wss.h.patch"        "include/sound/wss.h"
}

main() {
  if [ $# -ne 1 ]; then usage; exit 1; fi
  case "$1" in
    *.*.*)  generate_patches "$1" ;;
    *)      usage; exit 1 ;;
  esac
  exit "$?"
}

main "$@"
```

## File location and callsite

| Before | After |
|--------|-------|
| `cs4237b/generate-patches.sh` | `tools/generate-patches.sh` |
| Called as `./generate-patches.sh 6.18.8` from `cs4237b/` | Called as `../tools/generate-patches.sh 6.18.8` from `cs4237b/` |

The old file is deleted. TOOLS_REVAMP.md "Things out of scope" line is updated
to remove `generate-patches.sh` and note that it was moved.

## TOOLS_REVAMP.md update

- Remove `generate-patches.sh` from "Things out of scope / left alone"
- Add a Phase 7 entry (or fold into Phase 4 tidy) noting the move and improvements
