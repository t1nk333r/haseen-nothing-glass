#!/usr/bin/env bash

# merge.sh - Extract translatable strings from QML files into .pot templates
#
# Scans each shippable widget package for i18n() calls in its QML and writes a
# .pot (Portable Object Template) that translators copy to start a translation.
# Existing .po files are merged forward so nothing already translated is lost.
#
# Usage:
#   ./translate/merge.sh              # all shippable packages (skips test-*)
#   ./translate/merge.sh weather      # a single package
#
# Requires gettext (xgettext, msgmerge):
#   Debian/Ubuntu: sudo apt install gettext
#   Fedora:        sudo dnf install gettext
#   Arch:          sudo pacman -S gettext

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ISSUES_URL="https://github.com/jaxparrow07/macos-widgets/issues"

if ! command -v xgettext &>/dev/null; then
    echo "[!] xgettext not found. Install gettext:"
    echo "    Debian/Ubuntu: sudo apt install gettext"
    echo "    Fedora:        sudo dnf install gettext"
    echo "    Arch:          sudo pacman -S gettext"
    exit 1
fi

merge_package() {
    local PACKAGE_NAME="$1"

    # Skip development-only widgets.
    if [[ "$PACKAGE_NAME" == test-* ]]; then
        return 0
    fi

    local PACKAGE_DIR="${PROJECT_DIR}/packages/${PACKAGE_NAME}"
    local METADATA_FILE="${PACKAGE_DIR}/metadata.json"

    if [[ ! -f "$METADATA_FILE" ]]; then
        echo "[!] No metadata.json for: ${PACKAGE_NAME}"
        return 1
    fi

    local PLUGIN_ID
    PLUGIN_ID=$(jq -r ".KPlugin.Id" "$METADATA_FILE")
    local DOMAIN="plasma_applet_${PLUGIN_ID}"
    local POT_DIR="${SCRIPT_DIR}/${PACKAGE_NAME}"
    local POT_FILE="${POT_DIR}/template.pot"

    echo "[*] ${PACKAGE_NAME} (${DOMAIN})"

    # Collect QML files, paths relative to the project root for clean references.
    local QML_FILES=()
    while IFS= read -r -d '' file; do
        QML_FILES+=("$file")
    done < <(cd "$PROJECT_DIR" && find "packages/${PACKAGE_NAME}/contents" -name "*.qml" -print0 2>/dev/null)

    if [[ ${#QML_FILES[@]} -eq 0 ]]; then
        echo "    [!] No QML files, skipping"
        return 0
    fi

    mkdir -p "$POT_DIR"

    local VERSION
    VERSION=$(jq -r ".KPlugin.Version // \"1.0\"" "$METADATA_FILE")

    # xgettext reads QML's i18n() family when treated as JavaScript.
    (cd "$PROJECT_DIR" && xgettext \
        --from-code=UTF-8 \
        --language=JavaScript \
        --keyword=i18n:1 \
        --keyword=i18nc:1c,2 \
        --keyword=i18np:1,2 \
        --keyword=i18ncp:1c,2,3 \
        --package-name="${DOMAIN}" \
        --package-version="${VERSION}" \
        --foreign-user \
        --msgid-bugs-address="${ISSUES_URL}" \
        -o "$POT_FILE" \
        "${QML_FILES[@]}")

    if [[ ! -f "$POT_FILE" ]]; then
        echo "    [!] No translatable strings found"
        return 0
    fi

    # Tidy the placeholder header xgettext emits.
    local WIDGET_NAME_PRETTY
    WIDGET_NAME_PRETTY=$(jq -r ".KPlugin.Name // \"${PACKAGE_NAME}\"" "$METADATA_FILE")
    sed -i \
        -e "s/# SOME DESCRIPTIVE TITLE./# ${WIDGET_NAME_PRETTY} - Translation Template/" \
        -e "/# Copyright (C)/d" \
        -e "/# This file is distributed/d" \
        -e "/# This file is put in the public domain/d" \
        -e "s/# FIRST AUTHOR <EMAIL@ADDRESS>, YEAR./# Translators:/" \
        -e "s/\"PO-Revision-Date: YEAR-MO-DA HO:MI+ZONE\\\\n\"/\"PO-Revision-Date: 2025-01-01 00:00+0000\\\\n\"/" \
        -e "s/\"Last-Translator: FULL NAME <EMAIL@ADDRESS>\\\\n\"/\"Last-Translator: \\\\n\"/" \
        -e "s/\"Language-Team: LANGUAGE <LL@li.org>\\\\n\"/\"Language-Team: \\\\n\"/" \
        -e "s/charset=CHARSET/charset=UTF-8/" \
        "$POT_FILE"

    local STRING_COUNT
    STRING_COUNT=$(grep -c "^msgid " "$POT_FILE" 2>/dev/null || echo "0")
    STRING_COUNT=$((STRING_COUNT - 1))  # drop the empty header msgid
    echo "    [+] ${STRING_COUNT} strings -> translate/${PACKAGE_NAME}/template.pot"

    # Roll the new template into any existing translations.
    local PO_COUNT=0
    for PO_FILE in "${POT_DIR}"/*.po; do
        [[ -f "$PO_FILE" ]] || continue
        local LANG_CODE
        LANG_CODE=$(basename "$PO_FILE" .po)
        echo "    [*] merging ${LANG_CODE}.po"
        msgmerge --update --no-fuzzy-matching "$PO_FILE" "$POT_FILE"
        PO_COUNT=$((PO_COUNT + 1))
    done
    [[ $PO_COUNT -gt 0 ]] && echo "    [+] merged ${PO_COUNT} translation(s)"

    return 0
}

echo "macOS Widgets - extracting translatable strings"
echo ""

if [[ -n "$1" ]]; then
    if [[ ! -d "${PROJECT_DIR}/packages/$1" ]]; then
        echo "[!] Package not found: $1"
        exit 1
    fi
    merge_package "$1"
else
    for PACKAGE_DIR in "${PROJECT_DIR}"/packages/*/; do
        merge_package "$(basename "$PACKAGE_DIR")" || true
    done
fi

echo ""
echo "[+] Templates are in translate/<package>/template.pot"
echo ""
echo "To start a translation:"
echo "  cp translate/<package>/template.pot translate/<package>/<lang>.po"
echo "  # edit <lang>.po (Lokalize, Poedit, or any text editor)"
echo "  ./translate/build.sh   # compile and install the .mo files"
