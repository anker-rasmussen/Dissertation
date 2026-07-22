# Veilid 0.5.3 → 0.5.7 Upgrade — Change Summary

A readable tour of everything that changed across the July 2026 upgrade sessions
(2026-07-19 → 2026-07-22). The working tracker with full analysis is
[ROADMAP.md](ROADMAP.md); this document is the guided version. Commit SHAs are
noted as **fork** (`Repos/veilid`, gitlab.com/tech_new/veilid) or **app**
(`Repos/dissertationapp`, github.com/anker-rasmussen/dissertationapp).

## The headline numbers

| Measurement | Before (0.5.3) | After (0.5.7 + fixes) |
|---|---|---|
| E2E sequential auctions | 263.4s | **109.2s** (−59%) |
| E2E concurrent auctions | 207.8s | **81.2s** (−61%) |
| E2E happy path | 116.2s | **67.2s** (−42%) |
| Full suite | 591.6s | **284.9s** (−52%) |
| Devnet E2E setup gate | ~90s, timeout-prone | **~5s** |
| MPC route_exchange phase | 26.8–29.8s | **13.3–19.4s** |
| `make demo` post-MPC key delivery | 20+s (timeout + resend) | **25ms** |
| Unit/integration tests | 224 pass | 224 pass |

## 1. The migration itself (Phases 0–4)

- **Merged upstream v0.5.7** into the fork (fork `19d2c0f7`). Only two real
  conflicts (Cargo.lock, bucket_entry split). Patch dispositions: recursion-limit
  CI fix dropped (superseded upstream), ping-span dropped (mechanism removed),
  playground `limit_*` config removed (0.5.4+ computes attachment level
  adaptively — the old high-limit hack is obsolete), BOOT-v0 and route-cache
  patches kept.
- **Market compiles at 0.5.7** (app `00bb773`): the tuned public config surface
  (rpc timeout, DHT timeouts, connection counts) moved behind the internal
  "footgun" config, so the market's hand-tuning was deleted wholesale. Later
  verified: 0.5.7's internal defaults are byte-identical to our old tuned values,
  so nothing was actually lost.
- **Clippy 1.95 baseline repair** (app `cb88483`), including a real footgun fix:
  loser-key IPC errors now fail tests loudly instead of reading as "no key".

## 2. The genesis deadlock — four fork patches (Phase 2b)

At 0.5.7 a fresh isolated network **cannot form**: upstream assumes an
established public network already exists. Root-caused with strace + a
debug-logged extra node reading the `stage:` state machine lines. Four
interlocking gates, each its own patch (prime upstream-MR material):

1. **fork `b979a4f9`** — static dial info required ≥5 live peers to confirm
   (`EXTERNAL_INFO_VALIDATIONS`); fully-static config now confirms peerlessly.
2. **fork `fac1a4d8`** — BOOT v0 replied `[]` before first publication; now
   falls back to current unpublished PeerInfo once dial info is confirmed.
3. **fork `1c3655b4`** — relay requirements demanded WS/WSS/IPv6 coverage a
   UDP/TCP/IPv4 devnet can never provide (stuck `NeedsRelays` forever); now
   scoped to the node's own address types × outbound protocols.
4. **fork `b6c3fb2f`** — ipspoof's 1.2.3.x addresses classify as NAT-translated
   and demanded a relay even for Direct-class dial info; Direct is now exempt.

Plus config repairs: `min_peer_count` hard-fails at 0.5.7 (was killing every
node at spawn — the uniform-97s E2E failure), `ws.connect=false` needed in
devnet configs (fork `f68bec29`, app `8796968`).

**Result:** 20/20 devnet nodes reachable in ~5s; each node bootstraps exactly
once in 7–138ms.

## 3. The three performance root causes (Phase 5g)

Profiling the happy path (timestamped runs + op-id-level veilid-core debug
logs) found three independent defects:

