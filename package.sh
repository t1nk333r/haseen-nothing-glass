#!/usr/bin/env bash

# Package KDE Plasma widgets into distributable .plasmoid files

set -e

PACKAGE_DIR="2-packaged"
PACKAGES_SRC="packages"

package_widget() {
	local WIDGET_NAME="$1"
	local WIDGET_DIR="${PACKAGES_SRC}/${WIDGET_NAME}"
	local METADATA_FILE="${WIDGET_DIR}/metadata.json"

	if [[ ! -f "$METADATA_FILE" ]]; then
		echo "[!] Error: metadata.json not found in ${WIDGET_NAME}"
		return 1
	fi

	echo ""
	echo "================================"
	echo "[*] Packaging: ${WIDGET_NAME}"
	echo "================================"

	local WIDGET_ID=$(jq -r '.KPlugin.Id' "$METADATA_FILE")
	local VERSION=$(jq -r '.KPlugin.Version' "$METADATA_FILE")

	if [[ -z "$WIDGET_ID" || "$WIDGET_ID" == "null" ]]; then
		echo "[!] Error: Invalid widget ID in metadata.json"
		return 1
	fi

	local OUTPUT_NAME="${WIDGET_NAME}"
	if [[ -n "$VERSION" && "$VERSION" != "null" ]]; then
		OUTPUT_NAME="${WIDGET_NAME}-${VERSION}"
	fi
	local OUTPUT_FILE="${PACKAGE_DIR}/${OUTPUT_NAME}.plasmoid"

	local TEMP_DIR=$(mktemp -d)
	trap "rm -rf $TEMP_DIR" EXIT

	echo "[*] Copying widget files (dereferencing symlinks)..."
	tar -C "${WIDGET_DIR}" -chf - . | tar -C "$TEMP_DIR" -xf -

	echo "[*] Cleaning up development files..."
	find "$TEMP_DIR" -name "*.swp" -delete 2>/dev/null || true
	find "$TEMP_DIR" -name "*.swo" -delete 2>/dev/null || true
	find "$TEMP_DIR" -name "*~" -delete 2>/dev/null || true
	find "$TEMP_DIR" -name ".DS_Store" -delete 2>/dev/null || true

	mkdir -p "$PACKAGE_DIR"
	local ABS_OUTPUT=$(realpath "$OUTPUT_FILE")

	echo "[*] Creating .plasmoid package..."
	pushd "$TEMP_DIR" > /dev/null
	zip -q -r "$ABS_OUTPUT" .
	popd > /dev/null

	echo "[+] Package created successfully!"
	echo "    Widget ID: ${WIDGET_ID}"
	echo "    Version: ${VERSION}"
	echo "    Output: ${ABS_OUTPUT}"
	echo "    Size: $(du -h "$OUTPUT_FILE" | cut -f1)"

	return 0
}

print_usage() {
	echo "Usage:"
	echo "  ./package.sh <package_folder>    Package a single widget (works for test-* too)"
	echo "  ./package.sh -a | --all          Package all non-test widgets"
	echo "  ./package.sh -t | --test         Package only test-* widgets"
	echo "  ./package.sh -a -t               Package everything (or: -at)"
}

WANT_ALL=false
WANT_TEST=false
WIDGET_NAME=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		-a|--all)
			WANT_ALL=true
			shift
			;;
		-t|--test)
			WANT_TEST=true
			shift
			;;
		-at|-ta)
			WANT_ALL=true
			WANT_TEST=true
			shift
			;;
		-h|--help)
			print_usage
			exit 0
			;;
		-*)
			echo "[!] Unknown flag: $1"
			print_usage
			exit 1
			;;
		*)
			if [[ -n "$WIDGET_NAME" ]]; then
				echo "[!] Multiple widget names not supported: $WIDGET_NAME and $1"
				exit 1
			fi
			WIDGET_NAME="$1"
			shift
			;;
	esac
done

if [[ "$WANT_ALL" == "true" || "$WANT_TEST" == "true" ]]; then
	if [[ -n "$WIDGET_NAME" ]]; then
		echo "[!] Cannot combine a widget name with -a / -t"
		exit 1
	fi

	ALL_WIDGETS=($(ls -d ${PACKAGES_SRC}/*/ 2>/dev/null | xargs -n 1 basename))
	if [[ ${#ALL_WIDGETS[@]} -eq 0 ]]; then
		echo "[!] No widgets found in ${PACKAGES_SRC} directory"
		exit 1
	fi

	WIDGETS=()
	for widget in "${ALL_WIDGETS[@]}"; do
		if [[ "$widget" == test-* ]]; then
			if [[ "$WANT_TEST" == "true" ]]; then
				WIDGETS+=("$widget")
			fi
		else
			if [[ "$WANT_ALL" == "true" ]]; then
				WIDGETS+=("$widget")
			fi
		fi
	done

	if [[ ${#WIDGETS[@]} -eq 0 ]]; then
		echo "[!] No matching widgets to package"
		exit 1
	fi

	echo "[*] Packaging ${#WIDGETS[@]} widget(s)..."
	for widget in "${WIDGETS[@]}"; do
		package_widget "$widget" || echo "[!] Failed: $widget"
	done

	echo ""
	echo "[+] All packages saved to: $(realpath $PACKAGE_DIR)"

elif [[ -n "$WIDGET_NAME" && -d "${PACKAGES_SRC}/$WIDGET_NAME" ]]; then
	package_widget "$WIDGET_NAME"
	echo "[+] Packaging complete!"
else
	if [[ -n "$WIDGET_NAME" ]]; then
		echo "[!] Widget package not found: $WIDGET_NAME"
	fi
	echo "[+] Available widgets:"
	ls "$PACKAGES_SRC"
	echo ""
	print_usage
	exit 1
fi
