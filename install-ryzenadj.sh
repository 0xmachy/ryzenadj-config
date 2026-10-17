#!/usr/bin/env bash
#
# Script instalasi RyzenAdj v0.16.0 + script performance
# Mengkompilasi dari source FlyGoat/RyzenAdj dan memasang script performance
# dari 0xmachy/ryzenadj-config (atau file 'performance' lokal kalau ada)
#
# Usage: sudo ./install-ryzenadj.sh
#

set -euo pipefail

# Konstanta
RYZENADJ_VERSION="0.16.0"
RYZENADJ_REPO="https://github.com/FlyGoat/RyzenAdj.git"
SCRIPT_REPO="https://github.com/0xmachy/ryzenadj-config.git"
BUILD_DIR="/tmp/ryzenadj-build-${RYZENADJ_VERSION}"
SCRIPT_INSTALL_PATH="/usr/local/bin/performance"

# Warna output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Cek root
if [[ "$EUID" -ne 0 ]]; then
    error "Script ini harus dijalankan sebagai root (sudo)."
    exit 1
fi

# Deteksi distro
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "${ID}"
    elif command -v lsb_release &> /dev/null; then
        lsb_release -is | tr '[:upper:]' '[:lower:]'
    else
        echo "unknown"
    fi
}

DISTRO=$(detect_distro)
log "Detected distribution: ${DISTRO}"

# Install dependencies
install_dependencies() {
    log "Installing build dependencies..."
    
    case "${DISTRO}" in
        ubuntu|debian|linuxmint|pop)
            apt update
            apt install -y build-essential cmake git libpci-dev
            ;;
        fedora|rhel|centos|rocky|almalinux)
            dnf install -y cmake gcc-c++ git pciutils-devel
            ;;
        arch|manjaro|endeavouros)
            pacman -Sy --noconfirm base-devel pciutils cmake git
            ;;
        opensuse*|suse|tumbleweed)
            zypper install -y cmake gcc-c++ git pciutils-devel
            ;;
        *)
            warn "Distro tidak dikenali. Pastikan sudah terinstall: build-essential, cmake, git, libpci-dev (atau equivalennya)"
            read -p "Lanjutkan? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
            ;;
    esac
}

# Build ryzenadj dari source
build_ryzenadj() {
    log "Cloning RyzenAdj v${RYZENADJ_VERSION}..."
    
    rm -rf "${BUILD_DIR}"
    git clone --depth 1 --branch "v${RYZENADJ_VERSION}" "${RYZENADJ_REPO}" "${BUILD_DIR}"
    
    cd "${BUILD_DIR}"
    
    log "Building RyzenAdj..."
    rm -rf win32  # Hapus Windows-specific files
    mkdir -p build
    cd build
    
    cmake -DCMAKE_BUILD_TYPE=Release ..
    make -j"$(nproc)"
    
    log "Installing ryzenadj to /usr/local/bin..."
    cp ryzenadj /usr/local/bin/ryzenadj
    chmod 755 /usr/local/bin/ryzenadj
    
    # Verifikasi
    if command -v ryzenadj &> /dev/null; then
        log "RyzenAdj berhasil terinstall!"
        ryzenadj --help | head -5
    else
        error "Instalasi ryzenadj gagal!"
        exit 1
    fi
}

# Pasang script performance: pakai file lokal kalau ada (sepaket/zip),
# kalau tidak clone dari repo
install_performance_script() {
    local script_dir src_script temp_dir=""
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [[ -f "${script_dir}/performance" ]]; then
        log "Memakai script performance lokal: ${script_dir}/performance"
        src_script="${script_dir}/performance"
    else
        log "Downloading script performance from ${SCRIPT_REPO}..."
        temp_dir="/tmp/ryzenadj-script-$$"
        rm -rf "${temp_dir}"
        git clone --depth 1 "${SCRIPT_REPO}" "${temp_dir}"
        src_script="${temp_dir}/performance"
    fi

    log "Installing performance script to ${SCRIPT_INSTALL_PATH}..."
    cp "${src_script}" "${SCRIPT_INSTALL_PATH}"
    chmod 755 "${SCRIPT_INSTALL_PATH}"

    if [[ -n "${temp_dir}" ]]; then
        rm -rf "${temp_dir}"
    fi

    if [[ -x "${SCRIPT_INSTALL_PATH}" ]]; then
        log "Script performance berhasil dipasang di ${SCRIPT_INSTALL_PATH}"
    else
        error "Gagal memasang script performance!"
        exit 1
    fi
}

# Cleanup build directory
cleanup() {
    log "Cleaning up build directory..."
    rm -rf "${BUILD_DIR}"
}

# Main
main() {
    echo "========================================"
    echo "  RyzenAdj v${RYZENADJ_VERSION} Installer"
    echo "  + Performance Script Installer"
    echo "========================================"
    echo
    
    install_dependencies
    echo
    build_ryzenadj
    echo
    install_performance_script
    echo
    cleanup
    echo
    echo "========================================"
    log "Instalasi selesai!"
    echo "========================================"
    echo
    echo "Binaries:"
    echo "  - ryzenadj          : /usr/local/bin/ryzenadj"
    echo "  - performance script: ${SCRIPT_INSTALL_PATH}"
    echo
    echo "Usage:"
    echo "  sudo ryzenadj --info"
    echo "  sudo ${SCRIPT_INSTALL_PATH##*/}"
    echo
}

main "$@"
