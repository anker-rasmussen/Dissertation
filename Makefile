# =============================================================================
# Dissertation Project — Top-Level Makefile
# =============================================================================
# Composable build/run targets that delegate to existing scripts.
#
#   make help         — show available targets
#   make build        — debug build of market crate
#   make test         — run unit + integration tests
#   make demo         — full devnet demo (build → start → run 3 nodes)
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

.PHONY: help install-deps build build-release build-mpspdz build-ipspoof \
        devnet-up devnet-down devnet-restart \
        demo test test-e2e test-e2e-full check clippy fmt clean clean-data coverage coverage-e2e release-gate

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

build-release: ## Build market crate (release)
	cargo build --release --manifest-path $(MARKET_DIR)/Cargo.toml

build-mpspdz: ## Build MP-SPDZ (mascot-party.x, auction_n)
	$(ROOT_DIR)setup-mpspdz.sh --mp-spdz-dir $(MP_SPDZ_DIR)

build-ipspoof: $(IPSPOOF_SO) ## Build libipspoof.so for devnet IP spoofing

$(IPSPOOF_SO): $(IPSPOOF_SRC)
	gcc -shared -fPIC -o $@ $< -ldl

# ── Devnet ───────────────────────────────────────────────────────────────────
devnet-up: ## Start Veilid devnet (Docker)
	docker compose -f $(COMPOSE_FILE) up -d
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

devnet-down: ## Stop Veilid devnet
	docker compose -f $(COMPOSE_FILE) down
	-pkill -f "target/debug/market" 2>/dev/null
	-pkill -f "target/release/market" 2>/dev/null

devnet-restart: devnet-down clean-data devnet-up ## Restart devnet with clean data

# ── Demo ─────────────────────────────────────────────────────────────────────
demo: build-ipspoof build-mpspdz build-release devnet-up ## Full demo: build everything, start devnet, launch 3 nodes
	@echo ""
	@echo "Starting 3-node market cluster..."
	@echo "  Node 9  -> port 5169, IP 1.2.3.10 (Bidder 1)"
	@echo "  Node 10 -> port 5170, IP 1.2.3.11 (Bidder 2)"
	@echo "  Node 11 -> port 5171, IP 1.2.3.12 (Auctioneer)"
	@echo ""
	@sleep 10
	@trap 'kill $$(jobs -p) 2>/dev/null; wait' EXIT INT TERM; \
	for offset in 9 10 11; do \
		( \
			export MARKET_NODE_OFFSET=$$offset; \
			export LD_PRELOAD=$(IPSPOOF_SO); \
			export RUST_LOG=info,veilid_core=info; \
			export MP_SPDZ_DIR=$(MP_SPDZ_DIR); \
			cd $(MARKET_DIR) && cargo run --release 2>&1 | sed "s/^/[Node $$offset] /"; \
		) & \
		sleep 2; \
	done; \
	wait

# ── Test ─────────────────────────────────────────────────────────────────────
test: ## Run unit + integration tests (mock-based)
	cargo test --manifest-path $(MARKET_DIR)/Cargo.toml

test-e2e: build-ipspoof  ## Run e2e smoke tests (requires devnet + LD_PRELOAD)
	LD_PRELOAD=$(IPSPOOF_SO) cargo test --manifest-path $(MARKET_DIR)/Cargo.toml \
		--test integration_tests -- --ignored e2e_smoke_

test-e2e-full: build-ipspoof ## Run full e2e tests (MPC/decryption, slower)
	LD_PRELOAD=$(IPSPOOF_SO) cargo test --manifest-path $(MARKET_DIR)/Cargo.toml \
		--test integration_tests -- --ignored e2e_full_

# ── Quality ──────────────────────────────────────────────────────────────────
check: ## cargo check
	cargo check --manifest-path $(MARKET_DIR)/Cargo.toml

clippy: ## cargo clippy with warnings as errors
	cargo clippy --manifest-path $(MARKET_DIR)/Cargo.toml -- -D warnings

fmt: ## Check formatting
	cargo fmt --manifest-path $(MARKET_DIR)/Cargo.toml -- --check

# ── Clean ────────────────────────────────────────────────────────────────────
clean: ## cargo clean
	cargo clean --manifest-path $(MARKET_DIR)/Cargo.toml

clean-data: ## Remove node data directories and docker volumes
	rm -rf ~/.local/share/smpc-auction-node-*
	-docker volume ls | grep veilid | awk '{print $$2}' | xargs -r docker volume rm 2>/dev/null

# ── Coverage ────────────────────────────────────────────────────────────────
coverage: ## Run tests with coverage (requires cargo-llvm-cov)
	cargo llvm-cov --manifest-path $(MARKET_DIR)/Cargo.toml --html

coverage-e2e: build-ipspoof ## Run all tests (incl. e2e) with coverage (requires devnet)
	LD_PRELOAD=$(IPSPOOF_SO) cargo llvm-cov --manifest-path $(MARKET_DIR)/Cargo.toml \
		--html -- --include-ignored

release-gate: ## Verify clean tree and submodule pin integrity
	$(ROOT_DIR)scripts/release_gate.sh
