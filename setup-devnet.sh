#!/bin/bash
# =============================================================================
# Dissertation Demo Setup Script
# =============================================================================
# Sets up and runs a complete 3-node sealed-bid auction demo with:
# - Veilid devnet (1 bootstrap + 4 nodes via Docker)
# - MP-SPDZ (compiled with SSL certs)
# - Market app cluster (3 nodes)
#
# Usage:
#   ./setup-devnet.sh           # Full setup and run
#   ./setup-devnet.sh --build   # Build only, don't start
#   ./setup-devnet.sh --clean   # Clean up old data and volumes
#   ./setup-devnet.sh --stop    # Stop everything
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS_DIR="$SCRIPT_DIR/Repos"
VEILID_DIR="$REPOS_DIR/veilid"
MP_SPDZ_DIR="$REPOS_DIR/MP-SPDZ"
MARKET_DIR="$REPOS_DIR/dissertationapp/market"
IPSPOOF_SRC="$VEILID_DIR/.devcontainer/scripts/ip_spoof.c"
IPSPOOF_SO="$VEILID_DIR/.devcontainer/scripts/libipspoof.so"
COMPOSE_FILE="$VEILID_DIR/.devcontainer/compose/docker-compose.dev.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

header() {
    echo ""
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}  $1${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo ""
}

# =============================================================================
# Cleanup Functions
# =============================================================================

cleanup_data() {
    header "Cleaning Up Old Data"

    log_info "Removing old market node data..."
    rm -rf ~/.local/share/smpc-auction-node-*

    log_info "Removing old veilid docker volumes..."
    docker volume ls | grep veilid | awk '{print $2}' | xargs -r docker volume rm 2>/dev/null || true

    log_success "Cleanup complete"
}

stop_all() {
    header "Stopping All Services"

    log_info "Stopping docker containers..."
    cd "$VEILID_DIR/.devcontainer/compose"
    docker compose -f docker-compose.dev.yml down 2>/dev/null || true

    log_info "Killing any running market nodes..."
    pkill -f "target/debug/market" 2>/dev/null || true
    pkill -f "target/release/market" 2>/dev/null || true

    log_success "All services stopped"
}

# =============================================================================
# Build Functions
# =============================================================================

build_ipspoof() {
    header "Building IP Spoof Library"

    if [ -f "$IPSPOOF_SO" ] && [ "$IPSPOOF_SO" -nt "$IPSPOOF_SRC" ]; then
        log_success "libipspoof.so already up to date"
        return 0
    fi

    log_info "Compiling ip_spoof.c..."
    gcc -shared -fPIC -o "$IPSPOOF_SO" "$IPSPOOF_SRC" -ldl

    if [ -f "$IPSPOOF_SO" ]; then
        log_success "libipspoof.so compiled successfully"
    else
        log_error "Failed to compile libipspoof.so"
        exit 1
    fi
}

build_mpspdz() {
    header "Building MP-SPDZ"

    cd "$MP_SPDZ_DIR"

    # Check if already built
    if [ -f "replicated-ring-party.x" ]; then
        log_success "MP-SPDZ already built (replicated-ring-party.x exists)"
    else
        log_info "Building MP-SPDZ (this may take a while)..."
        make -j$(nproc) replicated-ring-party.x
        log_success "MP-SPDZ built successfully"
    fi

    # Setup SSL certificates for 3 parties
    if [ -f "Player-Data/P0.pem" ] && [ -f "Player-Data/P1.pem" ] && [ -f "Player-Data/P2.pem" ]; then
        log_success "SSL certificates already exist for 3 parties"
    else
        log_info "Generating SSL certificates for 3 parties..."
        ./Scripts/setup-ssl.sh 3
        log_success "SSL certificates generated"
    fi

    # Compile auction program for 3 parties
    log_info "Compiling auction_n program for 3 parties..."
    ./compile.py -R 64 auction_n -- 3
    log_success "auction_n-3 compiled"
}

build_market() {
    header "Building Market App"

    cd "$MARKET_DIR"

    log_info "Building market app (release mode)..."
    cargo build --release

    log_success "Market app built successfully"
}

