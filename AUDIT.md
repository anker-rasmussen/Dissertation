# Production Readiness Audit — Sealed-Bid Auction Marketplace

**Date:** 2026-02-14
**Reviewer posture:** Principal SWE, distributed systems — "What stops this from going live?"
**Scope:** `Repos/dissertationapp/market/` (Rust), `Repos/MP-SPDZ/Programs/Source/auction_n.mpc`

---

## Executive Summary

This system implements a sealed-bid auction marketplace over Veilid P2P with MP-SPDZ MPC for bid privacy. The architecture is sound in concept — trait-based DI, two-tier coordination, MASCOT for malicious-security MPC. However, **the system is not production-ready**. There are protocol-level trust violations that allow both sellers and winners to cheat, network resilience gaps that enable DoS and data loss, and resource leaks that degrade availability over time.

### Verdict: **NOT READY FOR PRODUCTION DEPLOYMENT**

| Category | Severity | Blocking Issues |
|----------|----------|-----------------|
| MPC Protocol Correctness | **P0** | 3 critical (seller forge, winner forge, party desync) |
| Network Resilience | **P0** | 4 critical (unbounded queues, no timeouts, DHT races, no partition recovery) |
| Resource Management | **P1** | 5 issues (TCP leaks, route leaks, zombie processes, unbounded buffers) |
| Security & Crypto | **P1** | 2 issues (CBOR deser DoS, no input validation on bids) |
| Error Handling | **P1** | 9 production panic paths via unwrap/expect |
| Configuration | **P2** | 7 hardcoded values (insecure storage, network key, ports, paths) |
| Testing | **P2** | 1448 LOC critical path untested, zero fuzz/adversarial tests |
| Concurrency | **P3** | 1 medium (double mutex pattern), otherwise sound |

---

## P0 — Protocol-Level Trust Violations

These are fundamental design flaws. An adversary doesn't need to exploit a bug — the protocol *as designed* allows cheating.

### 1. Seller Can Forge MPC Results
**`mpc_orchestrator.rs:37-82`, `mpc_execution.rs:154-182`**

The seller (party 0) runs MP-SPDZ locally and parses stdout to determine the winner. There is **no cryptographic attestation** that the MPC output is genuine. The seller can fabricate stdout with any winner/bid, then announce that result to the network.

**Impact:** Total auction compromise. Seller picks winner, steals deposits, denies legitimate sales.

**Fix required:** MPC output must be attested — either all parties independently verify the result, or use MP-SPDZ's commitment/MAC-based output verification.

### 2. Winner Can Forge Bid Reveal
**`auction_coordinator.rs:730-806`**

Post-MPC, the winner reveals their bid to the seller. The seller checks that SHA256(revealed_bid || nonce) matches the commitment — but **never verifies** that revealed_bid equals the value actually submitted to MPC. The winner can reveal any value and the commitment check passes (they know their own nonce).

**Impact:** Winner claims a lower price than their actual winning bid.

**Fix required:** Bind the commitment to the MPC input. The MPC program should output a hash of the winning bid that the seller can cross-check.

### 3. Nondeterministic Party Assignment
**`bid_record.rs:95-103`**

Party IDs are assigned by sorting bids by timestamp + pubkey tiebreaker. But bids are fetched asynchronously from DHT. If nodes see bids arrive in different orders or at different times, **they may compute different party assignments**. MASCOT requires all parties to agree on who is party 0, 1, 2, ...

**Impact:** MPC protocol fails silently. Parties compute on mismatched inputs.

**Fix required:** Party assignment must be committed to DHT (e.g., seller publishes canonical ordering) before MPC begins. All parties must read and agree on the same ordering.

---

## P0 — Network Resilience

These issues cause data loss, hangs, or denial-of-service under normal distributed systems failure modes.

### 4. Unbounded Message Queue
**`node.rs:67`**

`mpsc::unbounded_channel()` for Veilid update callbacks. No backpressure. A malicious peer flooding app_message can exhaust process memory.

**Fix:** Use bounded channel with configurable capacity + drop policy.

### 5. No Timeouts on Network Sends
**`auction_coordinator.rs:623, 1153`, `mpc.rs:200`**

`routing_context.app_message()` has no timeout wrapper. If a route is stale or the peer is down, the call blocks indefinitely, stalling the main auction processing loop.

**Fix:** Wrap all network sends in `tokio::time::timeout()`.

