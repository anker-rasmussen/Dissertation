#!/bin/bash
# =============================================================================
# MP-SPDZ Setup Script (Standalone)
# =============================================================================
# Idempotent script that prepares MP-SPDZ for sealed-bid auction use.
# Works on any host — each step is skipped if artifacts already exist.
#
# Usage:
#   ./setup-mpspdz.sh [--max-parties N] [--mp-spdz-dir PATH]
#
# Environment:
#   MP_SPDZ_DIR   Override the MP-SPDZ directory (same as --mp-spdz-dir)
#
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ── Defaults ──────────────────────────────────────────────────────────────────
MAX_PARTIES=10
MP_SPDZ_DIR="${MP_SPDZ_DIR:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --max-parties)
            MAX_PARTIES="$2"; shift 2 ;;
        --mp-spdz-dir)
            MP_SPDZ_DIR="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--max-parties N] [--mp-spdz-dir PATH]"
            echo ""
            echo "Prepares MP-SPDZ for sealed-bid auction use (idempotent)."
            echo ""
            echo "Options:"
            echo "  --max-parties N       Max parties for SSL certs (default: 10)"
            echo "  --mp-spdz-dir PATH    Path to MP-SPDZ directory"
            echo "  -h, --help            Show this help"
            echo ""
            echo "Environment:"
            echo "  MP_SPDZ_DIR           Same as --mp-spdz-dir"
            exit 0 ;;
        *)
            log_error "Unknown option: $1"
            exit 1 ;;
    esac
done

# ── Validate --max-parties ──────────────────────────────────────────────────
if ! [[ "$MAX_PARTIES" =~ ^[0-9]+$ ]] || [ "$MAX_PARTIES" -lt 3 ]; then
    log_error "--max-parties must be an integer >= 3 (got: $MAX_PARTIES)"
    exit 1
fi

# ── Resolve MP-SPDZ directory ────────────────────────────────────────────────
if [ -z "$MP_SPDZ_DIR" ]; then
    # Auto-detect: look for Repos/MP-SPDZ relative to this script
    if [ -d "$SCRIPT_DIR/Repos/MP-SPDZ" ]; then
        MP_SPDZ_DIR="$SCRIPT_DIR/Repos/MP-SPDZ"
    elif [ -d "$SCRIPT_DIR/MP-SPDZ" ]; then
        MP_SPDZ_DIR="$SCRIPT_DIR/MP-SPDZ"
    else
        log_error "Cannot find MP-SPDZ directory. Use --mp-spdz-dir or set MP_SPDZ_DIR."
        exit 1
    fi
fi

if [ ! -d "$MP_SPDZ_DIR" ]; then
    log_error "MP-SPDZ directory does not exist: $MP_SPDZ_DIR"
    exit 1
fi

MP_SPDZ_DIR="$(cd "$MP_SPDZ_DIR" && pwd)"  # Normalize to absolute path
log_info "MP-SPDZ directory: $MP_SPDZ_DIR"

# ── 1. Check prerequisites ───────────────────────────────────────────────────
log_info "Checking prerequisites..."

MISSING=()
command -v make    >/dev/null 2>&1 || MISSING+=("make")
command -v python3 >/dev/null 2>&1 || MISSING+=("python3")
if ! command -v g++ >/dev/null 2>&1 && ! command -v clang++ >/dev/null 2>&1; then
    MISSING+=("g++ or clang++")
fi

if [ ${#MISSING[@]} -gt 0 ]; then
    log_error "Missing prerequisites: ${MISSING[*]}"
    log_error "Please install them and re-run."
    exit 1
fi
log_success "Prerequisites OK (make, python3, C++ compiler)"

# ── 2. Build shamir-party.x ──────────────────────────────────────────────────
if [ -f "$MP_SPDZ_DIR/shamir-party.x" ]; then
    log_success "shamir-party.x already built"
else
    log_info "Building shamir-party.x (this may take a while)..."
    NPROC="${NPROC:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)}"
    make -C "$MP_SPDZ_DIR" -j"$NPROC" shamir-party.x
    log_success "shamir-party.x built"
fi

# ── 3. Ensure Player-Data directory ──────────────────────────────────────────
mkdir -p "$MP_SPDZ_DIR/Player-Data"
log_success "Player-Data/ directory exists"

# ── 4. Generate SSL certificates ─────────────────────────────────────────────
LAST_CERT="$MP_SPDZ_DIR/Player-Data/P$((MAX_PARTIES - 1)).pem"
if [ -f "$MP_SPDZ_DIR/Player-Data/P0.pem" ] && [ -f "$LAST_CERT" ]; then
    log_success "SSL certificates already exist (P0..P$((MAX_PARTIES - 1)))"
else
    log_info "Generating SSL certificates for $MAX_PARTIES parties..."
    cd "$MP_SPDZ_DIR"
    ./Scripts/setup-ssl.sh "$MAX_PARTIES"
    log_success "SSL certificates generated"
fi

# ── 5. Pre-compile auction_n for 3 parties ───────────────────────────────────
SCHEDULE_FILE="$MP_SPDZ_DIR/Programs/Schedules/auction_n-3.sch"
if [ -f "$SCHEDULE_FILE" ]; then
    log_success "auction_n-3 already compiled"
else
    log_info "Compiling auction_n for 3 parties..."
    cd "$MP_SPDZ_DIR"
    ./compile.py auction_n -- 3
    log_success "auction_n-3 compiled"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}  MP-SPDZ Setup Complete${NC}"
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo ""
echo "  Directory:    $MP_SPDZ_DIR"
echo "  Binary:       $([ -f "$MP_SPDZ_DIR/shamir-party.x" ] && echo "OK" || echo "MISSING")"
echo "  SSL certs:    $([ -f "$MP_SPDZ_DIR/Player-Data/P0.pem" ] && echo "OK" || echo "MISSING")"
echo "  auction_n-3:  $([ -f "$SCHEDULE_FILE" ] && echo "OK" || echo "MISSING")"
echo ""
