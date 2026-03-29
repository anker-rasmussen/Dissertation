# =============================================================================
# Dissertation Project — Top-Level Makefile
# =============================================================================
#
#   make help         — show available targets
#   make build        — debug build of market crate
#   make demo         — playground devnet demo (build → start → run 3 nodes)
#   make bench        — run all benchmarks and generate plots
# =============================================================================

SHELL := /bin/bash

# ── Paths ────────────────────────────────────────────────────────────────────
ROOT_DIR     := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
REPOS_DIR    := $(ROOT_DIR)Repos
MARKET_DIR   := $(REPOS_DIR)/dissertationapp/market
MP_SPDZ_DIR  := $(REPOS_DIR)/MP-SPDZ
VEILID_DIR   := $(REPOS_DIR)/veilid
ifeq ($(shell uname -s),Darwin)
  IPSPOOF_SO     := $(VEILID_DIR)/target/release/libveilid_ipspoof.dylib
  PRELOAD_VAR    := DYLD_INSERT_LIBRARIES
else
  IPSPOOF_SO     := $(VEILID_DIR)/target/release/libveilid_ipspoof.so
  PRELOAD_VAR    := LD_PRELOAD
endif

.PHONY: help install-deps build build-release build-mpspdz build-playground \
        demo test clean bench bench-clean

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
			automake libtool; \
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
			automake libtool; \
	elif [ "$$(uname -s)" = "Darwin" ]; then \
		echo "Detected macOS..."; \
		brew install cmake openssl gmp libsodium boost automake libtool; \
	else \
		echo "Unsupported OS. Please install dependencies manually:"; \
		echo "  C++ toolchain (g++/clang++), cmake, python3, openssl, gmp,"; \
		echo "  libsodium, boost (filesystem, iostreams, thread),"; \
		echo "  GTK3/WebKit2GTK 4.1 (for Dioxus desktop), automake, libtool"; \
		exit 1; \
	fi
	@echo ""
	@echo "All system dependencies installed."

# ── Build ────────────────────────────────────────────────────────────────────
build: ## Build market crate (debug)
	cargo build --manifest-path $(MARKET_DIR)/Cargo.toml

build-release: ## Build market crate (release)
	cargo build --release --manifest-path $(MARKET_DIR)/Cargo.toml

build-mpspdz: ## Build MP-SPDZ (mascot-party.x, shamir-party.x, auction_n)
	$(ROOT_DIR)setup-mpspdz.sh --mp-spdz-dir $(MP_SPDZ_DIR)

build-playground: ## Build veilid-server + ipspoof + playground binary
	cargo build --release --manifest-path $(VEILID_DIR)/Cargo.toml \
		-p veilid-server -p veilid-ipspoof -p veilid-playground

# ── Demo ─────────────────────────────────────────────────────────────────────
demo: build-playground build-mpspdz build-release ## Full demo: build, start playground devnet, launch 3 nodes
	@echo "Cleaning previous data..."; \
	$(VEILID_DIR)/target/release/veilid-playground clean 2>/dev/null || true; \
	rm -rf /tmp/veilid-playground 2>/dev/null || true; \
	rm -rf $(HOME)/.local/share/smpc-auction-node-{20,21,22} /tmp/smpc-auction-node-{20,21,22} 2>/dev/null || true; \
	echo "Starting playground devnet (20 nodes)..."; \
	$(VEILID_DIR)/target/release/veilid-playground start 20 \
		--ipspoof $(IPSPOOF_SO) \
		--veilid-server $(VEILID_DIR)/target/release/veilid-server & \
	PLAYGROUND_PID=$$!; \
	echo "Waiting for devnet nodes..."; \
	for i in $$(seq 1 60); do \
		all_up=true; \
		for port in $$(seq 5150 5169); do \
			timeout 1 bash -c "echo >/dev/tcp/127.0.0.1/$$port" 2>/dev/null || { all_up=false; break; }; \
		done; \
		if [ "$$all_up" = true ]; then echo "Devnet ready (20/20 nodes)"; break; fi; \
		sleep 1; \
	done; \
	echo ""; \
	echo "Starting 3-node market cluster..."; \
	echo "  Node 20 -> port 5170, IP 1.2.3.21 (Bidder 1)"; \
	echo "  Node 21 -> port 5171, IP 1.2.3.22 (Bidder 2)"; \
	echo "  Node 22 -> port 5172, IP 1.2.3.23 (Auctioneer/Seller)"; \
	echo ""; \
	trap 'kill $$PLAYGROUND_PID $$(jobs -p) 2>/dev/null; wait' EXIT INT TERM; \
	for offset in 20 21 22; do \
		if [ $$offset -eq 22 ]; then \
			DEMO_ARGS="--demo-role seller --demo-duration 90"; \
		else \
			DEMO_ARGS="--demo-role bidder"; \
		fi; \
		( \
			export VEILID_NODE_OFFSET=$$offset; \
			export VEILID_INSECURE_STORAGE=true; \
			export $(PRELOAD_VAR)=$(IPSPOOF_SO); \
			export RUST_LOG=market=info,veilid_core=warn; \
			export MP_SPDZ_DIR=$(MP_SPDZ_DIR); \
			$(MARKET_DIR)/target/release/market $$DEMO_ARGS 2>&1 | sed "s/^/[Node $$offset] /"; \
		) & \
		sleep 2; \
	done; \
	wait

