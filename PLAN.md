# Arch post-install script: build plan

Hand this file to Claude Code to build the script with you. Put it in an empty folder, `cd` there, run `claude`, and say:

> Read PLAN.md and start with the questionnaire.

Claude Code will interview you first, fill in the package lists and settings from your answers, and only then start building, one phase at a time. Test each phase in a VM before running it on real hardware.

---

## Instructions for Claude Code

- The owner (Ian) knows general programming but is new to bash. Explain each new bash construct in a short comment the first time it appears. Keep the code plain: no clever one-liners, no frameworks, no extra features beyond this plan.
- Before writing any code, run the questionnaire (Phase 0) with Ian. Do not skip it or guess answers.
- Build one phase at a time. Stop after each phase, show what changed, and wait for Ian before starting the next.
- Run `shellcheck` on every script and fix all warnings before finishing a phase.
- Never run the script on this machine unless Ian asks. It installs system packages.
- Follow the durability rules below. If a request would break one, say so before doing it.

## Goal

One script, run as the normal user right after `archinstall`, that sets up:

1. MangoWM (Wayland compositor) and the Wayland basics it needs
2. Dux Shell 2.0 (desktop shell from Dux Labs, formerly DankMaterialShell) and its greeter
3. Ian's own kitty and fish setup (from his fish-dotfiles repo), plus Neovim with LazyVim
4. Dark mode for GTK, KDE and Flatpak apps
5. Flatpak and Ian's apps

GPU drivers are not part of this script; archinstall installs them (see Scope).

It must be safe to run again at any time, and it must keep working as the software it installs gets updated.

## Durability rules (why it keeps working after updates)

These are the whole point. Each rule removes a common way post-install scripts break.

1. **Install packages, never build from source.** Use pacman, the AUR, or Flathub. Packages track upstream changes for you; hand-written build steps break when upstream changes its build. (This means Dux Shell comes from its Arch package, not a git clone + `make`.)
2. **Never pin versions or download URLs.** No `foo-1.2.3`, no GitHub release links. Only package names.
3. **Package names live in plain text files, not in the code.** When a package gets renamed or you want something new, you edit a list, not the script.
4. **Check every name before installing anything.** A `--check` mode confirms every listed package still exists. After a rename upstream, it tells you exactly which line to fix instead of failing halfway through an install.
5. **Configs are symlinked from a git repo, never edited in place.** The script never uses `sed` or `echo >>` on config files. Your configs are copied over whole, so upstream default changes cannot conflict with edits.
6. **Use upstream's own setup commands.** For example, Dux Shell's `dms systemd enable` instead of hand-writing service files.
7. **No `curl ... | sh`.** It runs code nobody has read, and it changes without warning.
8. **Full system upgrade first, every run** (`pacman -Syu`). Arch does not support partial upgrades, and installing on top of a stale system is a common breakage.
9. **Every step checks before acting** (`--needed`, `command -v`, `[[ -d ... ]]`), so re-running is always safe and also works as a repair.

## Folder layout

```
arch-post-install/
├── PLAN.md
├── ANSWERS.md            # questionnaire answers (Phase 0)
├── install.sh            # the only script
├── packages/
│   ├── pacman.txt        # official repo packages, one per line, # for comments
│   ├── aur.txt           # AUR packages
│   └── flatpak.txt       # Flathub app IDs
└── dotfiles/
    └── environment.d/    # each file → ~/.config/environment.d/<file>
```

kitty and fish come from Ian's separate repo (fish-dotfiles), and the Mango config comes from `dms setup` (see Phases 4 and 5). On a new machine: run archinstall (minimal profile), install git, clone this repo, run `./install.sh`.

## Scope (from the questionnaire)

archinstall runs first and handles graphics drivers, hardware, network (choose NetworkManager), audio (PipeWire), keyboard layout and the firewall. This script never touches those.

## How `install.sh` behaves

