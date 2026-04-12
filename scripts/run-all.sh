#!/usr/bin/env bash
# Host-side orchestrator - builds and runs compat tests across all distros and architectures.
# Run from the consuming repo root with the shared workflows checkout alongside.
#
# Usage:
#   ./run-all.sh                        # all distros (skips cross-arch if QEMU unavailable)
#   ./run-all.sh arch                   # single distro (x86_64)
#   ./run-all.sh ubuntu-arm64           # specific arch variant
#   ./run-all.sh --no-cache             # force rebuild all
#   ./run-all.sh --setup-qemu           # install QEMU binfmt handlers then run
#   ./run-all.sh --all-arch             # run cross-arch even if QEMU check fails
#   ./run-all.sh --package-group x11-full  # install full dep set (default: x11-base)
#   ./run-all.sh --image-prefix myapp   # docker image name prefix (default: compat)
#
# Environment variables:
#   TEST_COMMANDS       - newline-separated build/test commands (default: "zig build\nzig build test")
#   X11_TEST_COMMANDS   - newline-separated X11 test commands (default: empty)
#   ZIG_VERSION         - zig version to install (default: 0.15.2)
#
# Cross-arch containers (arm64, riscv64) require QEMU binfmt_misc support.
# On Linux: docker run --privileged --rm tonistiigi/binfmt --install all
# Or pass --setup-qemu to do this automatically.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKERFILES_DIR="$(cd "$SCRIPT_DIR/../dockerfiles" && pwd)"

ZIG_VERSION="${ZIG_VERSION:-0.15.2}"
PACKAGE_GROUP="x11-base"
IMAGE_PREFIX="compat"
TEST_COMMANDS="${TEST_COMMANDS:-$(printf 'zig build\nzig build test')}"
X11_TEST_COMMANDS="${X11_TEST_COMMANDS:-}"

# x86_64 (native) distros
DISTROS_AMD64=(arch debian openmandriva ubuntu fedora)

# arm64 distros (require QEMU on x86_64 hosts)
DISTROS_ARM64=(ubuntu-arm64 debian-arm64 arch-arm64 fedora-arm64 openmandriva-arm64)

# riscv64 distros (require QEMU on x86_64 hosts)
DISTROS_RISCV64=(ubuntu-riscv64 debian-riscv64 arch-riscv64 fedora-riscv64)

NO_CACHE=""
FILTER=""
SETUP_QEMU=false
FORCE_ALL_ARCH=false

while [ $# -gt 0 ]; do
    case $1 in
        --no-cache)        NO_CACHE="--no-cache"; shift ;;
        --setup-qemu)      SETUP_QEMU=true; shift ;;
        --all-arch)        FORCE_ALL_ARCH=true; shift ;;
        --package-group)   PACKAGE_GROUP="$2"; shift 2 ;;
        --image-prefix)    IMAGE_PREFIX="$2"; shift 2 ;;
        *)                 FILTER="$1"; shift ;;
    esac
done

# ── QEMU detection ────────────────────────────────────────────────────────────
has_qemu_arm64=false
has_qemu_riscv64=false

check_qemu() {
    docker run --rm --platform "$1" "$2" /bin/true 2>/dev/null
}

if $SETUP_QEMU; then
    echo "--> Installing QEMU binfmt handlers..."
    docker run --privileged --rm tonistiigi/binfmt --install all
fi

if check_qemu linux/arm64 arm64v8/ubuntu:24.04 2>/dev/null; then
    has_qemu_arm64=true
fi
if check_qemu linux/riscv64 riscv64/ubuntu:latest 2>/dev/null; then
    has_qemu_riscv64=true
fi

if $FORCE_ALL_ARCH; then
    has_qemu_arm64=true
    has_qemu_riscv64=true
fi

# ── Distro selection ──────────────────────────────────────────────────────────
if [ -n "$FILTER" ]; then
    DISTROS=("$FILTER")
else
    DISTROS=("${DISTROS_AMD64[@]}")

    if $has_qemu_arm64; then
        DISTROS+=("${DISTROS_ARM64[@]}")
    else
        echo ""
        echo "  NOTE: arm64 containers skipped (QEMU not available)."
        echo "        Run with --setup-qemu to install QEMU binfmt handlers,"
        echo "        or pass --all-arch to force (expect exec format errors)."
    fi

    if $has_qemu_riscv64; then
        DISTROS+=("${DISTROS_RISCV64[@]}")
    else
        echo ""
        echo "  NOTE: riscv64 containers skipped (QEMU not available)."
    fi
fi

# ── Platform mapping ──────────────────────────────────────────────────────────
get_platform() {
    case "$1" in
        *-arm64)   echo "linux/arm64" ;;
        *-riscv64) echo "linux/riscv64" ;;
        *)         echo "linux/amd64" ;;
    esac
}

# ── Run ───────────────────────────────────────────────────────────────────────
PASS=()
FAIL=()

for distro in "${DISTROS[@]}"; do
    IMAGE="${IMAGE_PREFIX}-${distro}"
    DOCKERFILE="$DOCKERFILES_DIR/Dockerfile.${distro}"
    PLATFORM=$(get_platform "$distro")

    if [ ! -f "$DOCKERFILE" ]; then
        echo "ERROR: $DOCKERFILE not found"
        exit 1
    fi

    echo ""
    echo "======================================================"
    echo "  Distro: $distro  [${PLATFORM}]"
    echo "======================================================"

    echo "--> Building image $IMAGE..."
    if ! docker build \
        $NO_CACHE \
        --platform "$PLATFORM" \
        --build-arg ZIG_VERSION="$ZIG_VERSION" \
        --build-arg PACKAGE_GROUP="$PACKAGE_GROUP" \
        -f "$DOCKERFILE" \
        -t "$IMAGE" \
        .; then
        FAIL+=("$distro")
        echo "--> BUILD FAILED: $distro"
        continue
    fi

    echo "--> Running tests..."
    if docker run --rm \
        --platform "$PLATFORM" \
        -e TEST_COMMANDS="$TEST_COMMANDS" \
        -e X11_TEST_COMMANDS="$X11_TEST_COMMANDS" \
        --name "${IMAGE_PREFIX}-${distro}-$$" \
        "$IMAGE"; then
        PASS+=("$distro")
        echo "--> PASS: $distro"
    else
        FAIL+=("$distro")
        echo "--> FAIL: $distro"
    fi
done

echo ""
echo "======================================================"
echo "  Results"
echo "======================================================"
for d in "${PASS[@]:-}";  do [ -n "$d" ] && echo "  PASS  $d"; done
for d in "${FAIL[@]:-}";  do [ -n "$d" ] && echo "  FAIL  $d"; done
echo ""

if [ ${#FAIL[@]} -gt 0 ]; then
    exit 1
fi
