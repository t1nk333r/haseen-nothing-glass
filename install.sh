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

if [[ "$1" == "--all" || "$1" == "-a" ]]; then
	echo "[*] Installing all widgets..."

	WIDGETS=($(ls -d packages/*/ 2>/dev/null | xargs -n 1 basename))

	if [[ ${#WIDGETS[@]} -eq 0 ]]; then
		echo "[!] No widgets found in packages directory"
		exit 1
	fi

	echo "[+] Found ${#WIDGETS[@]} widgets to install"

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

elif [[ -n "$1" && -d "packages/$1" ]]; then
	install_widget "$1" "false"
	echo "[+] Installation complete!"
else
	if [[ -n "$1" ]]; then
		echo "[!] Widget package not found: $1"
	else
		echo "[!] No widget specified"
	fi
	echo "[+] Available packages:"
	ls packages
	echo ""
	echo "Usage:"
	echo "  ./install.sh <package_folder>    Install a single widget"
	echo "  ./install.sh --all | -a          Install all widgets"
	exit 1
fi
