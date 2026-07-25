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
| `etc/sysctl.d/99-nmi-watchdog-enable.conf` | Re-enables the NMI hardlockup watchdog that CachyOS disables by default |
| `etc/udev/rules.d/70-magic-trackpad-bt.rules.template` | Stable symlink for the Bluetooth Magic Trackpad (its `/dev/input/eventN` changes every reconnect) |
| `etc/udev/rules.d/61-hotplug.rules.template` | Restarts the three-finger-drag service the instant the trackpad reconnects |
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

## Freeze diagnostics: kernel lockup watchdogs

This machine had intermittent freezes during active use that required a forced restart,
with zero trace in the logs afterward - no MCE, no OOM-kill, no GPU-reset signature,
nothing. The reason: two separate settings disable the kernel's lockup detectors
entirely, so a hang just sits there silently instead of logging anything.

1. `nowatchdog` on the kernel command line (`/etc/default/limine`) - not part of the
   touchpad fix above; it was very likely picked up incidentally during the same
   2026-06-22 touchpad-debugging session (multiple `limine-update` runs that morning),
   since it has no relation to touchpad behavior.
2. `kernel.nmi_watchdog = 0` in `/usr/lib/sysctl.d/70-cachyos-settings.conf` - a CachyOS
   package default (ships with the distro, not something this machine's owner set),
   which re-disables the NMI hardlockup watchdog via sysctl moments after boot even once
   `nowatchdog` is removed from the cmdline.

`install.sh` removes `nowatchdog` and installs `etc/sysctl.d/99-nmi-watchdog-enable.conf`
(sorts after CachyOS's own `70-` file alphabetically, so it wins). Neither change stops a
freeze from happening, but if one occurs again, the kernel should now log
`BUG: soft/hard lockup - CPU#N stuck` with a stack trace pointing at whatever's actually
hung, instead of leaving nothing to investigate. Check `cat /proc/sys/kernel/watchdog`
and `cat /proc/sys/kernel/nmi_watchdog` both read `1` to confirm both are active - a
future CachyOS update could silently reset the sysctl default again.

## Magic Trackpad + three-finger drag (Bluetooth, hardware-specific)

An Apple Magic Trackpad is paired over Bluetooth for macOS-style multitouch. Two
quirks worth knowing if this breaks after a reinstall or a new pairing:

- **Won't pair while a cable is plugged in.** Magic Trackpads fall back to acting as a
  wired USB HID device whenever a cable is connected (charging or otherwise), and won't
  complete Bluetooth pairing in that state - unplug it first, then toggle the power
  switch off/on to re-enter pairing mode.
- **Invisible in System Settings.** KDE's Mouse/Touchpad pages never list it - KWin's own
  D-Bus `InputDevice` object flags it `isVirtual: true`, because Bluetooth HID devices
  are injected via the kernel's `uhid` subsystem, putting their sysfs path under
  `/devices/virtual/...`. It's still fully functional at the libinput/KWin level despite
  being hidden from the GUI (confirmed via
  `busctl --user introspect org.kde.KWin /org/kde/KWin/InputDevice/eventN`). This likely
  affects any Bluetooth mouse/touchpad on this machine, not just this one.

KDE/KWin doesn't expose a native three-finger-*drag* toggle (only tap-and-drag, which is
a different gesture) - confirmed absent from the same D-Bus interface above - so this
uses [linux-3-finger-drag](https://github.com/jesperdote/linux-3-finger-drag) (my fork of
[lmr97's tool](https://github.com/lmr97/linux-3-finger-drag)), a small Rust daemon that
exclusively grabs the touchpad and synthesizes the drag via `uinput`. `install.sh` clones
it to `~/src/linux-3-finger-drag` and installs the two udev rule templates above, but
does **not** build/install/enable it - that needs Rust (`rustup default stable`) and the
tool's own sudo-gated installer (`sudo ./install.sh` from that directory), printed as a
manual step. After that, `~/.config/systemd/user/three-finger-drag.service`'s `ExecStart`
needs `--device /dev/input/magic-trackpad-bt-event` appended by hand - this machine has
two touchpads (built-in Synaptics + the Magic Trackpad), and the tool's auto-discovery
silently picks the wrong one otherwise.

Trade-off accepted: exclusively grabbing the trackpad breaks the pre-existing
`~/.config/libinput-gestures.conf` 3-finger/4-finger swipe-to-action bindings (Present
Windows, Minimize/Maximize, desktop switching) on the Magic Trackpad specifically, since
`libinput-gestures` only sees a synthetic clone that deliberately omits
3-finger-drag-shaped input. Those bindings still work fine on the built-in touchpad.

If the fork's `61-hotplug.rules` is ever reinstalled verbatim (unscoped, matching every
`SUBSYSTEM=="input"` event) instead of the templated version here, it will restart the
service in response to its own synthetic `uinput` clone appearing at every startup,
causing an infinite restart loop that trips systemd's start-rate limit within seconds.
The templated version here is scoped to the trackpad's own `ATTRS{uniq}`/vendor/product
specifically to avoid that.

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
- **Magic Trackpad Bluetooth pairing** - runtime action, not a config file; see above.
- **linux-3-finger-drag build/install** - needs Rust + its own sudo-gated installer +
  a manual `ExecStart` edit; see above.
