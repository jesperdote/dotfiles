# Ubuntu vs CachyOS/Arch — CLI Command Comparison

A quick reference for users coming from Ubuntu/Debian to CachyOS (Arch-based).

## Package Management

| Task | Ubuntu (`apt`) | CachyOS/Arch (`pacman`) |
|---|---|---|
| Install package | `sudo apt install <pkg>` | `sudo pacman -S <pkg>` |
| Remove package | `sudo apt remove <pkg>` | `sudo pacman -R <pkg>` |
| Remove package + deps | `sudo apt autoremove <pkg>` | `sudo pacman -Rs <pkg>` |
| Update package list | `sudo apt update` | `sudo pacman -Sy` |
| Upgrade all packages | `sudo apt upgrade` | `sudo pacman -Syu` (do update+upgrade together) |
| Search for package | `apt search <name>` | `pacman -Ss <name>` |
| Show package info | `apt show <pkg>` | `pacman -Si <pkg>` (remote) / `pacman -Qi <pkg>` (installed) |
| List installed packages | `apt list --installed` | `pacman -Q` |
| Check what package owns a file | `dpkg -S <file>` | `pacman -Qo <file>` |
| List files owned by package | `dpkg -L <pkg>` | `pacman -Ql <pkg>` |
| Clean package cache | `sudo apt clean` | `sudo pacman -Sc` (or `-Scc` for all) |
| Install from AUR (no apt equivalent) | — | `paru -S <pkg>` or `yay -S <pkg>` (AUR helpers) |
| Reinstall a package | `sudo apt install --reinstall <pkg>` | `sudo pacman -S <pkg>` (pacman always reinstalls if asked) |
| Downgrade a package | `apt install <pkg>=<version>` | `sudo pacman -U /var/cache/pacman/pkg/<pkg>-<old-version>.pkg.tar.zst` |

> CachyOS also ships `pacman-key`, and since it's Arch-based, **rolling release** — there's no LTS/version split like Ubuntu's `20.04`/`22.04`/`24.04`.

## Service Management (systemd — same on both)

| Task | Ubuntu | CachyOS/Arch |
|---|---|---|
| Start service | `sudo systemctl start <svc>` | same |
| Enable on boot | `sudo systemctl enable <svc>` | same |
| Check status | `systemctl status <svc>` | same |
| View logs | `journalctl -u <svc>` | same |

Systemd commands are identical — this is one of the easiest parts of the transition.

## System Info & Updates

| Task | Ubuntu | CachyOS/Arch |
|---|---|---|
| OS version info | `lsb_release -a` or `/etc/os-release` | `/etc/os-release` (no `lsb_release` by default) |
| Kernel version | `uname -r` | same |
| List PPAs / extra repos | `/etc/apt/sources.list.d/` | `/etc/pacman.conf` (repos), AUR is not a repo, it's source-build |
| Full system upgrade incl. AUR | `sudo apt update && sudo apt full-upgrade` | `sudo pacman -Syu && yay -Syu` (or just `yay -Syu` if using an AUR helper, since it wraps pacman too) |

## Logs & Debugging

| Task | Ubuntu | CachyOS/Arch |
|---|---|---|
| View system log | `journalctl` or `/var/log/syslog` | `journalctl` (Arch doesn't keep a classic `/var/log/syslog` by default) |
| Boot log | `journalctl -b` | same |
| Disk usage | `df -h`, `du -sh` | same (coreutils, identical everywhere) |

## Networking

| Task | Ubuntu | CachyOS/Arch |
|---|---|---|
| Network manager CLI | `nmcli` (NetworkManager, default) | `nmcli` (CachyOS desktop editions default to NetworkManager too) |
| Show IP info | `ip a` | same (`ifconfig` is deprecated/not installed by default on both) |
| Firewall | `ufw` (Uncomplicated Firewall) | not installed by default; Arch users typically use `firewalld`, `nftables`, or `iptables` directly |

## File & Process Basics (identical — both use the same coreutils/GNU userland)

| Task | Command (same on both) |
|---|---|
| List files | `ls -la` |
| Change directory | `cd` |
| Copy / move / delete | `cp`, `mv`, `rm` |
| View running processes | `ps aux`, `top`, `htop` |
| Kill process | `kill`, `killall` |
| Edit file | `nano`, `vim` |
| Find files | `find`, `locate` |
| Permissions | `chmod`, `chown` |
| Disk/partition tools | `lsblk`, `fdisk`, `mount` |

These don't change between distros because they come from the same GNU coreutils / shell — distro choice only affects **package management, init system config, and default tooling**, not basic shell usage.

## Key Conceptual Differences

- **Ubuntu**: point releases (`.deb` packages via `apt`/`dpkg`), large official repos, PPAs for extra software, stable/LTS cycle.
- **Arch/CachyOS**: rolling release, smaller official repos (`core`, `extra`, `multilib`) but the **AUR** (Arch User Repository) covers almost everything else via build-from-source helpers like `yay`/`paru`.
- **CachyOS specifically**: an Arch derivative with performance-tuned kernels (e.g. `linux-cachyos`), custom repos, and the `cachyos-settings`/`cachyos-rate-mirrors` tooling — otherwise it behaves like vanilla Arch for `pacman` purposes.

## Useful First Commands on CachyOS

```bash
sudo pacman -Syu              # full system update — do this often, Arch is rolling release
pacman -Qdt                   # list orphaned packages (no longer needed deps)
sudo pacman -Rns $(pacman -Qdtq)  # remove orphans
cachyos-rate-mirrors           # CachyOS tool to pick fastest mirrors
yay -Syu                       # if you install an AUR helper, update AUR packages too
```
