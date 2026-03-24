# =============================================================================
# Dissertation Project — Top-Level Makefile
# =============================================================================
#
#   make help         — show available targets
#   make build        — debug build of market crate
#   make demo         — full devnet demo (build → start → run 3 nodes)
#   make bench        — run all benchmarks and generate plots
# =============================================================================

SHELL := /bin/bash

# ── Paths ────────────────────────────────────────────────────────────────────
ROOT_DIR     := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
REPOS_DIR    := $(ROOT_DIR)Repos
MARKET_DIR   := $(REPOS_DIR)/dissertationapp/market
MP_SPDZ_DIR  := $(REPOS_DIR)/MP-SPDZ
VEILID_DIR   := $(REPOS_DIR)/veilid
IPSPOOF_SRC  := $(VEILID_DIR)/.devcontainer/scripts/ip_spoof.c
IPSPOOF_SO   := $(VEILID_DIR)/.devcontainer/scripts/libipspoof.so
COMPOSE_FILE := $(VEILID_DIR)/.devcontainer/compose/docker-compose.dev.yml

PLAYGROUND_BIN   := $(HOME)/Repos/veilid/target/release/veilid-playground
PLAYGROUND_DATA  := /tmp/veilid-playground

.PHONY: help install-deps build build-release build-mpspdz build-ipspoof \
        demo test clean bench bench-clean devnet-up devnet-down

# ── Help ─────────────────────────────────────────────────────────────────────
help: ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ── Dependencies ─────────────────────────────────────────────────────────────
install-deps: ## Install all system dependencies (requires sudo)
	@command -v cargo >/dev/null 2>&1 || \
		{ echo "Rust not found. Install via: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"; exit 1; }
	@if [ -f /etc/arch-release ]; then \
		echo "Detected Arch Linux..."; \
		sudo pacman -S --needed --noconfirm \
			base-devel pkgconf cmake clang python \
			openssl xdotool webkit2gtk-4.1 gtk3 libsoup3 \
			glib2 atk cairo pango gdk-pixbuf2 \
			gmp libsodium boost boost-libs \
			automake libtool docker docker-compose; \
	elif [ -f /etc/debian_version ]; then \
		echo "Detected Debian/Ubuntu..."; \
		sudo apt-get update && sudo apt-get install -y --no-install-recommends \
			build-essential pkg-config cmake clang python3 \
			libssl-dev libxdo-dev \
			libwebkit2gtk-4.1-dev libgtk-3-dev libsoup-3.0-dev \
			libjavascriptcoregtk-4.1-dev libglib2.0-dev \
			libatk1.0-dev libcairo2-dev libpango1.0-dev \
			libgdk-pixbuf-2.0-dev \
			libgmp-dev libsodium-dev \
			libboost-dev libboost-filesystem-dev \
			libboost-iostreams-dev libboost-thread-dev \
			automake libtool docker.io docker-compose; \
	elif [ "$$(uname -s)" = "Darwin" ]; then \
		echo "Detected macOS..."; \
		brew install cmake openssl gmp libsodium boost automake libtool docker docker-compose; \
	else \
		echo "Unsupported OS. Please install dependencies manually:"; \
		echo "  C++ toolchain (g++/clang++), cmake, python3, openssl, gmp,"; \
		echo "  libsodium, boost (filesystem, iostreams, thread),"; \
		echo "  GTK3/WebKit2GTK 4.1 (for Dioxus desktop), automake, libtool, docker"; \
		exit 1; \
	fi
	@echo ""
	@echo "All system dependencies installed."

# ── Build ────────────────────────────────────────────────────────────────────
build: ## Build market crate (debug)
	cargo build --manifest-path $(MARKET_DIR)/Cargo.toml

build-release:
	cargo build --release --manifest-path $(MARKET_DIR)/Cargo.toml

build-mpspdz:
	$(ROOT_DIR)setup-mpspdz.sh --mp-spdz-dir $(MP_SPDZ_DIR)

build-ipspoof: $(IPSPOOF_SO)

$(IPSPOOF_SO): $(IPSPOOF_SRC)
	gcc -shared -fPIC -o $@ $< -ldl

# ── Demo ─────────────────────────────────────────────────────────────────────
demo: build-ipspoof build-mpspdz build-release ## Full demo: build, start devnet, launch 3 nodes
	@docker compose -f $(COMPOSE_FILE) down -v 2>/dev/null; true
	@rm -rf ~/.local/share/smpc-auction-node-*
	@docker compose -f $(COMPOSE_FILE) up -d
	@echo "Waiting for bootstrap to be healthy..."
	@healthy=false; \
	for i in $$(seq 1 30); do \
		if docker compose -f $(COMPOSE_FILE) ps | grep -q healthy; then \
			healthy=true; break; \
		fi; \
		sleep 2; printf "."; \
	done; echo ""; \
	if [ "$$healthy" = "false" ]; then \
		echo "ERROR: Devnet bootstrap did not become healthy after 60 seconds"; \
		exit 1; \
	fi
	@echo ""
	@echo "Starting 3-node market cluster..."
	@echo "  Node 20 -> port 5170, IP 1.2.3.21 (Bidder 1)"
	@echo "  Node 21 -> port 5171, IP 1.2.3.22 (Bidder 2)"
	@echo "  Node 22 -> port 5172, IP 1.2.3.23 (Auctioneer/Seller)"
	@echo ""
	@sleep 10
	@trap 'kill $$(jobs -p) 2>/dev/null; wait' EXIT INT TERM; \
	for offset in 20 21 22; do \
		if [ $$offset -eq 22 ]; then \
			DEMO_ARGS="--demo-role seller --demo-duration 90"; \
		else \
			DEMO_ARGS="--demo-role bidder"; \
		fi; \
		( \
			export VEILID_NODE_OFFSET=$$offset; \
			export LD_PRELOAD=$(IPSPOOF_SO); \
			export RUST_LOG=info,veilid_core=info; \
			export MP_SPDZ_DIR=$(MP_SPDZ_DIR); \
			cd $(MARKET_DIR) && cargo run --release -- $$DEMO_ARGS 2>&1 | sed "s/^/[Node $$offset] /"; \
		) & \
		sleep 2; \
	done; \
	wait

