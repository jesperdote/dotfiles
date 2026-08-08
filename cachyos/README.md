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
| `etc/udev/rules.d/70-magic-trackpad.rules.template` | Stable symlink for the Magic Trackpad regardless of Bluetooth vs USB connection |
| `etc/udev/rules.d/61-hotplug.rules.template` | Restarts the three-finger-drag service the instant the trackpad (re)connects, either connection |
| `etc/systemd/system-sleep/90-trackpad-resume-fix.sh` | Rebinds the touchpad and restarts Toshy on every resume, fixing a dead-touchpad-after-suspend bug |
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

## Power button locks screen (macOS-style)

By default KDE's power button either sleeps or shows a shutdown prompt. `install.sh` sets
it to lock the screen instead (like tapping the power button on a MacBook), via
`kwriteconfig6 --file powerdevilrc --group <AC|Battery> --group SuspendAndShutdown --key
PowerButtonAction 32`. `32` isn't arbitrary - it's `PowerDevil::PowerButtonAction::LockScreen`
from [powerdevil's enum](https://github.com/KDE/powerdevil/blob/master/daemon/powerdevilenums.h):
`NoAction=0, Sleep=1, Hibernate=2, Shutdown=8, PromptLogoutDialog=16, LockScreen=32,
TurnOffScreen=64, ToggleScreenOnOff=128`. No GUI option needed to change it further - System
Settings -> Power Management -> Button Events has the same dropdown if you want a different
action later.

Takes effect on next login; to apply immediately without logging out, restart the
`powerdevil` kded module (it doesn't reliably auto-respawn after being killed, so relaunch
it explicitly):

```bash
kquitapp6 org_kde_powerdevil
nohup /usr/lib/org_kde_powerdevil >/dev/null 2>&1 &
disown
```

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

## Touchpad/TrackPoint resume fix (systemd-sleep hook, hardware-specific)

Recurring bug (first hit 2026-08-07): after resuming from suspend (closing the lid,
locking, then reopening), the built-in touchpad and TrackPoint go completely dead - both
still show up in `/proc/bus/input/devices` and `evtest` opens their device nodes fine, but
zero events or kernel interrupts are ever generated, no matter how much you tap/click.
Two separate, compounding causes:

1. **RMI4/SMBus transport doesn't re-init on resume.** The touchpad's kernel log line
   (`psmouse serio1: synaptics: Trying to set up SMBus access`) only ever appears once, at
   boot - never again after a resume, even though the input device object is still there
   (a stale zombie). Confirmed via `/proc/interrupts`: the `rmi4-*.fn12` (2D sensor)
   interrupt count doesn't move at all while actively tapping. Fix: rebind the `psmouse`
   driver on `serio1` (the i8042 AUX port) to force it to redo that handshake:
   ```bash
   echo -n "serio1" | sudo tee /sys/bus/serio/drivers/psmouse/unbind
   echo -n "serio1" | sudo tee /sys/bus/serio/drivers/psmouse/bind
   ```
2. **Toshy's `xwaykeyz` can end up with a stale exclusive grab.** Toshy's config service
   auto-grabs "all keyboards" at startup/hotplug, which in practice sweeps up pointer
   devices too (confirmed via `ls -la /proc/<xwaykeyz-pid>/fd`, which had the touchpad's
   and TrackPoint's `/dev/input/eventN` open). Its own log shows `BrokenPipeError` /
   `"Device may be in transition (KVM switch?)"` retries when it tries to (re-)grab a
   device mid-resume, before fix #1 above has actually run. Linux's `EVIOCGRAB` means a
   process holding a broken/stale grab silently blackholes input for every other listener,
   including the compositor - which is why `evtest` also saw nothing. Only killing and
   restarting the service clears it (confirmed empirically: a full logout/login, which
   respawns `toshy-config.service` fresh, restored the touchpad even though the driver
   rebind alone had not).

**Fix**: `etc/systemd/system-sleep/90-trackpad-resume-fix.sh`, installed to
`/usr/lib/systemd/system-sleep/` by `install.sh`, runs automatically after every resume
(`systemd-sleep` hooks get `$1=post $2=suspend` from `systemd-logind`) and does both
repairs in order: a short `sleep 2` to let the SMBus controller finish resuming, the
`psmouse` rebind, then `systemctl --user restart toshy-config.service` for whichever user
owns the `seat0` session (found via `loginctl`, not hardcoded - root can't run `--user`
systemctl without explicitly pointing `XDG_RUNTIME_DIR` at that user's runtime dir).

**Follow-up bug (found 2026-08-08, fixed same day):** the very first version of this hook
ran that `systemctl --user restart` synchronously, which froze the entire desktop session
for ~87 seconds on every single resume. `systemd-sleep` freezes `user.slice` before
suspend and only thaws it after every `post` hook returns - but `user.slice` contains the
user's own systemd instance, so a synchronous `systemctl --user` call from inside the hook
is asking a frozen target to respond before it's been thawed. It doesn't error out cleanly;
it just stalls until something breaks the deadlock ~87s later, holding the whole session
(compositor included) frozen the entire time. Confirmed via `journalctl`: `Unit now
thawed` landed exactly 87s after the hook's `sudo systemctl --user restart` line, on every
resume since the hook was installed, versus milliseconds before it existed. Fixed by
backgrounding that call (`setsid ... & disown`) so the hook returns immediately and the
thaw isn't held hostage; the actual restart completes a few seconds later once the session
unfreezes on its own.

Only relevant if you're setting up the same physical hardware and running Toshy. If a
similar dead-touchpad-after-resume symptom shows up without Toshy installed, cause #1
alone may already be enough - check `/proc/interrupts` for the `rmi4-*.fn12` line before
assuming cause #2 also applies.

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

### Root cause found (2026-07-25): Raydium touchscreen resume crash

The watchdog fix above paid off immediately - the very next freeze left a full trace.
Sequence of events from the kernel log:

1. System suspends (s2idle) after the screen locks/idles.
2. On resume, the Raydium touchscreen driver's IRQ handler
   (`raydium_i2c_irq` in `raydium_i2c_ts`) fires before its internal state is fully
   re-initialized post-resume, and NULL-pointer-dereferences.
3. That crash cascades into a second, more severe fault (a CET/control-flow-integrity
   violation) while the kernel tries to clean up the crashed thread.
4. The kernel explicitly logs `Fixing recursive fault but reboot is needed!` - at that
   point it has already given up on recovering.
5. Everything after is the system limping in a degraded state: Bluetooth and WiFi
   actually reconnect fine at the kernel level (explains music briefly stopping then
   the Bluetooth headset re-pairing), but the display/graphics session never recovers,
   hence the black screen requiring a forced shutdown.

This is a known bug class, not specific to this machine - other users hit the same
`raydium_i2c_irq` NULL pointer crash on resume (see
[Arch Forums report](https://bbs.archlinux.org/viewtopic.php?id=292611)). There's a
known upstream patch for a related Raydium resume issue
([linux-input ML](https://www.spinics.net/lists/linux-input/msg56023.html)), but it's
not confirmed present in this kernel build, and reproducing/verifying a kernel patch
wasn't worth it over the simpler fix below.

**Fix**: `install.sh` blacklists `raydium_i2c_ts` entirely (`etc/modprobe.d` isn't a
directory this repo manages elsewhere yet, so the file is written directly, not
templated - no personal data involved). This fully removes the touchscreen as a
feature on this machine, in exchange for eliminating this crash class. Confirmed
before applying: the kernel trace itself proves the driver was actively loaded and
receiving real interrupts at the moment of the crash, regardless of any BIOS-level
touch toggle - so blacklisting is a real fix, not a redundant no-op.

## Magic Trackpad + three-finger drag (Bluetooth + USB, hardware-specific)

An Apple Magic Trackpad is paired over Bluetooth for macOS-style multitouch, and also
works over USB (e.g. while charging) since three-finger-drag follows either connection -
see below. Quirks worth knowing if this breaks after a reinstall or a new pairing:

- **Won't pair over Bluetooth while a cable is plugged in.** Magic Trackpads fall back to
  acting as a wired USB HID device whenever a cable is connected (charging or otherwise),
  and won't complete Bluetooth pairing in that state - unplug it first, then toggle the
  power switch off/on to re-enter pairing mode.
- **Invisible in System Settings.** KDE's Mouse/Touchpad pages never list it - KWin's own
  D-Bus `InputDevice` object flags it `isVirtual: true`, because Bluetooth HID devices
  are injected via the kernel's `uhid` subsystem, putting their sysfs path under
  `/devices/virtual/...`. It's still fully functional at the libinput/KWin level despite
  being hidden from the GUI (confirmed via
  `busctl --user introspect org.kde.KWin /org/kde/KWin/InputDevice/eventN`). This likely
  affects any Bluetooth mouse/touchpad on this machine, not just this one.
- **USB exposes two identical-looking HID interfaces.** Plugged in via cable, the
  trackpad enumerates as *two* `/dev/input/eventN` nodes with the same
  `ATTRS{uniq}`/`id/vendor`/`id/product` (only differing in which USB interface number
  they hang off). Only interface 1 is the real multitouch device libinput actually uses
  (verified with `libinput list-devices`) - interface 0 is present but unused. The udev
  rules below disambiguate with `ENV{ID_USB_INTERFACE_NUM}=="01"` - not `KERNELS=="*:1.1"`,
  which looks like the obvious choice but silently never matches: `KERNELS` and `ATTRS` in
  one rule must both match the *same* device while walking up the chain, and no single
  ancestor has both the `:1.1` kernel name and the uniq/vendor/product attributes.
  `ID_USB_INTERFACE_NUM` is a property already resolved onto the device itself by earlier
  stock udev rules (same source as the `-if01-` suffix on the default by-id symlink), so
  it works as a plain `ENV{}` match with no ancestor-walk issue.

KDE/KWin doesn't expose a native three-finger-*drag* toggle (only tap-and-drag, which is
a different gesture) - confirmed absent from the same D-Bus interface above - so this
uses [linux-3-finger-drag](https://github.com/jesperdote/linux-3-finger-drag) (my fork of
[lmr97's tool](https://github.com/lmr97/linux-3-finger-drag)), a small Rust daemon that
exclusively grabs the touchpad and synthesizes the drag via `uinput`. `install.sh` clones
it to `~/src/linux-3-finger-drag` and installs the two udev rule templates above, but
does **not** build/install/enable it - that needs Rust (`rustup default stable`) and the
tool's own sudo-gated installer (`sudo ./install.sh` from that directory), printed as a
manual step. After that, `~/.config/systemd/user/three-finger-drag.service`'s `ExecStart`
needs `--device /dev/input/magic-trackpad-event` appended by hand - this machine has two
touchpads (built-in Synaptics + the Magic Trackpad), and the tool's auto-discovery
silently picks the wrong one otherwise. That symlink is kept up by `70-magic-trackpad.
rules` regardless of which connection is active, so the `ExecStart` line itself never
needs to change between Bluetooth and USB.

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
(and, for USB, `ENV{ID_USB_INTERFACE_NUM}=="01"`) specifically to avoid that.

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
