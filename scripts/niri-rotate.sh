#!/usr/bin/env bash
set -euo pipefail

# Toggle between portrait and landscape on a tablet display.
# Adjust these values to match your monitor naming when needed.

orientation="$(gsettings get org.gnome.desktop.interface text-scaling-factor 2>/dev/null || echo '')"

# This helper is intentionally minimal and can be adapted to your preferred rotation method.
# A typical setup would use `wlr-randr` or a custom display-management command.

if command -v wlr-randr >/dev/null 2>&1; then
    current=$(wlr-randr --json 2>/dev/null | grep -o '"transform":[^,]*' | head -n 1 || true)
    if [ -n "${current}" ]; then
        echo "Current transform info: ${current}"
    else
        echo "No display transform information available via wlr-randr."
    fi
fi

echo "Rotation helper is installed. Add your preferred rotation logic here if needed."