### 6. DHT Read-Modify-Write Races
**`bid_ops.rs:48-112`, `auction_coordinator.rs:460-476`**

Bid index updates use optimistic read-then-write with retry, but **no compare-and-swap**. Between the read and write, another node can modify the same DHT record. Concurrent bids on the same listing can be silently lost.

**Fix:** Use Veilid's DHT sequence numbers for CAS, or implement a conflict resolution strategy.

### 7. No Partition Recovery
**`auction_coordinator.rs:582-640, 1352-1369`**

If a node disconnects mid-auction:
- Winner never receives challenge (20s timeout, then give up)
- Monitoring loop retries MPC indefinitely but never removes stale listings
- No mechanism to resume or cancel auctions after network heal

**Fix:** Add auction TTLs, state checkpointing, and explicit cancellation protocol.

---

## P1 — Resource Management

### 8. TCP Listener Leak
**`mpc.rs:169-178`**

`TcpListener` spawned per MPC party in `run_outgoing_proxy()` runs forever in an accept loop. If MPC execution fails or times out, the listener socket remains open until process exit. Repeated auctions exhaust ports.

### 9. Routing Context Leak
**`mpc.rs:191-200`**

`api.routing_context()` created per connection, never explicitly released. Veilid routing contexts hold route references internally. Over time, this pollutes the DHT route table.

### 10. Zombie MPC Processes
**`mpc_execution.rs:141-145`**

On timeout, `child.kill().await` is called but the process isn't waited/reaped. Zombie `mascot-party.x` processes accumulate.

### 11. Route Manager Leak
**`mpc_orchestrator.rs:538-544`**

`cleanup_route_manager()` only runs on explicit call. When auctions end or MPC fails, route managers stay registered. The `route_managers` map grows unboundedly.

### 12. Unbounded Pending Data Buffer
**`mpc.rs:66`**

`pending_data: HashMap<usize, Vec<Vec<u8>>>` has a 10MB cap check but **no eviction**. Entries for crashed/disconnected parties are never removed.

---

## P1 — Security & Cryptography

### 13. CBOR Deserialization Without Size Limits
**`listing.rs:167`, `bid.rs:120,150,189`, `registry.rs:80,146`, `bid_announcement.rs:128`**

All `ciborium::from_reader()` calls accept unbounded input. While Veilid DHT enforces 32KB values, a crafted CBOR payload with deeply nested structures or huge string lengths can cause OOM during parsing.

**Fix:** Use `ciborium::from_reader()` with a length-limited reader wrapper, or validate payload size before deserializing.

### 14. No Bid Amount Validation
**`bid.rs:33-53`, `auction_n.mpc:26-29`**

