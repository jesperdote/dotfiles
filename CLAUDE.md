# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A personal multi-machine dotfiles/system-setup repo: one top-level folder per
machine/OS, each independently reproducible. There is no build, lint, or test step
anywhere in this repo - every machine folder is a bash script plus static config
snippets.

## Structure

- One folder per machine: `cachyos/` (ThinkPad T14 Gen2 running CachyOS) and `vps/`
  (homelab VPS, "caljerry", Ubuntu 26.04 LTS). When adding a new machine, create a new
  top-level folder following the same internal pattern: an idempotent `install.sh`
  entry point, package lists as plain text files where applicable, and a README
  documenting machine-specific rationale (hardware quirks, why a given fix exists,
  what's deliberately left manual).
- Folders are independent - nothing is shared between them. Don't introduce cross-folder
  imports/sourcing; if logic is genuinely common across OSes (e.g. zoxide setup), it's
  fine to duplicate the small snippet in each folder rather than build shared tooling,
  given how little there is.
- `ubuntu-vs-arch-cli.md` at the root is general reference material, not tied to a
  specific machine folder.

## Commands

Each machine folder is self-contained - `cd` into it and run its own `install.sh`:

```bash
cd cachyos && ./install.sh
```

Validate a script after editing it (no test suite exists anywhere in this repo):

```bash
bash -n cachyos/install.sh
```

## cachyos/ specifics

See `cachyos/README.md` for full rationale. Key points a future session should know
before editing anything in that folder:

- Each step in `install.sh` is individually idempotent (checks current state before
  acting) - there's no single "already ran" marker for the whole script.
- `cachyos/etc/sudoers.d/90-diagnostics-nopasswd.template` uses a `__USER__` placeholder
  substituted via `sed` at install time, not deployed verbatim. Keep that rule scoped to
  read-only diagnostics only (`dmesg`, `journalctl`, `evtest`, `libinput`) - don't widen
  it to install/modify commands without deliberate reconsideration.
- The touchpad fix (`psmouse.synaptics_intertouch=1` via `/etc/default/limine` +
  `limine-update`) is specific to this exact Synaptics touchpad (`LEN2072`) and assumes
  the **Limine** bootloader. Not portable to other hardware/bootloaders without
  adaptation.
- Toshy is cloned/pulled automatically but its `./setup_toshy.py install` is
  deliberately **not** run automatically - that installer has intentional "type this
  secret code to confirm you read this" prompts meant to block unattended installs.
  Don't try to script around them; leave that step manual.