### Finding 1 — devnet IPv6 leak (fork `0af0ac69`, app `7fca3a1`)
Devnet listeners bind dual-stack, so nodes advertised the host's **real global
IPv6** as dial info. Peers connected via it — **bypassing ipspoof entirely** —
and all ~23 processes on the host share one IPv6 /56, i.e. one address-filter
rate bucket (128 connections/min). Connection storms tripped it and stalled new
connections until the 60s window drained. Fixed idiomatically with 0.5.7's
first-class `core.network.address_types = ["IPV4"]`. Also killed the phantom
relay selection (IPv6 in the requirement set with no IPv6 dial info).

### Finding 2 — dispatcher head-of-line blocking (app `a2a8221`) ⭐
**The long-standing "cold route" stall was our bug, not Veilid's.**
`dispatch_veilid_update` awaited each AppCall handler to completion before
sending `app_call_reply` — but handlers make *nested* app_calls (challenge →
reveal → key transfer), and each side's answer could only be produced by the
other side's dispatcher, which was blocked in its own nested send. Both nodes
stalled for exactly the 20s retry budget, then everything burst-delivered at
once (the "simultaneous heal", duplicate floods, `Unmatched operation id`
errors). Diagnosed by tracing one op id across nodes: delivered in 1ms, replied
23s later. AppCall processing is now spawned per update (safe: out-of-order and
duplicate delivery were already the handler contract). The Feb 2026
reveal-triggered-resend hardening had been papering over this the whole time —
including `make demo`'s "first key transfer times out, resend delivers"
signature.

### Finding 3 — verification refetched the DHT (app `85db016`)
Exposed by Finding 2: with verification now running ~10ms after MPC (instead of
~20s later on a quiet network), the seller's `verify_winner_reveal` failed
spuriously and withheld the key — it was refetching the winner's commitment
from the live DHT mid-churn. Structurally wrong regardless: the reveal must
open the commitment the MPC actually *consumed*. The winner's commitment is now
snapshotted from the MPC-input BidIndex into `VerificationState`; verification
is DHT-free (which also closes a post-MPC record-rewrite TOCTOU hole).

## 4. Idiomatic-Veilid adoption (Phase 5a–5e)

- **(a) `max_concurrent_operations`** — evaluated, deliberately **not** set:
  audit shows zero concurrent DHT fan-out in the market (all sequential awaits),
  so the default of 16 cannot be reached. Re-adding hand-tuned config we just
  deleted would be anti-idiomatic.
- **(b) `flush_dht_record`** (app `001a84f`) — adopted at the two shared write
  choke points, closing the announce-then-fetch race against 0.5.7's offline
  subkey writes. Zero-cost when nothing is pending; measured no regression.
- **(c) HPKE design spike** (app `c852230`, investigate-only) —
  `market/tests/hpke_spike.rs` proves the VLD0 ed25519→x25519 bridge works with
  the market's existing `ed25519-dalek` identities: seal a content key to
  `BidRecord.signing_pubkey`, open with the signing secret; non-recipient and
  wrong-AAD both fail. Design note in ROADMAP 5c — production adoption would
  replace the plaintext key transfer payload with a sealed blob (defense in
  depth + offline-winner delivery), pending sign-off.
- **(d) Attachment telemetry** (app `152f887`) — reliable peer count, estimated
  network size, and median latency from the richer 0.5.7
  `VeilidUpdate::Attachment` now shown in the status UI and logs.
- **(e) Workaround removal** (evidence-based, one candidate per full-suite run):
  - *Post-barrier route refresh*: **removed** (app `7be35f8`) — it dated from
    when the readiness barrier took 30–120s and routes died during it; the
    barrier now completes in seconds. −90 LoC, best suite time (284.9s).
  - *Fork patch `f2d3b461`* (route-cache panics): **superseded upstream** —
    0.5.4 redesigned the hop cache to refcount duplicate hop sets; our patch
    content is entirely absent from the merged tree. Nothing to remove.
  - *Reactive route-death refresh*: **kept deliberately** — it's a correctness
    mechanism for real route churn; devnet evidence structurally can't justify
    removing it.
  - *Fresh-devnet-per-test*: **kept — removal fails hard.** A shared-devnet
    trial made the concurrent test time out at 720s (stale market-node routing
    entries across tests, exactly as the original comment said).
