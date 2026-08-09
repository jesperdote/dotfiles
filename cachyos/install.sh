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

echo "==> colorls gem fix (AUR ruby-colorls caps unicode-display_width <3.0, but pulls in 3.x)"
if command -v colorls >/dev/null && ! colorls --version >/dev/null 2>&1; then
    gem install --user-install unicode-display_width -v '2.6.0'
else
    echo "    Skipped (colorls not installed, or already working)"
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

echo "==> colorls aliases in ~/.zshrc"
if ! grep -q "alias ls='colorls'" ~/.zshrc 2>/dev/null; then
    cat zsh/colorls.zsh >> ~/.zshrc
fi

echo "==> Bluetooth aliases in ~/.zshrc"
if ! grep -q "alias trackpad-connect=" ~/.zshrc 2>/dev/null; then
    cat zsh/bluetooth.zsh >> ~/.zshrc
fi

echo "==> Claude Code statusline (oh-my-posh)"
OMP_THEME_DEST="$HOME/.config/oh-my-posh/claude.omp.json"
mkdir -p "$(dirname "$OMP_THEME_DEST")"
if [[ ! -f "$OMP_THEME_DEST" ]] || ! cmp -s oh-my-posh/claude.omp.json "$OMP_THEME_DEST"; then
    cp oh-my-posh/claude.omp.json "$OMP_THEME_DEST"
    echo "    Installed $OMP_THEME_DEST"
else
    echo "    Skipped (theme already up to date)"
fi

CLAUDE_SETTINGS="$HOME/.claude/settings.json"
OMP_STATUSLINE_CMD="oh-my-posh claude --config $OMP_THEME_DEST"
mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
[[ -f "$CLAUDE_SETTINGS" ]] || echo '{}' > "$CLAUDE_SETTINGS"
if [[ "$(jq -r '.statusLine.command // empty' "$CLAUDE_SETTINGS")" != "$OMP_STATUSLINE_CMD" ]]; then
    jq --arg cmd "$OMP_STATUSLINE_CMD" \
        '.statusLine = {"type": "command", "command": $cmd, "padding": 0}' \
        "$CLAUDE_SETTINGS" > "$CLAUDE_SETTINGS.tmp"
    mv "$CLAUDE_SETTINGS.tmp" "$CLAUDE_SETTINGS"
    echo "    Set statusLine in $CLAUDE_SETTINGS (takes effect on next Claude Code session)"
else
    echo "    Skipped (statusLine already set)"
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

echo "==> Touchpad/TrackPoint resume fix (systemd-sleep hook)"
echo "    The touchpad's RMI4/SMBus transport doesn't always re-init after suspend,"
echo "    leaving the touchpad and TrackPoint enumerated but dead, and Toshy's"
echo "    xwaykeyz can end up with a stale exclusive grab if it re-detects devices"
echo "    mid-resume. This hook rebinds psmouse and restarts toshy-config.service"
echo "    automatically on every resume. See README.md for the full diagnosis."
SLEEP_HOOK_DEST=/usr/lib/systemd/system-sleep/90-trackpad-resume-fix.sh
SLEEP_HOOK_SRC=etc/systemd/system-sleep/90-trackpad-resume-fix.sh
if [[ ! -f "$SLEEP_HOOK_DEST" ]] || ! cmp -s "$SLEEP_HOOK_SRC" "$SLEEP_HOOK_DEST"; then
    sudo cp "$SLEEP_HOOK_SRC" "$SLEEP_HOOK_DEST"
    sudo chmod 0755 "$SLEEP_HOOK_DEST"
    echo "    Installed $SLEEP_HOOK_DEST"
else
    echo "    Skipped (already up to date)"
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

echo "==> Blacklisting raydium_i2c_ts (Raydium touchscreen resume crash)"
echo "    Known kernel bug: this driver's IRQ handler NULL-pointer-dereferences on"
echo "    s2idle resume, cascading into a CET violation and an unrecoverable kernel"
echo "    state (silent freeze - black screen, no lockup logged prior to the watchdog"
echo "    fix above). See README.md for the full crash trace and diagnosis."
BLACKLIST_FILE=/etc/modprobe.d/blacklist-raydium.conf
if [[ ! -f "$BLACKLIST_FILE" ]]; then
    echo "blacklist raydium_i2c_ts" | sudo tee "$BLACKLIST_FILE" > /dev/null
    sudo rmmod raydium_i2c_ts 2>/dev/null || true
    echo "    Blacklisted and unloaded (touchscreen input is lost, by design)"
else
    echo "    Skipped (already blacklisted)"
fi

echo "==> Magic Trackpad three-finger drag (Bluetooth + USB)"
echo "    Bluetooth-connected input devices go through the kernel's uhid subsystem, so"
echo "    /dev/input/eventN changes on every reconnect; USB exposes the trackpad as two"
echo "    HID interfaces with identical vendor/product/serial. These udev rules key off"
echo "    the trackpad's Bluetooth address and USB serial (plus interface number for"
echo "    USB) instead, so downstream config can use one stable path either way. See"
echo "    README.md for the values below and full rationale."
TRACKPAD_RENDER_ARGS=(
    -e "s/__TRACKPAD_UNIQ__/08:65:18:ba:b6:7b/"
    -e "s/__TRACKPAD_VENDOR__/004c/"
    -e "s/__TRACKPAD_PRODUCT__/0265/"
    -e "s/__TRACKPAD_USB_UNIQ__/CC2305200Q90YWTA4/"
    -e "s/__TRACKPAD_USB_VENDOR__/05ac/"
    -e "s/__TRACKPAD_USB_PRODUCT__/0265/"
)

# Renders to a temp file and compares content rather than just checking the
# destination exists, so edits to the template (e.g. adding USB support)
# reach machines that already had an older version installed.
install_udev_rule() {
    local template="$1" dest="$2"
    shift 2
    local tmp
    tmp="$(mktemp)"
    sed "$@" "$template" > "$tmp"
    if [[ -f "$dest" ]] && cmp -s "$tmp" "$dest"; then
        echo "    Skipped (already up to date)"
        rm "$tmp"
    else
        sudo cp "$tmp" "$dest"
        rm "$tmp"
        sudo udevadm control --reload-rules
        echo "    Installed $dest"
    fi
}

OLD_MAGIC_RULE=/etc/udev/rules.d/70-magic-trackpad-bt.rules
if [[ -f "$OLD_MAGIC_RULE" ]]; then
    sudo rm "$OLD_MAGIC_RULE"
    echo "    Removed superseded $OLD_MAGIC_RULE (renamed, now covers USB too)"
fi
install_udev_rule etc/udev/rules.d/70-magic-trackpad.rules.template \
    /etc/udev/rules.d/70-magic-trackpad.rules "${TRACKPAD_RENDER_ARGS[@]}"
install_udev_rule etc/udev/rules.d/61-hotplug.rules.template \
    /etc/udev/rules.d/61-hotplug.rules "${TRACKPAD_RENDER_ARGS[@]}" -e "s/__USER__/$USER/"

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
         "--device /dev/input/magic-trackpad-event" - this machine has 2
         touchpads, and auto-discovery picks the built-in one instead. This path
         works whether the trackpad is connected over Bluetooth or USB.
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
  - Magic Trackpad stops reconnecting after a resume/lid-close (already paired/trusted,
    just shows `Connected: no`): physical nudges (tap, power-cycle, laptop BT radio
    toggle) are unreliable here - run the `trackpad-connect` alias instead.
  - linux-3-finger-drag build/install/service wiring: see the printed steps above
EOF