No validation that bid amounts are positive or within reasonable bounds. Zero bids, negative values (in MPC's integer domain), or u64::MAX are accepted. In the MPC program, bids are read from stdin without range checks.

### 15. Timing Side-Channel
**`bid_record.rs:92-103`, `mpc_verification.rs:18-26`**

Bid timestamps are stored in plaintext DHT and used for party ordering. An observer can correlate timestamps with network traffic to de-anonymize bidders, partially defeating the privacy goal.

---

## P1 — Error Handling (9 Panic Paths)

Production code contains `unwrap()`, `expect()`, and silent error swallowing that will crash the process under edge conditions:

| Location | Pattern | Risk |
|----------|---------|------|
| `mpc_execution.rs:110-111` | `.expect()` on piped stdout/stderr | Panic if pipe setup fails |
| `mpc_execution.rs:117,124` | `.unwrap_or(0)` on read | Silent loss of MPC output |
| `mpc_execution.rs:130` | `.unwrap_or_default()` on join | Task panic goes unnoticed |
| `config.rs:56` | `.expect()` on system clock | Panic on clock misconfiguration |
| `bid_storage.rs:96` | `.expect()` on RecordKey | Panic on invalid key format |
| `app/components.rs:37` | `.unwrap_or_default()` on node ID | Silent empty string in UI |
| `app/components.rs:584` | `.expect()` on SHARED_STATE | Panic if init ordering wrong |
| `main.rs:191,212` | `let _ = shutdown()` | Shutdown errors silently discarded |
| `app/actions.rs:119-128` | `.map_err()` → `warn!()` | Network errors not shown to user |

**Fix:** Replace all `.expect()` in non-test code with `?` or `.map_err()`. Add error propagation from action handlers to UI.

---

## P2 — Hardcoded Configuration

These prevent deployment outside the development environment without rebuilding:

| Value | Location | Issue |
|-------|----------|-------|
| `always_use_insecure_storage: true` | `main.rs:181` | Veilid protected store unencrypted |
| `"development-network-2025"` | `config.rs:32`, `node.rs:43` | Network key baked in |
| `udp://1.2.3.1:5160` | `node.rs:47` | Bootstrap IP for devnet only |
| `concat!(env!("CARGO_MANIFEST_DIR"), "/../../MP-SPDZ")` | `config.rs:43` | Build-time path baked into binary |
| `limit_over_attached: 8` | `node.rs:148-153` | Routing table sized for 8 nodes |
| `max_wait_secs = 180` | `main.rs:200` | Network attachment timeout |
| `now < 1900000000` | `config.rs:73-77` | Timestamp sanity check fails after 2030 |

**Fix:** Create a unified `Config` struct loaded from TOML/env vars. Zero magic numbers in source.

---

## P2 — Testing Gaps

### Coverage Holes

| Module | LOC | Tests |
|--------|-----|-------|
| `auction_coordinator.rs` | 1448 | **Zero** |
| `node.rs` | 339 | **Zero** |
| `dht.rs` | 349 | **Zero** |
| `mpc_routes.rs` | ~200 | **Zero** |
| `app/actions.rs` | ~200 | **Zero** |
| `app/state.rs` | ~100 | **Zero** |
| `app/components.rs` | ~600 | **Zero** |

### Missing Test Categories

- **Fuzzing:** Zero fuzz targets. CBOR deserialization and bid commitment validation are prime candidates.
- **Adversarial inputs:** No tests for malformed DHT records, oversized bids, replayed announcements.
- **Stress/load:** No tests for 10+ party auctions or concurrent bid storms.
- **Property-based:** No quickcheck/proptest for auction invariants (e.g., "highest bid always wins").
- **Failure injection:** No tests for partial MPC completion, DHT timeouts, route exhaustion.

### Mock Fidelity Issues

- **MockDht** doesn't enforce subkey structure, ownership, or sequence numbers
- **MockTransport** assumes all routes available, no latency/loss simulation
- **MockMpcRunner** returns hardcoded winner, doesn't validate party count or input format

---

## P3 — Concurrency

The concurrency model is **generally sound**. Rust's type system prevents most data races at compile time. One notable pattern:

### Double Mutex Acquisition
**`auction_coordinator.rs:599-608`**

Clones `Arc<Mutex>` while holding parent lock, then re-acquires. Not a deadlock (scoping prevents it), but semantically fragile. Would fail code review for lock discipline.

### Positive Findings
- `CancellationToken` + `tokio::select!` for graceful shutdown ✓
- `RwLock` used correctly for read-heavy state (BidStorage, AppState) ✓
- No illegal state machine transitions detected in AuctionLogic ✓
- No locks held across `.await` points in critical paths ✓

---

## Prioritized Remediation Roadmap

### Must-fix before any deployment (P0)
1. Cryptographically attest MPC output (prevent seller forgery)
2. Bind bid commitment to MPC input (prevent winner forgery)
3. Deterministic party assignment via DHT-published canonical ordering
4. Bounded message channels with backpressure
5. Timeouts on all network operations
6. CAS or conflict resolution for DHT writes

### Must-fix before untrusted users (P1)
7. CBOR size-limited deserialization
8. Bid amount validation (0 < bid < MAX_BID)
9. TCP listener cleanup after MPC completion
10. Zombie process reaping for mascot-party.x
11. Replace all `.expect()` / `.unwrap()` in production paths
12. Route manager cleanup on auction end

### Should-fix before scale (P2)
13. Externalize all configuration (TOML + env vars)
14. Add fuzz targets for CBOR, bid commitments, message parsing
15. Unit tests for auction_coordinator.rs (1448 LOC @ 0% coverage)
16. Adversarial integration tests (malformed inputs, replay attacks)

### Nice-to-have (P3)
17. Lock discipline documentation (ordering invariants)
18. Structured error types (unify anyhow → thiserror)
19. Metrics / observability (Prometheus counters for auction lifecycle)
20. Partition detection and auction state recovery protocol

---

*Generated by automated multi-domain audit. Findings should be validated against the latest codebase revision.*
