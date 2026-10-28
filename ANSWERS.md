# Questionnaire answers (Phase 0)

**Status:** approved by Ian on 2026-10-27. `packages/*.txt` written from these answers.

Each topic records the question, Ian's answer, and the packages or settings that result.
Re-run the questionnaire by editing a topic here, then regenerating `packages/*.txt`.

## 1. Machine

| Question | Answer | Result |
|---|---|---|
| Desktop or laptop? | Desktop | No laptop power or brightness tools needed |
| GPU | Handled by archinstall | No GPU packages in this script (see plan change below) |
| Wi-Fi / Bluetooth / printer / fingerprint | Handled by archinstall | No hardware packages in this script |

**Scope rule from Ian:** archinstall runs first with the *minimal* profile and is fully done before this script runs.
Everything archinstall handles is out of scope: graphics drivers, hardware, **network, audio**, keyboard layout.
This script only does what comes after that.

archinstall choices this script relies on: Network = NetworkManager, Audio = PipeWire.

**Plan change (confirmed):** drop the GPU detection step in Phase 3 and the `packages/gpu-*.txt` files.

**Reference machine:** Ian's current Arch install is close to the target setup, so package choices are checked against it.

## 2. AUR helper

| Question | Answer | Result |
|---|---|---|
| paru or yay? | paru | Bootstrap `paru-bin` in Phase 2 (installed here as `paru`) |

## 3. Mango

| Question | Answer | Result |
|---|---|---|
| Stable or -git? | Whatever Dux 2.0 needs | `mangowm` (official repo `extra`, 0.18.3 on the reference machine, works with Dux 2.0) |

**Finding: Dux Shell package names (checked 2026-10-27)**
- There is no stable `dux-shell` package. The only one is `dux-shell-git` (AUR). It provides `dux-shell` and `dms-shell`.
- Its dependency `dgop` comes from `dux-gop` (official repo `extra`).
- So `dux-shell` moves out of `pacman.txt` and goes into `aur.txt` as `dux-shell-git`.
- Other Dux Labs AUR packages exist: `dux-greeter-bin`, `dux-files-bin`, `dux-calendar-bin`, `dux-search-bin`.

## 4. Login

| Question | Answer | Result |
|---|---|---|
| TTY or login screen? | Dux Greeter (same as reference machine) | `greetd` (pacman), `dux-greeter-bin` (AUR); set up with `dms-greeter`'s own `install`/`enable` command, never by editing `/etc/greetd/config.toml` |
| Keyboard layout | US, set by archinstall | Nothing in the script |

## 5. Dux Shell features

All of these are in the official repo `extra` (checked with `pacman -Si`).

| Feature | Answer | Package |
|---|---|---|
| Wallpaper theming | Yes | `matugen` |
| Audio visualizer | Yes | `cava` |
| Sound effects | Yes | `qt6-multimedia` |
| Qt app theming | Yes | `qt6ct` |
| Printing panel | Yes | `cups`, `cups-pk-helper` (service: `cups`) |
| Clipboard paste | Yes | `wtype` |
| External monitor brightness | Yes | `i2c-tools` |
| Power profiles | Yes | `power-profiles-daemon` (service) |
| Network backend | NetworkManager, **set up by archinstall** | No package. Pick NetworkManager in archinstall's network setting. |

## 6. Wayland extras

| Question | Answer | Result |
|---|---|---|
| Screenshots / clipboard | Dux built-ins (`dms screenshot`, `dms clipboard`) | `wl-clipboard`, `grim`, `slurp`; dropped `cliphist` and `satty` from the plan's list |
| Screen recording | OBS Studio | Repo or Flatpak decided in topic 11 |
| File manager | Dolphin | `dolphin` |
| Night light | Dux built-in (`dms ipc night`, checked on reference machine) | No package |

Note: Dux Shell's own settings live in `~/.config/dms/` (`settings.json`, plugins). Asked about in topic 10.

## 7. Audio

| Question | Answer | Result |
|---|---|---|
| Audio base | Handled by archinstall (PipeWire) | No packages |
| Audio apps (pavucontrol, EasyEffects, ...) | None picked | No packages |

## 8–9. Fonts, terminal and shell

**Answer:** kitty, fish, prompt, terminal fonts and CLI tools are all handled by Ian's own repo
<https://github.com/iancrowder23-ship-it/fish-dotfiles>. This script clones it and runs its `install.sh`.

What that installer already does (read on 2026-10-27):
- pacman: `kitty fish starship git curl eza bind libnotify ttf-jetbrains-mono-nerd noto-fonts-emoji`, plus `fastfetch librsvg fisher`
- Clones itself to `~/.local/share/fish-dotfiles` (or `git pull`s on re-run), backs up `~/.config/{kitty,fish,fastfetch}`, deploys configs, installs fisher plugins, `chsh` to fish
- Flags: `-y`, `--theme`, `--accent`, `--dms`, `--no-fastfetch`, `--no-plugins`, `--no-shell-change`

