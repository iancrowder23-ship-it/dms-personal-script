#!/usr/bin/env bash
# The line above (the "shebang") tells Linux to run this file with bash.
#
# Arch post-install script: MangoWM + Dux Shell 2.0, apps and dotfiles.
# Run as your normal user right after archinstall. See PLAN.md.
#
#   ./install.sh          run every phase in order
#   ./install.sh --check  only check that every package name still exists

# Strict mode:
#   -e           stop the script as soon as any command fails
#   -u           treat using an unset variable as an error (catches typos)
#   -o pipefail  a pipeline like `a | b` fails if any part fails, not just the last
set -euo pipefail

# Folder this script lives in, so it works no matter where you run it from.
# $(...) runs a command and uses its output as text.
# "${BASH_SOURCE[0]}" is the path of this script file.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_DIR="$SCRIPT_DIR/packages"

# ── Helpers ──────────────────────────────────────────────────

# A function: call it like a command, e.g. `header "Packages"`.
# $1 is the first argument passed to it.
header() {
    printf '\n==> %s\n' "$1"
}

# Print an error to stderr (>&2) and stop the script with a failure code.
die() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
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

    printf '  MISSING  %s line %s: %s\n' "${file#"$SCRIPT_DIR"/}" "${line_number:-?}" "$name"

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
        printf '  SKIPPED  packages/aur.txt: paru is not installed yet (Phase 2 installs it)\n'
        SKIPPED=$((SKIPPED + 1))
    fi

    # Flathub. Needs flatpak and the flathub remote, which Phases 3 and 6 set up.
    # The pipe (|) sends the remote list into grep; -q means "just succeed or fail, print nothing".
    if command -v flatpak >/dev/null 2>&1 && flatpak remotes --columns=name | grep -qx flathub; then
        check_list "$PACKAGES_DIR/flatpak.txt" flatpak remote-info flathub
    else
        printf '  SKIPPED  packages/flatpak.txt: flatpak or the flathub remote is not set up yet (Phase 6 adds it)\n'
        SKIPPED=$((SKIPPED + 1))
    fi

    echo
    if [[ "$MISSING" -gt 0 ]]; then
        printf '%d name(s) not found. Fix the lines above (look the new name up on archlinux.org/packages, aur.archlinux.org or flathub.org).\n' "$MISSING"
        exit 1
    fi

    if [[ "$SKIPPED" -gt 0 ]]; then
        printf 'All checked names found (%d list(s) skipped, see above).\n' "$SKIPPED"
    else
        printf 'All names found.\n'
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

    if command -v paru >/dev/null 2>&1; then
        echo "  paru is already installed"
        return
    fi

    echo "  Installing paru from the AUR (paru-bin)"

    local build_dir
    # mktemp -d makes a new empty folder in /tmp with a unique name and prints its path.
    build_dir="$(mktemp -d)"

    git clone https://aur.archlinux.org/paru-bin.git "$build_dir/paru-bin"

    # The ( ... ) runs its commands in a subshell: the `cd` only applies inside it,
    # so the rest of the script stays in the folder it started in.
    # makepkg -s installs build dependencies, -i installs the finished package.
    (cd "$build_dir/paru-bin" && makepkg -si --noconfirm)

    # -r deletes the folder and everything in it; -f doesn't complain if it's already gone.
    rm -rf "$build_dir"
    echo "  paru installed"
}

phase_packages() {
    header "Phase 3: packages"
    echo "  (not built yet)"
}

phase_dotfiles() {
    header "Phase 4: dotfiles, shell and editor"
    echo "  (not built yet)"
}

phase_dux_shell() {
    header "Phase 5: Dux Shell"
    echo "  (not built yet)"
}

phase_flatpak() {
    header "Phase 6: Flatpak and dark mode"
    echo "  (not built yet)"
}

phase_finish() {
    header "Phase 7: finish"
    echo "  (not built yet)"
}

# ── Main ─────────────────────────────────────────────────────

usage() {
    echo "Usage: ./install.sh [--check]"
    echo "  (no option)  run every phase in order"
    echo "  --check      only check that every package name still exists, install nothing"
}

main() {
    # $EUID is the current user's ID; root is 0.
    # AUR helpers refuse to run as root, so the whole script runs as you and uses sudo only for pacman.
    if [[ "$EUID" -eq 0 ]]; then
        die "Run this as your normal user, not root. It uses sudo where needed."
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
    phase_finish
}

# Start here. "$@" passes along every argument the script was given.
main "$@"
