#!/usr/bin/env bash
# The line above (the "shebang") tells Linux to run this file with bash.
#
# Arch post-install script: MangoWM + Dux Shell 2.0, apps and dotfiles.
# Run as your normal user right after archinstall. See PLAN.md.
#
#   ./install.sh          run every phase in order
#   ./install.sh --check  only check that every package name still exists
#
# One-line install (see bootstrap below):
#   curl -fsSL https://raw.githubusercontent.com/iancrowder23-ship-it/dms-personal-script/main/install.sh | bash

# Strict mode:
#   -e           stop the script as soon as any command fails
#   -u           treat using an unset variable as an error (catches typos)
#   -o pipefail  a pipeline like `a | b` fails if any part fails, not just the last
set -euo pipefail

REPO_URL="https://github.com/iancrowder23-ship-it/dms-personal-script.git"
CLONE_DIR="$HOME/.local/share/dms-personal-script"

# Folder this script lives in, so it works no matter where you run it from.
# $(...) runs a command and uses its output as text.
# "${BASH_SOURCE[0]}" is the path of this script file. When the script is piped
# in through curl there is no file, so ${...:-} gives an empty string instead of an error.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" && pwd)"
PACKAGES_DIR="$SCRIPT_DIR/packages"

# ── Colours ──────────────────────────────────────────────────

# ANSI escape codes. Only the basic 16 colours, so they also work on the plain
# Linux console (the TTY you're on right after archinstall).
# -t 1 means "output is a terminal": no colour codes when output goes to a file or pipe.
# NO_COLOR is a common convention for turning colour off (no-color.org).
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
    # $'...' lets bash understand \033 (the escape character).
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    RED=$'\033[1;31m'
    GREEN=$'\033[1;32m'
    YELLOW=$'\033[1;33m'
    BLUE=$'\033[1;36m'   # bright cyan, the closest basic colour to Arch blue
    RESET=$'\033[0m'
else
    BOLD="" DIM="" RED="" GREEN="" YELLOW="" BLUE="" RESET=""
fi

# ── Helpers ──────────────────────────────────────────────────

# A function: call it like a command, e.g. `header "Packages"`.
# $1 is the first argument passed to it.
header() {
    printf '\n%s::%s %s%s%s\n' "$BLUE" "$RESET" "$BOLD" "$1" "$RESET"
}

# One line of progress inside a phase.
info() {
    printf '  %s->%s %s\n' "$BLUE" "$RESET" "$1"
}

# Something finished or is already in place.
ok() {
    printf '  %s->%s %s\n' "$GREEN" "$RESET" "$1"
}

# Worth noticing, but not an error.
warn() {
    printf '  %s!%s  %s\n' "$YELLOW" "$RESET" "$1"
}

# Print an error to stderr (>&2) and stop the script with a failure code.
die() {
    printf '%sError:%s %s\n' "$RED" "$RESET" "$1" >&2
    exit 1
}

# Ask a yes/no question; succeeds only on y or yes. Enter on its own means no.
# Reads from /dev/tty (your keyboard) so it works under curl | bash too.
# Usage: if ask "Do the thing?"; then ...; fi
ask() {
    local reply=""
    printf '\n%s?%s %s %s[y/N]%s ' "$YELLOW" "$RESET" "$1" "$DIM" "$RESET"
    # If there is no keyboard to read from (e.g. run by another program), the answer is no.
    # 2>/dev/null comes first so it also hides the error if /dev/tty can't be opened.
    read -r reply 2>/dev/null </dev/tty || true
    # ,, lowercases the text, so Y and YES work too.
    [[ "${reply,,}" == "y" || "${reply,,}" == "yes" ]]
}

