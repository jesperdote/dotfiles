# CachyOS setup notes (ThinkPad T14 Gen2)

Captures the system changes made during initial setup, for replaying after a reinstall.

## Usage

```bash
./install.sh
```

Idempotent - safe to re-run. Each step checks current state before changing anything.
Needs an AUR helper (`paru`/`yay`) already available for the AUR package step; CachyOS
ships `paru` by default.

## What's included

| File | Purpose |
|---|---|
| `packages.txt` | Official repo packages (zsh + cachyos-zsh-config + powerlevel10k, docker, docker-compose, docker-buildx, zoxide) |
| `aur-packages.txt` | AUR packages (visual-studio-code-bin, yay) |
| `etc/sudoers.d/90-diagnostics-nopasswd.template` | Passwordless sudo for read-only diagnostic tools (dmesg, journalctl, evtest, libinput) only - no install/modify commands |
| `zsh/zoxide.zsh` | Appended to `~/.zshrc` - makes `cd` use zoxide's fuzzy directory jumping |
| `install.sh` | Ties it all together |

See `../ubuntu-vs-arch-cli.md` (repo root) for a general Ubuntu vs Arch/CachyOS CLI
command reference.

## Shell

CachyOS installer offers a shell choice up front (bash/zsh/fish); this machine was set
up with fish, then switched to zsh (with the `cachyos-zsh-config` package for oh-my-zsh +
powerlevel10k + the autosuggestions/syntax-highlighting plugins, plus `zoxide`).
`install.sh` installs those packages and runs `chsh -s /usr/bin/zsh` if the current shell
isn't already zsh - takes effect on next login. Fish itself is left installed (not
removed) since `/etc/shells` still lists it; remove with `sudo pacman -R fish` if unwanted.

The full `~/.zshrc` and `~/.p10k.zsh` aren't backed up here since they're partly
machine-generated (`p10k configure` regenerates `.p10k.zsh` interactively) - only the
zoxide line that was manually added is captured in `zsh/zoxide.zsh`.

## Touchpad fix (hardware-specific)

This ThinkPad's Synaptics touchpad (`LEN2072`) defaults to legacy PS/2 emulation, which
has weak palm/multi-touch separation and causes phantom cursor movement when your palm
brushes the pad while dragging. The fix is the kernel parameter
`psmouse.synaptics_intertouch=1`, which switches it to the native RMI4/SMBus protocol.
`install.sh` adds this to `/etc/default/limine` and runs `limine-update`.

Side effect: the touchpad becomes a "new" device to the desktop after switching protocols,
so any per-device setting (tap-to-click, sensitivity) resets to default. Tap-to-click
defaults to off anyway, which matches the current preference on this machine - no action
needed unless you want it on.

Only relevant if you're setting up the same physical hardware. Diagnosis process if a
similar issue shows up on different hardware: capture raw events with `evtest` on the
touchpad's `/dev/input/eventN` node, check `dmesg | grep -i synaptics` for protocol/reset
info, and look for `ABS_MT_SLOT` value 1 (second contact point) coinciding with
discontinuous jumps in `ABS_X`/`ABS_Y`.

## Toshy

[Toshy](https://github.com/RedBearAK/toshy) (macOS-style keybinding remapper, via
`xwaykeyz`) is cloned from my fork (https://github.com/jesperdote/Toshy) into
`~/.local/src/toshy` by `install.sh` (re-running does a `git pull` rather than
re-cloning). The actual `./setup_toshy.py install` step is **not** run automatically -
the installer has intentional "type this secret code to confirm you read this" gates
(for the unprivileged-install path and an `.Xmodmap` warning) plus several plain y/n
prompts (system-updated check, PATH, KDE/KWin script, sudo capability). These are
deliberately built to prevent unattended/scripted installs, so `install.sh` just clones
the repo and prints the command to run interactively:

```bash
cd ~/.local/src/toshy && ./setup_toshy.py install
```

If modifier keys end up in the wrong place afterward, run `toshy-devices` to identify
your keyboard and add it to the Toshy config (see Toshy's README for specifics).

## Not covered by this script

- **VS Code** sign-in/settings sync - manual, account-based.
- Bootloader assumption: this assumes **Limine** (CachyOS default). If a future install
  uses GRUB or systemd-boot instead, the touchpad kernel-param step needs adapting to
  that bootloader's config location.
