#!/usr/bin/env bash
# Reproduces the system changes made on this CachyOS install (ThinkPad T14 Gen2).
# Safe to re-run: every step checks current state before changing anything.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

echo "==> Installing official repo packages"
sudo pacman -S --needed - < packages.txt

echo "==> Installing AUR packages (requires an AUR helper, e.g. paru)"
if command -v paru >/dev/null; then
    paru -S --needed - < aur-packages.txt
else
    echo "paru not found - install an AUR helper first, then re-run this script" >&2
fi

echo "==> Setting default shell to zsh (switched from fish)"
if [[ "$SHELL" != "/usr/bin/zsh" ]]; then
    chsh -s /usr/bin/zsh
    echo "    Default shell changed - takes effect on next login"
fi

echo "==> Enabling docker"
sudo systemctl enable --now docker
if ! groups "$USER" | grep -qw docker; then
    sudo usermod -aG docker "$USER"
    echo "    Added $USER to docker group - log out/in for it to take effect"
fi

echo "==> Diagnostics sudoers rule (passwordless dmesg/journalctl/evtest/libinput)"
SUDOERS_FILE=/etc/sudoers.d/90-diagnostics-nopasswd
if [[ ! -f "$SUDOERS_FILE" ]]; then
    sed "s/__USER__/$USER/" etc/sudoers.d/90-diagnostics-nopasswd.template | sudo tee "$SUDOERS_FILE" > /dev/null
    sudo visudo -cf "$SUDOERS_FILE"
    sudo chmod 0440 "$SUDOERS_FILE"
fi

echo "==> zoxide in ~/.zshrc"
if ! grep -q "zoxide init zsh" ~/.zshrc 2>/dev/null; then
    cat zsh/zoxide.zsh >> ~/.zshrc
fi

echo "==> Power button locks screen (macOS-style), instead of the sleep/shutdown prompt"
echo "    32 = PowerDevil::PowerButtonAction::LockScreen (see README.md for the full enum)."
if [[ "$(kreadconfig6 --file powerdevilrc --group AC --group SuspendAndShutdown --key PowerButtonAction)" != "32" ]]; then
    kwriteconfig6 --file powerdevilrc --group AC --group SuspendAndShutdown --key PowerButtonAction 32
    kwriteconfig6 --file powerdevilrc --group Battery --group SuspendAndShutdown --key PowerButtonAction 32
    echo "    Applied - takes effect on next login, or restart powerdevil now:"
    echo "        kquitapp6 org_kde_powerdevil; nohup /usr/lib/org_kde_powerdevil >/dev/null 2>&1 & disown"
else
    echo "    Skipped (already set)"
fi

echo "==> Touchpad fix: psmouse.synaptics_intertouch=1 (ThinkPad T14 Gen2 Synaptics palm-rejection bug)"
echo "    Only relevant on the same hardware - switches the touchpad from legacy PS/2"
echo "    emulation to native RMI4/SMBus, fixing phantom cursor movement during palm contact."
echo "    Side effect: touchpad becomes a 'new' device to the desktop, so tap-to-click"
echo "    (and other per-device settings) reset to default and may need re-enabling in"
echo "    System Settings -> Input Devices -> Touchpad."
LIMINE_CONF=/etc/default/limine
if [[ -f "$LIMINE_CONF" ]] && ! grep -q "psmouse.synaptics_intertouch=1" "$LIMINE_CONF"; then
    sudo sed -i 's/^KERNEL_CMDLINE\[default\]+="/KERNEL_CMDLINE[default]+="psmouse.synaptics_intertouch=1 /' "$LIMINE_CONF"
    sudo limine-update
    echo "    Applied - reboot for it to take effect"
else
    echo "    Skipped (no Limine config found, or already applied)"
fi

echo "==> Freeze diagnostics: re-enabling kernel lockup watchdogs"
echo "    nowatchdog (kernel cmdline) and kernel.nmi_watchdog=0 (CachyOS's own sysctl"
echo "    default) both disable lockup detection - either alone is enough to leave a"
echo "    hang with zero diagnostic trail. See README.md for how this was found."
if [[ -f "$LIMINE_CONF" ]] && grep -q "nowatchdog" "$LIMINE_CONF"; then
    sudo sed -i 's/ nowatchdog//' "$LIMINE_CONF"
    sudo limine-update
    echo "    Removed nowatchdog - reboot for it to take effect"
else
    echo "    Skipped (no Limine config found, or already removed)"
fi
SYSCTL_WATCHDOG=/etc/sysctl.d/99-nmi-watchdog-enable.conf
if [[ ! -f "$SYSCTL_WATCHDOG" ]]; then
    sudo cp etc/sysctl.d/99-nmi-watchdog-enable.conf "$SYSCTL_WATCHDOG"
    sudo sysctl --system > /dev/null
    echo "    Re-enabled kernel.nmi_watchdog via $SYSCTL_WATCHDOG"