# The Arch logo and a title, shown once at the start.
banner() {
    printf '%s' "$BLUE"
    # A here-document: everything up to the line EOF is printed as-is.
    # The quotes around 'EOF' stop bash from treating ` and $ in the art as code.
    cat <<'EOF'

                   -`
                  .o+`
                 `ooo/
                `+oooo:
               `+oooooo:
               -+oooooo+:
             `/:-:++oooo+:
            `/++++/+++++++:
           `/++++++++++++++:
          `/+++ooooooooooooo/`
         ./ooosssso++osssssso+`
        .oossssso-````/ossssss+`
       -osssssso.      :ssssssso.
      :osssssss/        osssso+++.
     /ossssssss/        +ssssooo/-
   `/ossssso+/:-        -:/+osssso+-
  `+sso+:-`                 `.-/+oso:
 `++:.                           `-/+/
 .`                                 `/
EOF
    printf '%s\n' "$RESET"
    printf '  %sdms-personal-script%s\n' "$BOLD" "$RESET"
    printf '  %sArch + MangoWM + Dux Shell%s\n' "$DIM" "$RESET"
}

# Read a package list file into the global array LIST.
# Skips blank lines and lines starting with #, and strips spaces.
# Usage: read_list "$PACKAGES_DIR/pacman.txt"; then use "${LIST[@]}".
read_list() {
    # `local` keeps a variable inside this function only.
    local file="$1"
    local line

    # [[ ... ]] is bash's test syntax. -f means "is a regular file".
    if [[ ! -f "$file" ]]; then
        die "List file not found: $file"
    fi

    # An array. () makes it empty.
    LIST=()

    # Read the file one line at a time.
    #   IFS=     keep leading/trailing spaces (we strip them ourselves below)
    #   -r       don't treat backslashes specially
    #   || [[ -n "$line" ]]  also handle a last line with no newline at the end
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Remove every space and tab from the line (package names never contain spaces).
        # ${var//pattern/} means "var with every match of pattern removed".
        line="${line//[[:space:]]/}"

        # Skip blank lines and comments. `continue` jumps to the next line.
        if [[ -z "$line" || "$line" == \#* ]]; then
            continue
        fi

        # += appends to the array.
        LIST+=("$line")
    done < "$file"
}

# ── Check mode ───────────────────────────────────────────────

# Counters for the check summary.
MISSING=0
SKIPPED=0

# Print one missing name with the file and line number to fix.
report_missing() {
    local file="$1"
    local name="$2"
    local line_number

    # grep -n prints "line:text"; -x matches the whole line; -F means plain text, not a pattern.
    # cut keeps only the part before the first ":", head keeps the first match.
    # `|| true` stops strict mode from exiting if grep finds nothing.
    line_number="$(grep -nxF -- "$name" "$file" | cut -d: -f1 | head -n 1 || true)"

    printf '  %sMISSING%s  %s line %s: %s\n' "$RED" "$RESET" "${file#"$SCRIPT_DIR"/}" "${line_number:-?}" "$name"

    # $(( ... )) does arithmetic.
    MISSING=$((MISSING + 1))
}

# Check a list file using a lookup command.
# Usage: check_list FILE COMMAND...   e.g. check_list pacman.txt pacman -Si
# The name to check is added to the end of the command.
check_list() {
    local file="$1"
    # shift drops $1, so "$@" now holds only the command and its options.
    shift
    local name

    read_list "$file"
    printf '  %s (%d names)\n' "${file#"$SCRIPT_DIR"/}" "${#LIST[@]}"

    # "${LIST[@]}" expands to every item in the array, each kept as one word.
    for name in "${LIST[@]}"; do
        # >/dev/null 2>&1 hides the command's normal output and its errors.
        # `if ! cmd` runs the block when the command fails (name not found).
        if ! "$@" "$name" >/dev/null 2>&1; then
            report_missing "$file" "$name"
        fi
    done
}

run_check() {
    header "Checking package names"

    # Official repos. -Si looks a package up in the synced repo databases.
    check_list "$PACKAGES_DIR/pacman.txt" pacman -Si

    # AUR. Needs paru, which Phase 2 installs.
    # `command -v` succeeds if a program exists in PATH.
    if command -v paru >/dev/null 2>&1; then
        # --aur makes paru look only in the AUR, so a repo package can't pass by mistake.
        check_list "$PACKAGES_DIR/aur.txt" paru -Si --aur
    else
        printf '  %sSKIPPED%s  packages/aur.txt: paru is not installed yet (Phase 2 installs it)\n' "$YELLOW" "$RESET"
        SKIPPED=$((SKIPPED + 1))
    fi

    # Flathub. Needs flatpak and the flathub remote, which Phases 3 and 6 set up.
    # The pipe (|) sends the remote list into grep; -q means "just succeed or fail, print nothing".
    if command -v flatpak >/dev/null 2>&1 && flatpak remotes --columns=name | grep -qx flathub; then
        check_list "$PACKAGES_DIR/flatpak.txt" flatpak remote-info flathub
    else
        printf '  %sSKIPPED%s  packages/flatpak.txt: flatpak or the flathub remote is not set up yet (Phase 6 adds it)\n' "$YELLOW" "$RESET"
        SKIPPED=$((SKIPPED + 1))
    fi

    echo
    if [[ "$MISSING" -gt 0 ]]; then
        printf '%s%d name(s) not found.%s Fix the lines above (look the new name up on archlinux.org/packages, aur.archlinux.org or flathub.org).\n' "$RED" "$MISSING" "$RESET"
        exit 1
    fi

    if [[ "$SKIPPED" -gt 0 ]]; then
        printf '%sAll checked names found%s (%d list(s) skipped, see above).\n' "$GREEN" "$RESET" "$SKIPPED"
    else
        printf '%sAll names found.%s\n' "$GREEN" "$RESET"
    fi
}

# ── Phases ───────────────────────────────────────────────────
# Each phase is filled in as it gets built (see PLAN.md).

phase_update_and_aur_helper() {
    header "Phase 2: system update and AUR helper"

    # Full upgrade on every run. Arch doesn't support installing onto an out-of-date system.
    sudo pacman -Syu --noconfirm

    # git and base-devel are needed to build AUR packages.
    # --needed skips anything already installed, so re-running is safe.
    sudo pacman -S --needed --noconfirm git base-devel

    # Actually run paru instead of just checking it's in PATH: a paru built against an
    # older pacman fails with "error while loading shared libraries: libalpm.so..."
    # after pacman updates, and that broken copy needs rebuilding.
    if paru --version >/dev/null 2>&1; then
        ok "paru is already installed"
        return
    fi

    # paru-bin is prebuilt against one libalpm version and breaks whenever pacman bumps it,
    # which is the library error. It conflicts with the source-built paru, so remove it first.
    # -Q succeeds if the package is installed.
    if pacman -Q paru-bin >/dev/null 2>&1; then
        warn "Removing broken paru-bin"
        sudo pacman -R --noconfirm paru-bin
    fi

    info "Building paru from the AUR"

    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
    local build_dir
    mkdir -p "$cache_dir"
    # mktemp -d makes a new empty folder with a unique name and prints its path.
    # It goes in ~/.cache, not /tmp: /tmp is RAM-backed on Arch and too small for a Rust build.
    build_dir="$(mktemp -d "$cache_dir/paru-build.XXXXXX")"

    git clone https://aur.archlinux.org/paru.git "$build_dir/paru"

    # The ( ... ) runs its commands in a subshell: the `cd` only applies inside it,
    # so the rest of the script stays in the folder it started in.
    # makepkg -s installs build dependencies (like rust), -i installs the finished package.
    (cd "$build_dir/paru" && makepkg -si --noconfirm)

    # -r deletes the folder and everything in it; -f doesn't complain if it's already gone.
    rm -rf "$build_dir"
    ok "paru installed"
}

phase_packages() {
    header "Phase 3: packages"

    # Official repo packages, all in one pacman call.
    read_list "$PACKAGES_DIR/pacman.txt"
    sudo pacman -S --needed --noconfirm "${LIST[@]}"

    # AUR packages. paru calls sudo itself when it needs to, so no sudo here.
    read_list "$PACKAGES_DIR/aur.txt"
    # ${#LIST[@]} is the number of items in the array.
    if [[ "${#LIST[@]}" -eq 0 ]]; then
        info "aur.txt is empty, nothing to install from the AUR"
        return
    fi
    paru -S --needed --noconfirm "${LIST[@]}"
}

phase_dotfiles() {
    header "Phase 4: dotfiles, shell and editor"

    # ── kitty + fish: Ian's fish-dotfiles repo and its own installer ──
    local dotfiles_repo="https://github.com/iancrowder23-ship-it/fish-dotfiles.git"
    local dotfiles_dir="$HOME/.local/share/fish-dotfiles"

    # -d means "is a directory". A .git folder inside means it's a git checkout.
    if [[ -d "$dotfiles_dir/.git" ]]; then
        info "Updating fish-dotfiles"
        # -C runs git as if inside that folder. --ff-only refuses to merge, so local edits are never mixed in.
        git -C "$dotfiles_dir" pull --ff-only
    elif [[ -e "$dotfiles_dir" ]]; then
        # -e means "exists at all". Something is there but it isn't a git checkout: don't touch it.
        die "$dotfiles_dir exists but is not a git checkout. Move it aside and re-run."
    else
        info "Cloning fish-dotfiles"
        git clone "$dotfiles_repo" "$dotfiles_dir"
    fi

    # -y: no questions. Colours are set later with `theme-pick --dms` (see Phase 7).
    "$dotfiles_dir/install.sh" -y

    # ── environment.d: symlink each file from this repo ──
    local env_source_dir="$SCRIPT_DIR/dotfiles/environment.d"
    local env_target_dir="$HOME/.config/environment.d"
    local source_file
    local target

    # -p creates parent folders too, and doesn't complain if the folder already exists.
    mkdir -p "$env_target_dir"

    # A glob: "$env_source_dir"/* expands to every file in that folder.
    for source_file in "$env_source_dir"/*; do
        # If the folder is empty the glob stays as a literal "*", so skip that case.
        if [[ ! -f "$source_file" ]]; then
            continue
        fi

        # basename strips the folder part: ".../qt6ct.conf" → "qt6ct.conf".
        target="$env_target_dir/$(basename "$source_file")"

        # -L means "is a symlink". A real file in the way gets renamed, never deleted.
        if [[ -e "$target" && ! -L "$target" ]]; then
            local backup
            backup="$target.bak-$(date +%Y%m%d-%H%M%S)"
            mv "$target" "$backup"
            warn "Moved existing $target to $backup"
        fi

        # ln -s makes a symlink; -f replaces an old link; -n treats an existing link as a file, not a folder.
        ln -sfn "$source_file" "$target"
        ok "Linked $target"
    done

    # ── Neovim: LazyVim starter config (LazyVim's official install steps) ──
    local nvim_dir="$HOME/.config/nvim"

    if [[ -e "$nvim_dir" ]]; then
        info "$nvim_dir already exists, leaving it alone"
    else
        info "Installing the LazyVim starter config"
        git clone https://github.com/LazyVim/starter "$nvim_dir"
        # Remove the starter's git history so the config becomes your own.
        rm -rf "$nvim_dir/.git"
    fi
}

phase_dux_shell() {
    header "Phase 5: Dux Shell"

    # Upstream's own command writes the Mango config (~/.config/mango) for Dux.
    # --skip-existing leaves configs that are already there alone, so re-running is safe.
    dms setup headless --compositor mango --skip-existing

    # Make sure dms.service starts with the Mango session, using upstream's command.
    # The output is saved in a variable first; `|| true` keeps strict mode from
    # stopping the script if the status command returns an error.
    local status
    status="$(dms systemd status 2>&1 || true)"

    # == with *text* on both sides means "contains text".
    if [[ "$status" == *mango-session.target* ]]; then
        ok "Dux Shell already starts with Mango"
    else
        dms systemd enable --compositor mango
        ok "Dux Shell will now start with Mango"
    fi

    # Login screen: greetd + dux-greeter-bin were installed in Phase 3.
    # Upstream's command points greetd at dms-greeter, picks Mango (the only compositor),
    # and enables greetd.service. It asks for sudo itself, and on re-runs it only
    # checks that everything is still set up. --yes skips its "Continue?" prompt.
    dms-greeter enable --yes
    ok "Dux Greeter is the login screen"
}

phase_flatpak() {
    header "Phase 6: Flatpak and dark mode"

    # Flathub, system-wide. --if-not-exists makes this a no-op on re-runs.
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

    read_list "$PACKAGES_DIR/flatpak.txt"
    if [[ "${#LIST[@]}" -eq 0 ]]; then
        info "flatpak.txt is empty, nothing to install"
    else
        # Already-installed apps are skipped.
        sudo flatpak install -y --noninteractive flathub "${LIST[@]}"
    fi

    # Let Flatpak apps read the GTK and KDE colour files Dux generates (read-only).
    # A --user override also applies to system-installed apps, and needs no sudo.
    flatpak override --user \
        --filesystem=xdg-config/gtk-3.0:ro \
        --filesystem=xdg-config/gtk-4.0:ro \
        --filesystem=xdg-config/kdeglobals:ro

    # Tell GTK, libadwaita and Flatpak apps to prefer dark mode.
    gsettings set org.gnome.desktop.interface color-scheme prefer-dark
    ok "Dark mode set for GTK, KDE and Flatpak apps"
}

phase_home_and_system() {
    header "Phase 7: home folders and system tweaks"

    # Desktop, Documents, Downloads, Music, Pictures, Public, Templates, Videos.
    # xdg-user-dirs (Phase 3) is the standard tool for this: it creates any that are
    # missing, leaves existing ones (like Downloads) alone, and tells apps where they are.
    xdg-user-dirs-update
    ok "Home folders ready (Documents, Pictures, Music, Videos, ...)"

    # Coloured pacman output. Arch ships the line commented out as "#Color".
    # grep -q only checks; sed -i edits the file in place, and only that one line.
    if grep -q '^#Color$' /etc/pacman.conf; then
        sudo sed -i 's/^#Color$/Color/' /etc/pacman.conf
        ok "Turned on colour in pacman"
    else
        ok "pacman colour already on"
    fi

    # Small built-in maintenance timers (systemctl enable is a no-op if already on):
    #   fstrim.timer          weekly SSD TRIM, keeps SSDs fast
    #   paccache.timer        weekly cleanup of old package files in pacman's cache (pacman-contrib)
    #   pkgfile-update.timer  daily refresh of pkgfile's "which package has this command" list
    sudo systemctl enable --now fstrim.timer paccache.timer pkgfile-update.timer
    ok "Maintenance timers on (SSD trim, package cache cleanup, pkgfile)"

    # Fill pkgfile's list now instead of waiting for the timer, so typing a command you
    # don't have tells you which package provides it (fish uses pkgfile for that).
    # compgen -G succeeds if the glob matches at least one file.
    if ! compgen -G "/var/cache/pkgfile/*.files" >/dev/null; then
        info "Downloading pkgfile's command list"
        sudo pkgfile --update
    fi
}

phase_finish() {
    header "Phase 8: finish"

    # Optional wallpaper pack. xdg-user-dir prints where your Pictures folder is.
    local wallpaper_dir
    wallpaper_dir="$(xdg-user-dir PICTURES)/wallpaper"

    if [[ -d "$wallpaper_dir/.git" ]]; then
        info "Updating wallpapers in $wallpaper_dir"
        git -C "$wallpaper_dir" pull --ff-only
    elif [[ -e "$wallpaper_dir" ]]; then
        warn "$wallpaper_dir exists but is not a git checkout, leaving it alone"
    elif ask "Download the mylinuxforwork wallpaper pack (about 1.2 GB) into $wallpaper_dir?"; then
        # --depth 1 skips the repo's history: only the current pictures are downloaded.
        git clone --depth 1 https://github.com/mylinuxforwork/wallpaper.git "$wallpaper_dir"
        ok "Wallpapers in $wallpaper_dir (pick one in Dux settings)"
    else
        info "Skipped wallpapers"
    fi

    printf '\n%sAll phases done.%s Next steps:\n' "$GREEN" "$RESET"
    printf '  %s1.%s Reboot.\n' "$BLUE" "$RESET"
    printf '  %s2.%s Log in, open kitty and run:  %stheme-pick --dms%s\n' "$BLUE" "$RESET" "$BOLD" "$RESET"
    printf '     %s(makes the terminal follow Dux'\''s wallpaper colours)%s\n' "$DIM" "$RESET"
    printf '  %s3.%s Run  %sdms-greeter sync%s  so the login screen matches your Dux theme.\n' "$BLUE" "$RESET" "$BOLD" "$RESET"
    printf '  %s4.%s For the Dux power and printing panels, enable their services:\n' "$BLUE" "$RESET"
    printf '     %ssudo systemctl enable --now power-profiles-daemon cups%s\n' "$BOLD" "$RESET"
}

# ── Bootstrap (curl | bash) ──────────────────────────────────

# When run through curl, only this one file arrives, without packages/ and dotfiles/.
# So: install git, clone (or update) the whole repo, and run install.sh from the clone.
bootstrap() {
    header "Getting dms-personal-script"

    # A full upgrade together with git, since Arch doesn't support partial upgrades.
    sudo pacman -Syu --needed --noconfirm git

    if [[ -d "$CLONE_DIR/.git" ]]; then
        info "Updating $CLONE_DIR"
        git -C "$CLONE_DIR" pull --ff-only
    elif [[ -e "$CLONE_DIR" ]]; then
        die "$CLONE_DIR exists but is not a git checkout. Move it aside and re-run."
    else
        info "Cloning into $CLONE_DIR"
        git clone "$REPO_URL" "$CLONE_DIR"
    fi

    # exec replaces this process with the cloned install.sh, passing the same arguments.
    # </dev/tty connects its input to your keyboard: under curl | bash, input is the
    # download pipe, and prompts (sudo, chsh, paru) need to read from you instead.
    exec "$CLONE_DIR/install.sh" "$@" </dev/tty
}

# ── Main ─────────────────────────────────────────────────────

usage() {
    echo "Usage: ./install.sh [--check]   (or through curl, see README.md)"
    echo "  (no option)  run every phase in order"
    echo "  --check      only check that every package name still exists, install nothing"
}

main() {
    # $EUID is the current user's ID; root is 0.
    # AUR helpers refuse to run as root, so the whole script runs as you and uses sudo only for pacman.
    if [[ "$EUID" -eq 0 ]]; then
        die "Run this as your normal user, not root. It uses sudo where needed."
    fi

    # Show the logo once. Under curl | bash the script restarts itself from the clone
    # (see bootstrap), and the exported variable tells that second run it's already shown.
    if [[ -z "${DMS_BANNER_SHOWN:-}" ]]; then
        banner
        export DMS_BANNER_SHOWN=1
    fi

    # No packages/ folder next to this script means it came through curl: fetch the repo first.
    if [[ ! -d "$PACKAGES_DIR" ]]; then
        bootstrap "$@"
    fi

    # $# is the number of arguments. `case` picks a branch by matching text.
    if [[ $# -gt 0 ]]; then
        case "$1" in
            --check)
                run_check
                exit 0
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                usage
                die "Unknown option: $1"
                ;;
        esac
    fi

    phase_update_and_aur_helper
    phase_packages
    phase_dotfiles
    phase_dux_shell
    phase_flatpak
    phase_home_and_system
    phase_finish
}

# Start here. "$@" passes along every argument the script was given.
main "$@"
