# CLAUDE.md — tcl-core-560z

This repo builds a custom TinyCore Linux kernel and `core.gz` for the IBM ThinkPad 560Z (Pentium II, 64 MB RAM). Read this file before doing anything else in this repo.

## Purpose

The 560Z has too little RAM to boot recent TinyCore Linux with the stock kernel. This repo produces a minimal custom kernel and root filesystem that fits. It also carries a custom ALSA driver for the CS4237B sound chip (`cs4237b/`), which the stock `snd-cs4236` driver fails to support on this machine.

## Branching

Per COLLAB.md: **never commit directly to `main`**. Always work on a named branch.

Exception: the `cs4237b-clean-driver-wip` branch is the active branch for the CS4237B driver rewrite — see `cs4237b/docs/STATUS.md` for current state before touching anything in `cs4237b/`.

## Build

Artifacts are produced by Docker:

```bash
make          # edit-config → build → publish (copies artifacts to release/)
```

Output lands in `release/<kernel>.<tcl-major>.<iteration>/` (e.g. `release/6.12.65.17.1/`).

## Releasing on GitHub

See `collaboration/RELEASING_ON_GITHUB.md` for the full process. Summary:

1. Verify the release commit and tag name
2. Create local tag if missing: `git tag <version> <commit>`
3. Push tag: `HOME=/home/linic git push origin <version>`
4. Run `gh release create` with assets from `release/<version>/`, using `README.md` in that directory as the release body
5. Exclude `linic.asc` (and `.sig` files if not yet set up in this environment)

## CS4237B driver

- Source: `cs4237b/`
- Active branch: `cs4237b-clean-driver-wip`
- **Read `cs4237b/docs/STATUS.md` first** — it is the source of truth for what is done vs. pending
- Design docs: `cs4237b/docs/01-why-the-hacks-make-it-work.md`, `02-menuconfig-plan.md`
- Compile and boot tests require the physical 560Z — Claude cannot run them

## git / SSH

Push operations require a workspace-specific prefix. See `collaboration/COLLAB.md` → "Pushing from this workspace".
