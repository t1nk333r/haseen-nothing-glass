#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

restart_plasmashell() {
	echo "[*] Reloading plasmashell..."

	if pgrep -x plasmashell >/dev/null; then
		if command -v kquitapp6 >/dev/null; then
			kquitapp6 plasmashell >/dev/null 2>&1 || true
		elif command -v qdbus6 >/dev/null; then
			qdbus6 org.kde.plasmashell /MainApplication quit >/dev/null 2>&1 || true
		else
			echo "[!] kquitapp6/qdbus6 not found; falling back to SIGTERM"
			killall plasmashell >/dev/null 2>&1 || true
		fi

		for _ in {1..50}; do
			if ! pgrep -x plasmashell >/dev/null; then
				break
			fi
			sleep 0.1
		done

		if pgrep -x plasmashell >/dev/null; then
			echo "[!] Plasmashell did not quit cleanly; sending SIGTERM"
			killall plasmashell >/dev/null 2>&1 || true
			sleep 0.5
		fi
	fi

	if command -v kstart6 >/dev/null; then
		kstart6 plasmashell >/dev/null 2>&1
	elif command -v kstart >/dev/null; then
		kstart plasmashell >/dev/null 2>&1
	else
		nohup plasmashell >/dev/null 2>&1 &
	fi

	echo "[+] Plasmashell reloaded"
}

install_widget() {
	local WIDGET_NAME="$1"
	local SKIP_RELOAD="${2:-false}"
	local WIDGET_DIR="packages/${WIDGET_NAME}"
	local METADATA_FILE="${WIDGET_DIR}/metadata.json"

	echo ""
	echo "================================"
	echo "[*] Processing widget: ${WIDGET_NAME}"
	echo "================================"

	local widgetId=$(jq -r ".KPlugin.Id" "$METADATA_FILE")

	if [[ -d "$HOME/.local/share/plasma/plasmoids/${widgetId}" ]]; then
		echo "[+] Widget already installed. Updating: ${widgetId}"
		kpackagetool6 --type=Plasma/Applet -u "${WIDGET_DIR}"
		local install_result=$?
	else
		echo "[+] Installing widget: ${widgetId}"
		kpackagetool6 --type=Plasma/Applet -i "${WIDGET_DIR}"
		local install_result=$?
	fi

	if [[ $install_result -eq 0 ]]; then
		echo "[+] Widget installed/updated successfully!"
	else
		echo "[!] Installation/update failed"
		return 1
	fi

	if [[ "$SKIP_RELOAD" != "true" ]]; then
		restart_plasmashell
	fi

	return 0
}

print_usage() {
	echo "Usage:"
	echo "  ./install.sh <package_folder>    Install a single widget (works for test-* too)"
	echo "  ./install.sh -a | --all          Install all non-test widgets"
	echo "  ./install.sh -t | --test         Install only test-* widgets"
	echo "  ./install.sh -a -t               Install everything (or: -at)"
}

# Parse flags and positional name
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

	ALL_WIDGETS=($(ls -d packages/*/ 2>/dev/null | xargs -n 1 basename))
	if [[ ${#ALL_WIDGETS[@]} -eq 0 ]]; then
		echo "[!] No widgets found in packages directory"
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
		echo "[!] No matching widgets to install"
		exit 1
	fi

	echo "[+] Installing ${#WIDGETS[@]} widget(s):"
	for widget in "${WIDGETS[@]}"; do
		echo "    - $widget"
	done

	FAILED_WIDGETS=()
	SUCCESSFUL_WIDGETS=()

	for widget in "${WIDGETS[@]}"; do
		if install_widget "$widget" "true"; then
			SUCCESSFUL_WIDGETS+=("$widget")
		else
			FAILED_WIDGETS+=("$widget")
			echo "[!] Failed to install: $widget"
		fi
	done

	echo ""
	echo "================================"
	echo "[*] Installation Summary"
	echo "================================"
	echo "[+] Successfully installed: ${#SUCCESSFUL_WIDGETS[@]}"
	for widget in "${SUCCESSFUL_WIDGETS[@]}"; do
		echo "    ✓ $widget"
	done

	if [[ ${#FAILED_WIDGETS[@]} -gt 0 ]]; then
		echo "[!] Failed to install: ${#FAILED_WIDGETS[@]}"
		for widget in "${FAILED_WIDGETS[@]}"; do
			echo "    ✗ $widget"
		done
	fi

	echo ""
	restart_plasmashell
	echo "[+] All done!"

elif [[ -n "$WIDGET_NAME" && -d "packages/$WIDGET_NAME" ]]; then
	install_widget "$WIDGET_NAME" "false"
	echo "[+] Installation complete!"
else
	if [[ -n "$WIDGET_NAME" ]]; then
		echo "[!] Widget package not found: $WIDGET_NAME"
	else
		echo "[!] No widget specified"
	fi
	echo "[+] Available packages:"
	ls packages
	echo ""
	print_usage
	exit 1
fi
