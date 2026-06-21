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
EOF