# =============================================================================
# Run Functions
# =============================================================================

start_devnet() {
    header "Starting Veilid Devnet"

    cd "$VEILID_DIR/.devcontainer/compose"

    # Check if already running
    if docker compose -f docker-compose.dev.yml ps --quiet 2>/dev/null | grep -q .; then
        log_warn "Devnet already running"
        return 0
    fi

    log_info "Starting veilid devnet (1 bootstrap + 4 nodes)..."
    docker compose -f docker-compose.dev.yml up -d

    log_info "Waiting for bootstrap to be healthy..."
    local retries=0
    local max_retries=30

    while [ $retries -lt $max_retries ]; do
        if docker compose -f docker-compose.dev.yml ps | grep -q "healthy"; then
            log_success "Veilid devnet is healthy"
            return 0
        fi
        retries=$((retries + 1))
        echo -n "."
        sleep 2
    done

    log_warn "Devnet may not be fully healthy yet, but continuing..."
}

start_market_cluster() {
    header "Starting Market App Cluster"

    cd "$MARKET_DIR"

    echo "  Node 5 -> port 5165, IP 1.2.3.6 (Bidder 1)"
    echo "  Node 6 -> port 5166, IP 1.2.3.7 (Bidder 2)"
    echo "  Node 7 -> port 5167, IP 1.2.3.8 (Auctioneer)"
    echo ""

    # Array to track child PIDs
    PIDS=()

    # Cleanup function
    cleanup() {
        echo ""
        log_info "Shutting down cluster..."
        for pid in "${PIDS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null
            fi
        done
        wait 2>/dev/null
        log_success "Cluster stopped"
    }
    trap cleanup EXIT INT TERM

    # Start each node
    for NODE_OFFSET in 5 6 7; do
        local PORT=$((5160 + NODE_OFFSET))
        local IP_SUFFIX=$((NODE_OFFSET + 1))

        log_info "Starting node $NODE_OFFSET (port $PORT, IP 1.2.3.$IP_SUFFIX)..."

        (
            export MARKET_NODE_OFFSET=$NODE_OFFSET
            export LD_PRELOAD="$IPSPOOF_SO"
            export RUST_LOG=info,veilid_core=info
            export MP_SPDZ_DIR="$MP_SPDZ_DIR"
            cd "$MARKET_DIR"
            cargo run --release 2>&1 | sed "s/^/[Node $NODE_OFFSET] /"
        ) &
        PIDS+=($!)

        # Small delay between starts
        sleep 2
    done

    echo ""
    log_success "All 3 nodes started. Press Ctrl+C to stop the cluster."
    echo ""

    # Wait for all background processes
    wait
}

# =============================================================================
# Main
# =============================================================================

show_help() {
    echo "Dissertation Demo Setup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help     Show this help message"
    echo "  --build    Build only, don't start services"
    echo "  --clean    Clean up old data and docker volumes"
    echo "  --stop     Stop all services"
    echo "  --restart  Stop, clean, and restart everything"
    echo ""
    echo "Without options: Full setup and run"
}

main() {
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --clean)
            cleanup_data
            exit 0
            ;;
        --stop)
            stop_all
            exit 0
            ;;
        --restart)
            stop_all
            cleanup_data
            # Fall through to full setup
            ;;
        --build)
            header "Build Only Mode"
            build_ipspoof
            build_mpspdz
            build_market
            log_success "All components built successfully!"
            exit 0
            ;;
    esac

    # Full setup and run
    header "Dissertation Demo Setup"
    echo "This script will:"
    echo "  1. Build IP spoof library (for devnet)"
    echo "  2. Build MP-SPDZ and generate SSL certs"
    echo "  3. Build market app"
    echo "  4. Start Veilid devnet (Docker)"
    echo "  5. Start 3-node market cluster"
    echo ""

    # Build everything
    build_ipspoof
    build_mpspdz
    build_market

    # Start services
    start_devnet

    # Give devnet time to stabilize
    log_info "Waiting 10 seconds for devnet to stabilize..."
    sleep 10

    # Start market cluster (this blocks until Ctrl+C)
    start_market_cluster
}

main "$@"
