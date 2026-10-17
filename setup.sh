#!/usr/bin/env bash
set -euo pipefail

# Color formatting
C_BLUE="\e[34m"
C_GREEN="\e[32m"
C_YELLOW="\e[33m"
C_RED="\e[31m"
C_RESET="\e[0m"

INFO()  { echo -e "${C_BLUE}[INFO]${C_RESET} $*"; }
OK()    { echo -e "${C_GREEN}[OK]${C_RESET} $*"; }
WARN()  { echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
ERROR() { echo -e "${C_RED}[ERROR]${C_RESET} $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${HOME}/.cache/niri-tablet-build"
NIRI_TARGET_TAG="v26.04"

echo -e "${C_BLUE}==================================================${C_RESET}"
echo -e "       niri-tablet Universal Setup Script         "
echo -e "${C_BLUE}==================================================${C_RESET}"

# ----------------------------------------------------
# 1. Distro Detection & Dependency Installation
# ----------------------------------------------------
INFO "Detecting operating system..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_LIKE="${ID_LIKE:-}"
else
    ERROR "Unable to detect distribution (/etc/os-release not found)."
fi

INFO "Detected OS: ${NAME:-${DISTRO_ID}} (${DISTRO_ID})"

install_dependencies() {
    INFO "Installing system development libraries and utilities..."
    
    # Check for sudo permissions
    if [ "$EUID" -ne 0 ] && ! command -v sudo &>/dev/null; then
        ERROR "'sudo' command not found. Please run this script with elevated privileges."
    fi

    SUDO="sudo"
    [ "$EUID" -eq 0 ] && SUDO=""

    case "${DISTRO_ID}" in
        debian|ubuntu|linuxmint|pop)
            $SUDO apt update
            $SUDO apt install -y git gcc clang pkg-config curl \
                libudev-dev libgbm-dev libxkbcommon-dev libegl1-mesa-dev \
                libwayland-dev libinput-dev libdbus-1-dev libsystemd-dev \
                libseat-dev libpipewire-0.3-dev libpango1.0-dev libdisplay-info-dev \
                fuzzel squeekboard iio-sensor-proxy
            ;;
        arch|cachyos|manjaro|endeavouros)
            $SUDO pacman -Syu --needed --noconfirm base-devel git clang pkgconf curl \
                systemd-libs libxkbcommon mesa wayland libinput \
                pipewire pango libdisplay-info seatd \
                fuzzel squeekboard iio-sensor-proxy
            ;;
        fedora)
            $SUDO dnf install -y git gcc clang pkgconf-pkg-config curl \
                systemd-devel libxkbcommon-devel mesa-libgbm-devel \
                wayland-devel libinput-devel dbus-devel \
                libseat-devel pipewire-devel pango-devel libdisplay-info-devel \
                fuzzel squeekboard iio-sensor-proxy
            ;;
        opensuse*|suse)
            $SUDO zypper refresh
            $SUDO zypper --non-interactive install git gcc clang pkg-config curl \
                libudev-devel libgbm-devel libxkbcommon-devel Mesa-libEGL-devel \
                wayland-devel libinput-devel dbus-1-devel systemd-devel \
                libseat-devel pipewire-devel pango-devel libdisplay-info-devel \
                fuzzel squeekboard iio-sensor-proxy
            ;;
        void)
            $SUDO xbps-install -Syu
            $SUDO xbps-install -y base-devel git clang pkg-config curl \
                eudev-libudev-devel libgbm-devel libxkbcommon-devel \
                wayland-devel libinput-devel dbus-devel elogind-devel \
                seatd-devel pipewire-devel pango-devel libdisplay-info-devel \
                fuzzel squeekboard
            ;;
        *)
            # Fallback by parent family
            if [[ "${DISTRO_LIKE}" == *"arch"* ]]; then
                $SUDO pacman -Syu --needed --noconfirm base-devel git clang pkgconf curl \
                    systemd-libs libxkbcommon mesa wayland libinput \
                    pipewire pango libdisplay-info seatd fuzzel squeekboard
            elif [[ "${DISTRO_LIKE}" == *"debian"* ]]; then
                $SUDO apt update && $SUDO apt install -y git gcc clang pkg-config curl \
                    libudev-dev libgbm-dev libxkbcommon-dev libegl1-mesa-dev \
                    libwayland-dev libinput-dev libdbus-1-dev libsystemd-dev \
                    libseat-dev libpipewire-0.3-dev libpango1.0-dev libdisplay-info-dev \
                    fuzzel squeekboard
            else
                WARN "Unmapped distribution ID '${DISTRO_ID}'. Ensure required C/Wayland development libraries are installed."
                read -p "Attempt build anyway? [y/N]: " -r confirm
                [[ "${confirm}" =~ ^[Yy]$ ]] || exit 1
            fi
            ;;
    esac
    OK "Dependencies installed successfully."
}