- `./install.sh` runs every phase in order.
- `./install.sh --check` only validates package names and exits. Installs nothing.
- Refuses to run as root (AUR helpers break as root). Uses `sudo` only for pacman commands.
- Starts with `set -euo pipefail` so any failure stops the script.
- Prints a `==> Phase name` header before each phase.
- One function per phase, called from a `main` function at the bottom.
- A small helper reads a list file, skipping blank lines and `#` comments, so all list files use the same format.

## Phases

### Phase 0: questionnaire

Interview Ian to decide every package and setting. The starting lists further down are defaults to offer, not final answers.

**How to run it:**

- Ask one topic at a time, a few questions per message at most. Use multiple choice with a recommended option marked where possible, and explain any term Ian may not know in one line.
- For every optional package, say what it does in plain words so Ian can decide.
- For apps Ian names casually ("discord", "vscode"), find the real package: prefer the official repos, then Flathub, then the AUR, and say which you chose and why. Confirm the name exists (`pacman -Si`, `flatpak search`, `paru -Si`, or the archlinux.org / flathub.org sites if not on Arch).
- Record every answer in `ANSWERS.md` as you go (question, answer, resulting packages), so the questionnaire can be resumed or re-run later to change choices.
- At the end, show a summary of all lists and settings and wait for Ian to approve it. Then write the `packages/*.txt` files.

**Topics, in this order:**