# ── Test ─────────────────────────────────────────────────────────────────────
test: ## Run unit + integration tests (mock-based)
	cargo test --manifest-path $(MARKET_DIR)/Cargo.toml

# ── Clean ────────────────────────────────────────────────────────────────────
clean: ## Remove all build artifacts and node data
	cargo clean --manifest-path $(MARKET_DIR)/Cargo.toml
	rm -rf ~/.local/share/smpc-auction-node-*
	rm -rf /tmp/veilid-playground*
	-pkill -f "target/debug/market" 2>/dev/null
	-pkill -f "target/release/market" 2>/dev/null
	-pkill -f "veilid-server" 2>/dev/null

# ── Benchmarks ──────────────────────────────────────────────────────────
BENCH_DIR    := $(MARKET_DIR)/scripts/bench
BENCH_OUT    := $(MARKET_DIR)/bench-results
BENCH_ITERS  ?= 5
BENCH_DEVNET_SIZES ?= 40 60 80
BENCH_WARMUP_SECS ?= 20

bench: build-mpspdz build-release build-playground ## Run all benchmarks (direct + Veilid) and generate plots
	@echo "=== Phase 1: Direct MPC (localhost, no Veilid) ==="
	cd $(MARKET_DIR) && \
	BENCH_ITERS=$(BENCH_ITERS) \
	MP_SPDZ_DIR=$(MP_SPDZ_DIR) \
	BENCH_OUT=$(BENCH_OUT)/direct_mpc.csv \
	bash $(BENCH_DIR)/run_mpc_direct.sh
	@echo ""
	@echo "=== Phase 2: MASCOT over Veilid (3-10 parties, devnet $(BENCH_DEVNET_SIZES)) ==="
	cd $(MARKET_DIR) && \
	$(PRELOAD_VAR)=$(IPSPOOF_SO) \
	MP_SPDZ_DIR=$(MP_SPDZ_DIR) \
	BENCH_ITERS=$(BENCH_ITERS) \
	BENCH_PARTIES="3 4 5 6 8 10" \
	BENCH_DEVNET_SIZES="$(BENCH_DEVNET_SIZES)" \
	BENCH_WARMUP_SECS=$(BENCH_WARMUP_SECS) \
	BENCH_MPC_PROTOCOL=mascot \
	MPC_PROTOCOL=mascot-party.x \
	BENCH_OUT=$(BENCH_OUT)/veilid_auction.csv \
	cargo run --release --bin bench-auction
	@echo ""
	@echo "=== Phase 3: Shamir over Veilid (3-20 parties, devnet $(BENCH_DEVNET_SIZES)) ==="
	cd $(MARKET_DIR) && \
	$(PRELOAD_VAR)=$(IPSPOOF_SO) \
	MP_SPDZ_DIR=$(MP_SPDZ_DIR) \
	BENCH_ITERS=$(BENCH_ITERS) \
	BENCH_PARTIES="3 4 5 6 8 10 15 20" \
	BENCH_DEVNET_SIZES="$(BENCH_DEVNET_SIZES)" \
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

# ── Dissertation ─────────────────────────────────────────────────────────────

DISS_DIR := $(ROOT_DIR)Dissertation
DISS_CHAPTERS := Ch1_Introduction.tex Ch2_OutputSummary.tex Ch3_Context.tex \
                 Ch4_Method.tex Ch5_Results.tex Ch6_Conclusions.tex

wordcount: ## Update dissertation word count (writes Dissertation/wordcount.tex)
	@cd $(DISS_DIR) && \
	WC=$$(texcount -inc -total -1 -sum $(DISS_CHAPTERS) 2>/dev/null) && \
	printf '%% Auto-generated by: make wordcount\n%% Do not edit manually.\n\\renewcommand{\\wordcount}{%s}\n' \
		"$$(printf '%d' "$$WC" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')" \
		> wordcount.tex && \
	echo "Word count: $$WC"

pdf: wordcount ## Build dissertation PDF
	cd $(DISS_DIR) && latexmk -pdf Dissertation.tex