# ── Test ─────────────────────────────────────────────────────────────────────
test: ## Run unit + integration tests (mock-based)
	cargo test --manifest-path $(MARKET_DIR)/Cargo.toml

# ── Clean ────────────────────────────────────────────────────────────────────
clean: ## Remove all build artifacts, node data, and docker volumes
	cargo clean --manifest-path $(MARKET_DIR)/Cargo.toml
	rm -rf ~/.local/share/smpc-auction-node-*
	-docker compose -f $(COMPOSE_FILE) down -v 2>/dev/null
	-pkill -f "target/debug/market" 2>/dev/null
	-pkill -f "target/release/market" 2>/dev/null

# ── Devnet ──────────────────────────────────────────────────────────────────
devnet-up: ## Start Docker devnet (20 nodes)
	docker compose -f $(COMPOSE_FILE) up -d

devnet-down: ## Stop Docker devnet and clean volumes
	docker compose -f $(COMPOSE_FILE) down -v

# ── Benchmarks ──────────────────────────────────────────────────────────
BENCH_DIR    := $(MARKET_DIR)/scripts/bench
BENCH_OUT    := $(MARKET_DIR)/bench-results
BENCH_ITERS  ?= 5
BENCH_DEVNET_MODE ?= docker
BENCH_DEVNET_SIZES ?= 40 60 80
BENCH_WARMUP_SECS ?= 60

# Ipspoof: use Rust ipspoof for playground, C ipspoof for Docker
PLAYGROUND_IPSPOOF := $(HOME)/Repos/veilid/target/release/libveilid_ipspoof.so
ifeq ($(BENCH_DEVNET_MODE),playground)
  BENCH_IPSPOOF := $(PLAYGROUND_IPSPOOF)
else
  BENCH_IPSPOOF := $(IPSPOOF_SO)
endif

bench: build-mpspdz build-release ## Run all benchmarks (direct + Veilid) and generate plots
ifeq ($(BENCH_DEVNET_MODE),docker)
	$(MAKE) build-ipspoof
endif
	@echo "=== Phase 1: Direct MPC (localhost, no Veilid) ==="
	cd $(MARKET_DIR) && \
	BENCH_ITERS=$(BENCH_ITERS) \
	MP_SPDZ_DIR=$(MP_SPDZ_DIR) \
	BENCH_OUT=$(BENCH_OUT)/direct_mpc.csv \
	bash $(BENCH_DIR)/run_mpc_direct.sh
	@echo ""
	@echo "=== Phase 2: MASCOT over Veilid (3-10 parties, devnet $(BENCH_DEVNET_SIZES)) ==="
	cd $(MARKET_DIR) && \
	LD_PRELOAD=$(BENCH_IPSPOOF) \
	MP_SPDZ_DIR=$(MP_SPDZ_DIR) \
	BENCH_ITERS=$(BENCH_ITERS) \
	BENCH_PARTIES="3 4 5 6 8 10" \
	BENCH_DEVNET_SIZES="$(BENCH_DEVNET_SIZES)" \
	BENCH_DEVNET_MODE=$(BENCH_DEVNET_MODE) \
	BENCH_WARMUP_SECS=$(BENCH_WARMUP_SECS) \
	BENCH_MPC_PROTOCOL=mascot \
	MPC_PROTOCOL=mascot-party.x \
	BENCH_OUT=$(BENCH_OUT)/veilid_auction.csv \
	cargo run --release --bin bench-auction
	@echo ""
	@echo "=== Phase 3: Shamir over Veilid (3-20 parties, devnet $(BENCH_DEVNET_SIZES)) ==="
	cd $(MARKET_DIR) && \
	LD_PRELOAD=$(BENCH_IPSPOOF) \
	MP_SPDZ_DIR=$(MP_SPDZ_DIR) \
	BENCH_ITERS=$(BENCH_ITERS) \
	BENCH_PARTIES="3 4 5 6 8 10 15 20" \
	BENCH_DEVNET_SIZES="$(BENCH_DEVNET_SIZES)" \
	BENCH_DEVNET_MODE=$(BENCH_DEVNET_MODE) \
	BENCH_WARMUP_SECS=$(BENCH_WARMUP_SECS) \
	BENCH_MPC_PROTOCOL=shamir \
	MPC_PROTOCOL=shamir-party.x \
	BENCH_OUT=$(BENCH_OUT)/veilid_auction.csv \
	cargo run --release --bin bench-auction
	@echo ""
	@echo "=== Phase 4: Generating plots ==="
	python3 $(BENCH_DIR)/plot_results.py \
		--results-dir $(BENCH_OUT) \
		--output-dir $(BENCH_OUT)/plots
	@echo ""
	@echo "Benchmark complete. Plots saved to: $(BENCH_OUT)/plots/"
	@ls -la $(BENCH_OUT)/plots/*.pdf 2>/dev/null || true

bench-clean: ## Remove all benchmark results and plots
	rm -rf $(BENCH_OUT)