Plan changes that follow from this:
- Phase 4 no longer symlinks kitty/fish or runs `chsh`. It clones/updates the repo and runs its installer. No `curl | bash` (rule 7).
- `kitty`, `fish`, `ttf-jetbrains-mono-nerd`, `noto-fonts-emoji` leave `pacman.txt`, because the dotfiles installer owns them.
- Durability rule 5 (symlinks) doesn't apply to kitty/fish: that repo's installer copies files. That's Ian's own tool doing its own setup, same idea as rule 6.

## Theming (dark mode outside Dux)

**Answer:** install whatever makes KDE and Flatpak apps dark where Dux doesn't already.

Dux's matugen templates on the reference machine: `gtk`, `kcolorscheme`, `kitty`, `mangowc`, `dgop` are active; `qt6ct` is not (not installed yet).

Approved set:
- pacman: `adw-gtk-theme`, `qt6ct`, `breeze`
- Flatpak: `org.gtk.Gtk3theme.adw-gtk3`, `org.gtk.Gtk3theme.adw-gtk3-dark` (both checked on Flathub)
- Commands (upstream tools, no file edits):
  `flatpak override --user --filesystem=xdg-config/gtk-3.0:ro --filesystem=xdg-config/gtk-4.0:ro --filesystem=xdg-config/kdeglobals:ro`
  and `gsettings set org.gnome.desktop.interface color-scheme prefer-dark`
- `QT_QPA_PLATFORMTHEME=qt6ct` needs a home. Mango config is upstream-only (topic 10), so it's proposed as a
  whole file `dotfiles/environment.d/qt6ct.conf` symlinked into `~/.config/environment.d/` (confirm in summary).

| Question | Answer | Result |
|---|---|---|
| How to run fish-dotfiles installer | `-y`, then `theme-pick --dms` after first login | Phase 4 runs `install.sh -y`; Phase 7 summary reminds Ian |
| App fonts | All four | `noto-fonts`, `noto-fonts-cjk`, `ttf-liberation`, `ttf-dejavu` |

## 10. Dotfiles

| Question | Answer | Result |
|---|---|---|
| Mango config | `dms setup` only | Script runs `dms setup headless --compositor mango --skip-existing`. No `dotfiles/mango/`. |
| Dux Shell settings | Start from Dux defaults | Nothing stored |
| Dux plugins | Don't install | Nothing |

## 11. Apps

Ian: start with just what's needed to get going; add more once the script is proven.

| App | Source | Package / ID |
|---|---|---|
| Brave | Flatpak | `com.brave.Browser` |
| OBS Studio | Flatpak | `com.obsproject.Studio` |
| Warehouse | Flatpak | `io.github.flattool.Warehouse` |
| VLC | Flatpak | `org.videolan.VLC` |
| ONLYOFFICE | Flatpak | `org.onlyoffice.desktopeditors` |
| Neovim + LazyVim | pacman + upstream starter | `neovim` and LazyVim's requirements: `lazygit`, `tree-sitter-cli`, `gcc` (via base-devel), `fzf`, `ripgrep`, `fd`, `unzip`, `wl-clipboard` |

All Flathub IDs checked with `flatpak remote-info`; all pacman names in `extra`/`core`.

LazyVim is set up with its official method, `git clone https://github.com/LazyVim/starter ~/.config/nvim`
(then its `.git` is removed, so the config becomes Ian's own). Skipped if `~/.config/nvim` already exists.

Dropped from the reference machine (can be added later): Steam, Flatseal, Claude Desktop/Code, github-cli, KDE Connect, system tools.

## 12. Flatpak scope

| Question | Answer | Result |
|---|---|---|
| --user or system-wide? | System-wide | `sudo flatpak remote-add` / `sudo flatpak install`. Theme overrides stay `--user` (a user override applies to system-installed apps too, and needs no sudo). |

## 13. Services

| Service | Answer | Result |
|---|---|---|
| ufw (firewall) | Handled by archinstall | Nothing |
| greetd / Dux Greeter | Install only; Ian turns it on from Dux settings for now | Packages installed, not enabled |
| power-profiles-daemon, cups | Not picked | Script enables no services. Ian may need to enable these (or pick printing in archinstall) for the Dux power/printing panels to work. |

## 14. Anything else

None.

Finding: the plan's two `exec_once` lines for Mango are not in the reference machine's config, and Dux still starts
once via `dms.service` (enabled, tied to `mango-session.target`). `dms setup` handles the session, so those lines are dropped.
