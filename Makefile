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
IPSPOOF_DIR  := $(REPOS_DIR)/dissertationapp/ip-spoof
IPSPOOF_SO   := $(IPSPOOF_DIR)/target/debug/libipspoof.so

.PHONY: help build build-release build-mpspdz build-ipspoof \
        devnet-up devnet-down devnet-restart \
        demo test test-e2e check clippy fmt clean clean-data

# ── Help ─────────────────────────────────────────────────────────────────────
help: ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ── Build ────────────────────────────────────────────────────────────────────
build: ## Build market crate (debug)
	cargo build --manifest-path $(MARKET_DIR)/Cargo.toml

build-release: ## Build market crate (release)
	cargo build --release --manifest-path $(MARKET_DIR)/Cargo.toml

build-mpspdz: ## Build MP-SPDZ (shamir-party.x, SSL certs, auction_n)
	$(ROOT_DIR)setup-mpspdz.sh --mp-spdz-dir $(MP_SPDZ_DIR)

build-ipspoof: ## Build libipspoof.so (Rust) for devnet IP spoofing
	cargo build --manifest-path $(IPSPOOF_DIR)/Cargo.toml

# ── Devnet ───────────────────────────────────────────────────────────────────
devnet-up: build-ipspoof ## Start Veilid devnet (5 processes)
	cargo run --manifest-path $(MARKET_DIR)/Cargo.toml --bin devnet-ctl -- start

devnet-down: ## Stop Veilid devnet
	cargo run --manifest-path $(MARKET_DIR)/Cargo.toml --bin devnet-ctl -- stop
	-pkill -f "target/debug/market" 2>/dev/null
	-pkill -f "target/release/market" 2>/dev/null

devnet-restart: devnet-down clean-data devnet-up ## Restart devnet with clean data

# ── Demo ─────────────────────────────────────────────────────────────────────
demo: build-ipspoof build-mpspdz build-release devnet-up ## Full demo: build everything, start devnet, launch 3 nodes
	@echo ""
	@echo "Starting 3-node market cluster..."
	@echo "  Node 5 -> port 5165, IP 1.2.3.6 (Bidder 1)"
	@echo "  Node 6 -> port 5166, IP 1.2.3.7 (Bidder 2)"
	@echo "  Node 7 -> port 5167, IP 1.2.3.8 (Auctioneer)"
	@echo ""
	@sleep 10
	@for offset in 5 6 7; do \
		( \
			export MARKET_NODE_OFFSET=$$offset; \
			export LD_PRELOAD=$(IPSPOOF_SO); \
			export RUST_LOG=info,veilid_core=info; \
			export MP_SPDZ_DIR=$(MP_SPDZ_DIR); \
			cd $(MARKET_DIR) && cargo run --release 2>&1 | sed "s/^/[Node $$offset] /"; \
		) & \
		sleep 2; \
	done; \
	trap 'kill $$(jobs -p) 2>/dev/null; wait' EXIT INT TERM; \
	wait

# ── Test ─────────────────────────────────────────────────────────────────────
test: ## Run unit + integration tests (mock-based)
	cargo test --manifest-path $(MARKET_DIR)/Cargo.toml

test-e2e: build-ipspoof  ## Run e2e tests (requires devnet + LD_PRELOAD)
	LD_PRELOAD=$(IPSPOOF_SO) cargo test --manifest-path $(MARKET_DIR)/Cargo.toml \
		--test integration_tests -- --ignored

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

clean-data: ## Remove node data directories
	rm -rf ~/.local/share/smpc-auction-node-*
	rm -rf /tmp/veilid-devnet
