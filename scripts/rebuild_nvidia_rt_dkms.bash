#!/bin/bash

set -euo pipefail

show_help() {
    cat <<'EOF'
Usage: sudo ./scripts/rebuild_nvidia_rt_dkms.bash [NVIDIA_VERSION] [KERNEL_VERSION]

Rebuild and install the NVIDIA DKMS modules for a PREEMPT_RT kernel by
injecting IGNORE_PREEMPT_RT_PRESENCE=1 into the driver's dkms.conf.

Arguments:
  NVIDIA_VERSION   Optional. Example: 570.211.01
  KERNEL_VERSION   Optional. Defaults to the running kernel from uname -r

Examples:
  sudo ./scripts/rebuild_nvidia_rt_dkms.bash
  sudo ./scripts/rebuild_nvidia_rt_dkms.bash 570.211.01
  sudo ./scripts/rebuild_nvidia_rt_dkms.bash 570.211.01 6.8.1-1015-realtime
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_help
    exit 0
fi

if [[ "${EUID}" -ne 0 ]]; then
    echo "Error: please run this script with sudo."
    exit 1
fi

detect_nvidia_version() {
    local version
    version="$(dkms status | sed -n 's/^nvidia\/\([^,]*\),.*/\1/p' | head -n1)"
    if [[ -z "${version}" ]]; then
        echo "Error: could not detect an installed NVIDIA DKMS version." >&2
        exit 1
    fi
    printf '%s\n' "${version}"
}

NVIDIA_VERSION="${1:-$(detect_nvidia_version)}"
KERNEL_VERSION="${2:-$(uname -r)}"
SOURCE_DIR="/usr/src/nvidia-${NVIDIA_VERSION}"
DKMS_CONF="${SOURCE_DIR}/dkms.conf"
BACKUP_CONF="${SOURCE_DIR}/dkms.conf.bak-preempt-rt-override"

if [[ ! -d "${SOURCE_DIR}" ]]; then
    echo "Error: NVIDIA source directory not found: ${SOURCE_DIR}"
    exit 1
fi

if [[ ! -f "${DKMS_CONF}" ]]; then
    echo "Error: dkms.conf not found: ${DKMS_CONF}"
    exit 1
fi

if [[ ! -d "/lib/modules/${KERNEL_VERSION}/build" ]]; then
    echo "Error: kernel build directory not found for ${KERNEL_VERSION}"
    exit 1
fi

echo "NVIDIA version: ${NVIDIA_VERSION}"
echo "Kernel version: ${KERNEL_VERSION}"
echo "Source dir:     ${SOURCE_DIR}"

if [[ ! -f "${BACKUP_CONF}" ]]; then
    cp "${DKMS_CONF}" "${BACKUP_CONF}"
fi

if ! grep -q 'IGNORE_PREEMPT_RT_PRESENCE=1' "${DKMS_CONF}"; then
    sed -i \
        's/IGNORE_CC_MISMATCH=1 /IGNORE_CC_MISMATCH=1 IGNORE_PREEMPT_RT_PRESENCE=1 /' \
        "${DKMS_CONF}"
fi

echo "Patched dkms.conf with IGNORE_PREEMPT_RT_PRESENCE=1"

rm -f /var/crash/nvidia-kernel-source-*.crash

echo "Running dkms build..."
dkms build --force -m nvidia -v "${NVIDIA_VERSION}" -k "${KERNEL_VERSION}"

echo "Running dkms install..."
dkms install --force -m nvidia -v "${NVIDIA_VERSION}" -k "${KERNEL_VERSION}"

echo "DKMS status:"
dkms status "nvidia/${NVIDIA_VERSION}"

if [[ "${KERNEL_VERSION}" == "$(uname -r)" ]]; then
    echo "Loading NVIDIA kernel modules into the running kernel..."
    modprobe nvidia
    modprobe nvidia_uvm
    modprobe nvidia_modeset
    modprobe nvidia_drm

    echo "Verifying with nvidia-smi..."
    nvidia-smi
else
    echo "Target kernel is not the running kernel; skipping modprobe and nvidia-smi."
fi

