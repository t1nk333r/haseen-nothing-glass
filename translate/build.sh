#!/usr/bin/env bash

# build.sh - Compile .po translations into .mo files inside each package
#
# Compiles every translate/<package>/*.po into a binary .mo placed where Plasma
# looks for it, so the translation ships with the widget on install/package.
#
# Usage:
#   ./translate/build.sh              # all shippable packages (skips test-*)
#   ./translate/build.sh weather      # a single package
#
# Requires gettext (msgfmt):
#   Debian/Ubuntu: sudo apt install gettext
#   Fedora:        sudo dnf install gettext
#   Arch:          sudo pacman -S gettext

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if ! command -v msgfmt &>/dev/null; then
    echo "[!] msgfmt not found. Install gettext:"
    echo "    Debian/Ubuntu: sudo apt install gettext"
    echo "    Fedora:        sudo dnf install gettext"
    echo "    Arch:          sudo pacman -S gettext"
    exit 1
fi

build_package() {
    local PACKAGE_NAME="$1"

    # Skip development-only widgets.
    if [[ "$PACKAGE_NAME" == test-* ]]; then
        return 0
    fi

    local PACKAGE_DIR="${PROJECT_DIR}/packages/${PACKAGE_NAME}"
    local METADATA_FILE="${PACKAGE_DIR}/metadata.json"
    local PO_DIR="${SCRIPT_DIR}/${PACKAGE_NAME}"

    [[ -f "$METADATA_FILE" ]] || { echo "[!] No metadata.json for: ${PACKAGE_NAME}"; return 1; }
    [[ -d "$PO_DIR" ]] || return 0

    local PLUGIN_ID
    PLUGIN_ID=$(jq -r ".KPlugin.Id" "$METADATA_FILE")
    local DOMAIN="plasma_applet_${PLUGIN_ID}"

    local LANG_COUNT=0
    for PO_FILE in "${PO_DIR}"/*.po; do
        [[ -f "$PO_FILE" ]] || continue

        local LANG_CODE
        LANG_CODE=$(basename "$PO_FILE" .po)
        local LOCALE_DIR="${PACKAGE_DIR}/contents/locale/${LANG_CODE}/LC_MESSAGES"
        local MO_FILE="${LOCALE_DIR}/${DOMAIN}.mo"

        mkdir -p "$LOCALE_DIR"
        msgfmt -o "$MO_FILE" "$PO_FILE"

        echo "    [+] ${PACKAGE_NAME}/${LANG_CODE} -> ${DOMAIN}.mo"
        LANG_COUNT=$((LANG_COUNT + 1))
    done

    if [[ $LANG_COUNT -eq 0 ]]; then
        echo "[*] ${PACKAGE_NAME}: no .po files yet"
    fi

    return 0
}

echo "macOS Widgets - compiling translations"
echo ""

if [[ -n "$1" ]]; then
    if [[ ! -d "${PROJECT_DIR}/packages/$1" ]]; then
        echo "[!] Package not found: $1"
        exit 1
    fi
    build_package "$1"
else
    for PACKAGE_DIR in "${PROJECT_DIR}"/packages/*/; do
        build_package "$(basename "$PACKAGE_DIR")" || true
    done
fi

echo ""
echo "[+] Done. Run ./install.sh to update installed widgets."