else
    echo "    Skipped (already installed)"
fi

echo "==> Magic Trackpad three-finger drag (Bluetooth)"
echo "    Bluetooth-connected input devices go through the kernel's uhid subsystem, so"
echo "    /dev/input/eventN changes on every reconnect. These udev rules key off the"
echo "    trackpad's own Bluetooth address instead, so downstream config can use a"
echo "    stable path. See README.md for the values below and full rationale."
MAGIC_RULE=/etc/udev/rules.d/70-magic-trackpad-bt.rules
if [[ ! -f "$MAGIC_RULE" ]]; then
    sed -e "s/__TRACKPAD_UNIQ__/08:65:18:ba:b6:7b/" \
        -e "s/__TRACKPAD_VENDOR__/004c/" \
        -e "s/__TRACKPAD_PRODUCT__/0265/" \
        etc/udev/rules.d/70-magic-trackpad-bt.rules.template | sudo tee "$MAGIC_RULE" > /dev/null
    sudo udevadm control --reload-rules
    echo "    Installed $MAGIC_RULE"
else
    echo "    Skipped (already installed)"
fi
HOTPLUG_RULE=/etc/udev/rules.d/61-hotplug.rules
if [[ ! -f "$HOTPLUG_RULE" ]]; then
    sed -e "s/__TRACKPAD_UNIQ__/08:65:18:ba:b6:7b/" \
        -e "s/__TRACKPAD_VENDOR__/004c/" \
        -e "s/__TRACKPAD_PRODUCT__/0265/" \
        -e "s/__USER__/$USER/" \
        etc/udev/rules.d/61-hotplug.rules.template | sudo tee "$HOTPLUG_RULE" > /dev/null
    sudo udevadm control --reload-rules
    echo "    Installed $HOTPLUG_RULE"
else
    echo "    Skipped (already installed)"
fi

TFD_SRC="$HOME/src/linux-3-finger-drag"
if [[ -d "$TFD_SRC/.git" ]]; then
    git -C "$TFD_SRC" pull
else
    mkdir -p "$(dirname "$TFD_SRC")"
    git clone https://github.com/jesperdote/linux-3-finger-drag.git "$TFD_SRC"
fi
chmod +x "$TFD_SRC/install.sh"  # not committed with the executable bit set
cat <<'EOF'
    Repo cloned/updated at ~/src/linux-3-finger-drag.

    NOT built/installed automatically (needs Rust, its own sudo-gated installer,
    and a reboot for group membership). Steps, in order:

      1. rustup default stable   # if Rust isn't set up yet
      2. cd ~/src/linux-3-finger-drag && sudo ./install.sh
      3. Edit ~/.config/systemd/user/three-finger-drag.service's ExecStart to add
         "--device /dev/input/magic-trackpad-bt-event" - this machine has 2
         touchpads, and auto-discovery picks the built-in one instead.
      4. systemctl --user daemon-reload && systemctl --user restart three-finger-drag.service
EOF

echo "==> Toshy (macOS-style keybinding remapper)"
TOSHY_SRC="$HOME/.local/src/toshy"
if [[ -d "$TOSHY_SRC/.git" ]]; then
    git -C "$TOSHY_SRC" pull
else
    mkdir -p "$(dirname "$TOSHY_SRC")"
    git clone https://github.com/jesperdote/Toshy.git "$TOSHY_SRC"
fi
cat <<'EOF'
    Repo cloned/updated at ~/.local/src/toshy.

    NOT run automatically - Toshy's installer has intentional "type this
    secret code to confirm you read this" prompts that cannot be (and are
    deliberately not meant to be) scripted around. Run it yourself:

        cd ~/.local/src/toshy && ./setup_toshy.py install

    Follow the interactive prompts (system-updated check, PATH, KDE/KWin
    script, sudo capability, etc). Log out/in afterward (or run
    'toshy-services-restart') to start the keymapper.
EOF

cat <<'EOF'

==> Manual steps not covered by this script:
  - VS Code: extensions/settings sync via your Microsoft/GitHub account (sign in once installed)
  - Toshy keyboard type/layout quirks: if modifier keys end up in the wrong place, run
    `toshy-devices` to find your keyboard's device name and add it to the Toshy config
  - Tap-to-click: defaults to OFF on a fresh install anyway (matches the current setting),
    enable in System Settings -> Input Devices -> Touchpad if you want it on
  - Magic Trackpad Bluetooth pairing: won't complete while a charging cable is plugged in
    (falls back to wired USB HID instead). Unplug it, toggle the trackpad's power switch
    off/on to re-enter pairing mode, then `bluetoothctl pair/trust/connect <mac>`.
  - linux-3-finger-drag build/install/service wiring: see the printed steps above
EOF