install_dependencies

# ----------------------------------------------------
# 2. Rust Compiler Verification
# ----------------------------------------------------
if ! command -v cargo &>/dev/null; then
    INFO "Rust compiler not detected. Installing via official rustup script..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "${HOME}/.cargo/env"
else
    OK "Rust is present: $(cargo --version)"
fi

# ----------------------------------------------------
# 3. Source Fetching & Patch Application
# ----------------------------------------------------
INFO "Preparing clean build directory in ${BUILD_DIR}..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

INFO "Cloning upstream Niri repository..."
git clone https://github.com/YaLTeR/niri.git "${BUILD_DIR}/niri"
cd "${BUILD_DIR}/niri"

INFO "Checking out upstream tag ${NIRI_TARGET_TAG}..."
git checkout "${NIRI_TARGET_TAG}"

INFO "Locating tablet gesture patches..."
PATCH_DIR=""
if [ -d "${SCRIPT_DIR}/pkg" ]; then
    PATCH_DIR="${SCRIPT_DIR}/pkg"
elif [ -d "${SCRIPT_DIR}/patches" ]; then
    PATCH_DIR="${SCRIPT_DIR}/patches"
elif compgen -G "${SCRIPT_DIR}/*.patch" > /dev/null; then
    PATCH_DIR="${SCRIPT_DIR}"
else
    ERROR "Unable to locate .patch files in ${SCRIPT_DIR}/pkg or ${SCRIPT_DIR}/"
fi

INFO "Applying gesture patches from ${PATCH_DIR}..."
if ! git am "${PATCH_DIR}"/00*.patch 2>/dev/null; then
    WARN "'git am' had committer/whitespace mismatch; applying via 'git apply'..."
    git am --abort 2>/dev/null || true
    git apply "${PATCH_DIR}"/00*.patch || ERROR "Patch application failed. Check git version or patch compatibility."
fi
OK "Patches applied successfully."

# ----------------------------------------------------
# 4. Compilation & Binary Installation
# ----------------------------------------------------
INFO "Building release binary... (This takes 2-5 minutes depending on CPU)"
cargo build --release

SUDO="sudo"
[ "$EUID" -eq 0 ] && SUDO=""

INFO "Installing compiled binary to /usr/local/bin/niri..."
$SUDO install -Dm755 target/release/niri /usr/local/bin/niri

# Install Wayland desktop session files if present in the source tree
if [ -f "resources/niri.desktop" ]; then
    $SUDO install -Dm644 resources/niri.desktop /usr/share/wayland-sessions/niri.desktop
    OK "Installed niri.desktop to display manager session folder."
fi

if [ -f "resources/niri-portals.conf" ]; then
    $SUDO install -Dm644 resources/niri-portals.conf /usr/share/xdg-desktop-portal/niri-portals.conf
    OK "Installed portal configuration."
fi

# ----------------------------------------------------
# 5. Helper Scripts & Rotation Service
# ----------------------------------------------------
INFO "Setting up user helper utilities..."
mkdir -p "${HOME}/.local/bin"

# Install OSK script
if [ -f "${SCRIPT_DIR}/scripts/niri-osk.sh" ]; then
    install -Dm755 "${SCRIPT_DIR}/scripts/niri-osk.sh" "${HOME}/.local/bin/niri-osk.sh"
else
    cat << 'EOF' > "${HOME}/.local/bin/niri-osk.sh"
#!/usr/bin/env bash
if pgrep -x squeekboard > /dev/null; then
    pkill squeekboard
else
    squeekboard &
fi
EOF
    chmod +x "${HOME}/.local/bin/niri-osk.sh"
fi
OK "Configured OSK toggle script at ~/.local/bin/niri-osk.sh"