1. **Machine:** desktop or laptop; GPU (offer to detect it with `lspci` if run on the machine); Wi-Fi, Bluetooth, printer, fingerprint reader.
2. **AUR helper:** paru (recommended) or yay.
3. **Mango:** stable `mangowm` (recommended, fewer surprises after updates) or `mangowm-git`.
4. **Login:** start Mango from the TTY, or a login screen (Dux Greeter / greetd). Keyboard layout if not US.
5. **Dux Shell features:** walk through each optional dependency (wallpaper theming, audio visualizer, network backend NetworkManager vs iwd, power profiles, sound effects, clipboard paste, external monitor brightness, printing) and ask yes/no.
6. **Wayland extras:** screenshots, clipboard history, night light, screen recording, file manager (Dux Files or another).
7. **Audio:** PipeWire (recommended default); any extras like EasyEffects or pavucontrol.
8. **Fonts and theming:** Nerd Font choice, emoji, CJK fonts, GTK/Qt theme and icon theme, cursor theme.
9. **Terminal and shell:** kitty and fish are fixed. Ask about prompt (starship or fish's own), and CLI tools (fzf, zoxide, eza, bat, ripgrep, fd, btop, fastfetch, etc.).
10. **Dotfiles:** where the current kitty, fish, and Mango configs live (git repo URL, files on another machine, or start fresh). If a repo, decide whether to copy them into `dotfiles/` here or clone that repo separately.
11. **Apps by category:** browser, editor/IDE, dev languages and tools, chat, media, office, gaming (Steam needs the multilib repo enabled; ask), anything else. Decide repo vs Flatpak for each, defaulting to the repo for system tools and Flatpak for desktop apps.
12. **Flatpak scope:** per-user (`--user`, no sudo, recommended) or system-wide.
13. **Services:** which to enable (Bluetooth, NetworkManager, printing, power-profiles-daemon, firewall).
14. **Anything else** Ian wants on every install.

**Done when:** Ian has approved the summary, `ANSWERS.md` exists, and every `packages/*.txt` file is filled in.

### Phase 1: skeleton and list reading

- `install.sh` with strict mode, root check, `main`, and empty phase functions.
- The list-reading helper.
- `--check` mode: `pacman -Si` for each name in `pacman.txt`, the AUR helper's `-Si` for `aur.txt`, and `flatpak remote-info flathub` for `flatpak.txt`. Print every missing name, then exit non-zero if any are missing.

**Done when:** `--check` reports a deliberately misspelled package name and passes once it's fixed.

### Phase 2: system update and AUR helper

- `sudo pacman -Syu --noconfirm`.
- Install `git` and `base-devel`.
- If `paru` is not installed, build `paru-bin` from the AUR in a `mktemp -d` folder with `makepkg -si --noconfirm`, then delete the temp folder.

**Done when:** running twice in a row does nothing the second time except the update.

### Phase 3: packages

- Install `pacman.txt` with `sudo pacman -S --needed --noconfirm`.
- Install `aur.txt` with `paru -S --needed --noconfirm` (skip if the file is empty). This brings in `dux-shell-git` and `dux-greeter-bin`.

**Done when:** a fresh VM ends this phase able to start `mango` from a TTY.

### Phase 4: dotfiles, shell and editor

- **kitty + fish:** if `~/.local/share/fish-dotfiles` is a git checkout, `git pull --ff-only` it; otherwise `git clone` https://github.com/iancrowder23-ship-it/fish-dotfiles there. Then run its `./install.sh -y`. That installer owns kitty, fish, starship, the terminal fonts, fisher plugins and `chsh`. Never `curl | bash` it.
- **environment.d:** for each file in `dotfiles/environment.d/`, symlink it into `~/.config/environment.d/` with `ln -sfn`. If a real file (not a symlink) is already there, rename it to `<name>.bak-<date>` first and say so. Never delete it.
- **LazyVim:** if `~/.config/nvim` does not exist, `git clone https://github.com/LazyVim/starter ~/.config/nvim`, then remove `~/.config/nvim/.git` (LazyVim's official install steps). If it exists, leave it alone.

**Done when:** a second run changes nothing, and `nvim` opens LazyVim.

### Phase 5: Dux Shell

- Its packages are installed in Phase 3.
- Generate the Mango config with upstream's command: `dms setup headless --compositor mango --skip-existing`. The script never writes Mango config itself.
- Check in the VM whether `dms setup headless` already enables the `dms` systemd user service. If it doesn't, also run `dms systemd enable`, only if it isn't enabled yet.
- The greeter (`greetd` + `dux-greeter-bin`) is installed but **not** enabled. Ian turns it on from Dux settings.

**Done when:** logging into Mango starts Dux Shell automatically, once (not twice).

### Phase 6: Flatpak and dark mode

- `sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo` (system-wide, per the questionnaire).
- `sudo flatpak install -y --noninteractive flathub` with every ID in `flatpak.txt`.
- Let Flatpak apps read Dux's colours: `flatpak override --user --filesystem=xdg-config/gtk-3.0:ro --filesystem=xdg-config/gtk-4.0:ro --filesystem=xdg-config/kdeglobals:ro`. A `--user` override also applies to system-installed apps.
- `gsettings set org.gnome.desktop.interface color-scheme prefer-dark`.

**Done when:** a second run reports nothing new to install.

### Phase 7: finish

- Print a short summary and remind Ian to:
  - reboot
  - run `theme-pick --dms` in kitty after first login (Dux has generated its colours by then)
  - turn on the Dux Greeter from Dux settings
  - enable `power-profiles-daemon` / `cups` if he wants the Dux power and printing panels (the script enables no services)

## Package lists

The lists in `packages/` were written from the approved questionnaire (`ANSWERS.md`) and checked against the repos, the AUR and Flathub on 2026-10-27. If `--check` flags one later, look it up on archlinux.org/packages, the AUR or flathub.org and update the line.

Notes on names:
- There is no stable `dux-shell` package; the only one is `dux-shell-git` in the AUR. Its `dgop` dependency comes from `dux-gop` (repo).
- The Mango `exec_once` session lines from older Dux docs are not needed. `dms setup` handles the session, and adding them (or `dms run`) can start the shell twice.

## Open items for Ian

- [x] Questionnaire done (`ANSWERS.md`).
- [ ] In archinstall: minimal profile, Network = NetworkManager, Audio = PipeWire, graphics driver for your GPU.
- [ ] Push this folder to a git repo so a new install is just `git clone` + `./install.sh`.

## Sources

- MangoWM install docs: https://mangowm.github.io/docs/installation.md
- Dux Shell install docs: https://duxlabs.dev/docs/dms/installation
- Dux Shell README: https://github.com/duxlabs-dev/dux-shell
- Arch wiki, partial upgrades: https://wiki.archlinux.org/title/System_maintenance#Partial_upgrades_are_unsupported