- **(f) DHT transactions** — deferred with reasons: single-writer records plus
  an app-level lock already serialize the only RMW race; transactions would add
  API surface without closing a real gap.
- **(g) Speedup pass** — the suite halved (see headline numbers); residual
  route_exchange ~14s is polling/barrier cadence with diminishing returns.

## 5. Ops / infra knowledge worth keeping

- **veilid-core log filtering**: tracing targets are *facility names* (`rpc`,
  `net`, `rtab`, `stor`…), not crate names. `RUST_LOG=veilid_core=debug` does
  nothing; `RUST_LOG=info,rpc=debug,net=debug,rtab=debug` works. `rpc_message`
  debug lines carry op ids — grep one across nodes to trace question/answer.
- **Diagnostic pattern for devnet genesis issues**: launch one extra node with
  `-l debug`, grep `stage:` for the inbound state machine
  (NeedsDialInfoConfirmation → NeedsRelays → ReadyToPublish). strace shows
  127.0.0.1, not 1.2.3.x — ipspoof rewrites before the syscall.
- **Principle (now in project memory): never block the update dispatch path on
  anything that awaits a peer's reply.** Any handler that inlines a nested
  app_call reintroduces the mutual-stall bug silently.
- MP-SPDZ still builds against vendored Boost 1.91.0 (never system Boost).

## 6. Publication material accumulated (Phase 6, routes not yet chosen)

- **Track A (upstream patches)**: the genesis-deadlock 4-patch series is a
  coherent contribution ("support fully-static/isolated network bootstrap")
  with the playground as its repro harness. Upstream's stale `limit_*` docs are
  a bonus docs patch. The `d68c16b8`/`f2d3b461` supersession tests remain to
  run.
- **Track D/E (MPC / P2P research)**: before/after transport numbers, the
  dispatcher HOL-blocking case study (an anonymous-routing-layer application
  protocol anti-pattern), MASCOT-over-private-routes characterization
  (~188 rounds, 37MB/party, 4.7s wall on warm routes).
- **Track B (community tooling)**: playground + ipspoof are now 0.5.7-native
  ("local Veilid devnet without Docker").

## Commit index

| Where | SHA | What |
|---|---|---|
| fork | `19d2c0f7` | merge upstream v0.5.7 |
| fork | `fb8380f1` | playground: drop obsolete `limit_*` set_configs |
| fork | `b979a4f9` | genesis 1: static dial info confirms peerlessly |
| fork | `fac1a4d8` | genesis 2: BOOT v0 pre-publication fallback |
| fork | `1c3655b4` | genesis 3: relay requirements scoped to own transports |
| fork | `b6c3fb2f` | genesis 4: Direct-class exempt from translation relay |
| fork | `f68bec29` | playground: min_peer_count removal, ws.connect=false, APPM |
| fork | `0af0ac69` | playground: IPv4-only devnet (address filter fix) |
| app | `00bb773` | build against 0.5.7 |
| app | `cb88483` | clippy 1.95 baseline + loser-key IPC footgun fix |
| app | `8796968` | devnet: disable outbound WS |
| app | `7fca3a1` | devnet: IPv4 only |
| app | `a2a8221` | ⭐ never block dispatcher on AppCall handlers |
| app | `85db016` | verify reveal against MPC-input commitment snapshot |
| app | `001a84f` | flush DHT records after critical writes |
| app | `c852230` | HPKE design spike (ignored test) |
| app | `152f887` | 0.5.7 attachment telemetry in UI/logs |