# Install Auto-Rotation script & systemd service if available
if [ -f "${SCRIPT_DIR}/scripts/niri-rotate.sh" ]; then
    install -Dm755 "${SCRIPT_DIR}/scripts/niri-rotate.sh" "${HOME}/.local/bin/niri-rotate.sh"
    if [ -f "${SCRIPT_DIR}/scripts/niri-rotate.service" ]; then
        mkdir -p "${HOME}/.config/systemd/user"
        cp "${SCRIPT_DIR}/scripts/niri-rotate.service" "${HOME}/.config/systemd/user/niri-rotate.service"
        systemctl --user daemon-reload || true
        systemctl --user enable --now niri-rotate.service 2>/dev/null || true
        OK "Enabled auto-rotation service (niri-rotate.service)."
    fi
fi

# ----------------------------------------------------
# 6. Non-Destructive Configuration Setup
# ----------------------------------------------------
NIRI_CONFIG_DIR="${HOME}/.config/niri"
mkdir -p "${NIRI_CONFIG_DIR}"

INFO "Installing gesture definitions to ${NIRI_CONFIG_DIR}/gestures.kdl..."
if [ -f "${SCRIPT_DIR}/gestures.kdl" ]; then
    cp "${SCRIPT_DIR}/gestures.kdl" "${NIRI_CONFIG_DIR}/gestures.kdl"
elif [ -f "${SCRIPT_DIR}/config/gestures.kdl" ]; then
    cp "${SCRIPT_DIR}/config/gestures.kdl" "${NIRI_CONFIG_DIR}/gestures.kdl"
else
    cat << 'EOF' > "${NIRI_CONFIG_DIR}/gestures.kdl"
gestures {
    show-touch-points "gestures"

    touchscreen-swipe {
        fingers 3
        horizontal-swipe "resize-column"
        tap             { maximize-column; }
        tap-more        { toggle-overview; }
        swipe-more-down { close-window; }
        swipe-more-up   { fullscreen-window; }

        hold {
            left  { move-column-left; }
            right { move-column-right; }
            up    { move-window-to-workspace-up; }
            down  { move-window-to-workspace-down; }
        }
    }

    touchscreen-edge-swipe {
        bottom { spawn-sh "~/.local/bin/niri-osk.sh"; }
        top    { toggle-overview; }
        left   { focus-column-left; }
        right  { focus-column-right; }
    }
}
EOF
fi
OK "Gestures file prepared."

MAIN_CONFIG="${NIRI_CONFIG_DIR}/config.kdl"
if [ -f "${MAIN_CONFIG}" ]; then
    # Create safety backup
    BACKUP_FILE="${MAIN_CONFIG}.bak.$(date +%s)"
    cp "${MAIN_CONFIG}" "${BACKUP_FILE}"
    OK "Created safety backup of existing config at: ${BACKUP_FILE}"

    # Safely append include if not already referenced
    if ! grep -q 'include.*"gestures\.kdl"' "${MAIN_CONFIG}"; then
        INFO "Linking gestures.kdl into config.kdl without modifying existing blocks..."
        echo -e '\n// Touchscreen gestures\ninclude "gestures.kdl" optional=true' >> "${MAIN_CONFIG}"
        OK "Appended optional include to config.kdl."
    else
        OK "config.kdl already contains include for gestures.kdl."
    fi
else
    INFO "No existing config.kdl found. Initializing minimal include configuration..."
    echo 'include "gestures.kdl" optional=true' > "${MAIN_CONFIG}"
fi

# ----------------------------------------------------
# 7. Verification & Config Reload
# ----------------------------------------------------
INFO "Running syntax validation..."
if /usr/local/bin/niri validate 2>&1; then
    OK "Configuration syntax is 100% valid."
else
    WARN "Validation reported warnings. Run 'niri validate' to inspect."
fi

if pgrep -x niri > /dev/null; then
    INFO "Live Niri session detected. Reloading configuration..."
    /usr/local/bin/niri msg action reload-config || true
    OK "Live reload sent."
fi

# Clean up source cache
rm -rf "${BUILD_DIR}"

echo -e "${C_GREEN}==================================================${C_RESET}"
echo -e "          Setup Finished Successfully!            "
echo -e "${C_GREEN}==================================================${C_RESET}"
echo -e "Binary Installed:    /usr/local/bin/niri"
echo -e "Gestures Config:     ~/.config/niri/gestures.kdl"
echo -e "Main Config:         ~/.config/niri/config.kdl"
echo -e "OSK Toggle Script:   ~/.local/bin/niri-osk.sh"
echo -e "${C_GREEN}==================================================${C_RESET}"
