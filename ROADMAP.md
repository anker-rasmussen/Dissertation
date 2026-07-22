# Roadmap: Veilid 0.5.7 Upgrade & Codebase Strengthening

Long-running tracker for upgrading the Veilid fork from upstream v0.5.3 to **v0.5.7** and
modernizing the market codebase. Updated every working session; each phase lands as its own
commit set with green build/tests before the next begins.

**End goal:** a codebase strong enough to publish from. Candidate routes (pick 1–2, not ranked):
**(A)** patches upstream to core Veilid devs · **(B)** Veilid community release (playground/ipspoof)
· **(C)** general-public write-up · **(D)** MPC research community publication · **(E)** P2P
research community publication. See [Publication notes](#publication-notes).

## Guiding principles

- **Idiomatic Veilid**: prefer the newest first-class APIs (0.5.4–0.5.7) over patterns inherited
  from 0.5.2/0.5.3-era limitations. When touching a subsystem, check whether a modern API covers
  what we hand-rolled — migrate deliberately, one change per commit, measured against E2E.
- **Evidence-based change**: workarounds are removed only when E2E (3/3, equal-or-better timing)
  proves them unnecessary. Devnet failures are code bugs, never "flakiness".
- **Pinned toolchain**: MP-SPDZ builds against the **vendored Boost 1.91.0**, never system/PATH
  Boost. Never "fix" an MP-SPDZ build by pointing it at system boost.
- **Standing constraints**: MPC traffic only via Veilid private routes; no
  `SafetySelection::Unsafe`; no `footgun-nodeid-target`; `app_call` over `app_message`;
  E2E sequential (`--test-threads=1`); one active private route per node.
- **Git hygiene**: push submodules (veilid, dissertationapp) before bumping parent pointers.
  Logical, semantic commits.

## Baseline (Phase 0)

| Item | Value |
|---|---|
| Parent repo | `bcbda37` |
| dissertationapp | `2f56b32` (master) |
| veilid fork | `583edabd` (main, = upstream v0.5.3 merge + local patches) |
| MP-SPDZ | `14a5d571` (pinned, vendored Boost 1.91.0) |
| Rust toolchain | 1.95.0 (0.5.7 MSRV: 1.89 ✓) |
| clippy/fmt | clean at `cb88483` (repaired for clippy 1.95: test exemptions + ~17 lint fixes) |
| unit/integration tests | 224 passed, 0 failed |
| E2E happy path | **116.2s** (2026-07-19, playground devnet, was 169s in Mar) |
| E2E concurrent | **207.8s** (was 284s) |
| E2E sequential | **263.4s** (was 380s) |

## Phases

### Phase 0 — Preflight, baseline, this doc
- [x] Commit uncommitted work as logical units (app: 2 commits; veilid fork: 2 commits)
- [x] Repoint stale local `master` in dissertationapp onto mainline (pre-rewrite pointer, no merge-base with origin/master)
- [x] Create ROADMAP.md
- [x] Record clippy/fmt/test baseline (market crate) — required repair: clippy 1.95 broke the old
  baseline (test-code unwrap exemption removed + stricter lints); fixed in `cb88483`, including
  a footgun fix (loser-key IPC errors now fail tests loudly instead of reading as "no key")
- [x] Record E2E baseline timings: 3/3 PASS — seq 263.4s / conc 207.8s / happy 116.2s
- [x] Commit parent pointer bumps + ROADMAP.md

### Phase 1 — Fork upgrade: merge upstream v0.5.7
- [x] Add upstream remote (`gitlab.com/veilid/veilid`), fetch tag `v0.5.7` (= `f5cdcca3`)
- [x] Merge dry-run (`git merge-tree`): only **2 conflicts** — `Cargo.lock` (regenerate) and
  `bucket_entry.rs` modify/delete (upstream split it into `bucket_entry/` module).
  Everything else auto-merges, including ipspoof/playground/BOOT-v0/route-cache patches.
- [x] Merged as `19d2c0f7` (2026-07-19). Conflicts as predicted: Cargo.lock regenerated;
  `bucket_entry.rs` deletion accepted (ping-span patch dropped with it).
- [x] Per-patch disposition:
  - [x] `a59bb1b3` recursion_limit CI fix → dropped (superseded upstream 0.5.4)
  - [x] `f2d3b461` route-cache panic→graceful → kept (auto-merged), re-evaluate in 5e
  - [x] `d68c16b8` BOOT v0 self-PeerInfo → kept (auto-merged); with/without supersession test
    still pending → moved to Phase 6 track A prep
  - [x] `07587551` devnet ping span → dropped (mechanism removed upstream). Equivalent knob if
    devnet convergence regresses: `UNRELIABLE_ANSWER_SPAN` (60s) in `bucket_entry/state_reason.rs:30`
  - [x] `ecb1ade8` playground limits → superseded; `set_config` calls removed in `fb8380f1`
  - [x] `ipspoof/` + `playground/` crates → clean auto-merge
- [x] Verified: fork workspace `cargo check` green; `cargo test -p veilid-core --lib` **25/25 pass**
  (incl. 0.5.7 HPKE known-answer tests + attachment manager); market compiled immediately after

### Phase 2 — Playground/devnet repair
- [x] Investigated (pre-merge, via v0.5.7 source): attachment limits are no longer config at all —
  0.5.7 computes attachment level adaptively (`attachment_manager/attachment_level_calculator.rs`,
  `SATURATION_TARGET_RELIABLE_NODES = 32`, latency-penalty tiers). The old high-limit hack is
  obsolete for 20-node devnets (all peers fit under saturation target). `doc/config/sample.config`
  upstream still lists `limit_*` — stale docs (candidate upstream docs patch, track A).
  veilid-server warns-and-ignores unknown/moved `--set-config` keys (settings.rs:1198) — playground
  won't hard-fail, but the calls must go.
- [x] Removed `limit_*` `set_config` calls from playground (`fb8380f1`); binaries rebuilt at 0.5.7
- [x] 20-node devnet → all attach + bootstrap converges (2026-07-20, after Phase 2b patches;
  E2E setup gate: 20/20 reachable in 5.1s); escalate 100/254 only if needed for benchmarks.
- [ ] If large-N tuning is ever needed: `core.internal.*` paths exist, honored only when
  veilid-server is built with `footgun-settings` (→ `veilid-core/footgun-config`); devnet-only, never production
- [x] Keep `detect_address_changes=false` (verified in 0.5.7 node logs: "Manually-disabled
  detection of PublicInternet address changes")
- [x] Validate `--set-config` parser accepts our syntax (empirical: all keys applied at 0.5.7;
  note removed/moved keys now hard-fail rather than warn — see Phase 2b min_peer_count)
- [x] Re-validate ipspoof LD_PRELOAD hooks vs 0.5.4 "dynamic source binding" (empirical: 20-node
  mesh forms over 1.2.3.x, full E2E suite passes)
- [x] Verify: `make demo` completes an auction (2026-07-20: 3-node auto-auction, MPC +
  commitment verification + decryption key delivered to winning bidder; first key transfer
  timed out at 20s, reveal-triggered resend delivered — designed retry path)

### Phase 3 — Market compile fix
- [x] Done in `00bb773` (folded into Phase 1 gate — market must compile post-merge). Actual
  breakage beyond predictions: `VeilidConfigRPC.timeout_ms`, `VeilidConfigDHT` timeouts,
  `VeilidConfigTCP/WS.max_connections`, `VeilidConfigUDP.socket_pool_size` all moved internal
  (dropped — public block collapsed to `VeilidConfigNetwork::default()`); ed25519-dalek
  `rand_core` feature no longer unified in transitively (now explicit in Cargo.toml);
  `RouteBlob` newly `#[must_use]` (one intentional drop annotated).
  `Bare*`/`AppCall`/`RouteChange`/DHT signatures: unchanged, compiled clean.
- [x] Dead plumbing removed: `limit_over_attached` + `rpc_timeout_ms` chains
  (config.rs, node.rs, e2e smoke.rs)
- [x] **Watch-item for Phase 4**: rpc timeout back to 10s default (was 5s tuned for faster
  dead-route detection in MPC tunnel) — check dead-route retry behavior in timings
- [x] Verified: clippy `-D warnings` 0 errors, fmt clean, 224/224 tests

### Phase 2b — 0.5.7 devnet genesis deadlock (found 2026-07-19/20, root-caused via strace + debug logs)
First 0.5.7 E2E run: 3/3 FAIL, uniform ~97s — "Devnet not reachable within 90 seconds".
A fresh isolated network cannot form at 0.5.7. **Four interlocking chicken-and-egg gates**
(each verified empirically; upstream design assumes an established public network exists):
1. **Static dial info requires live peers to confirm**: `confirm_dial_info.rs` gates publication
   on ≥5 live connectivity-capable peers (`EXTERNAL_INFO_VALIDATIONS`) even for fully-static
   config, and empty discovery (all-static) returns failure. `network_state.rs` even documents
   the intended static bypass — never implemented. → **Fork patch 1** (`b979a4f9`): fully-static
   nodes confirm without live peers; static-only skips discovery, derives address types statically.
2. **BOOT v0 returns `[]` before publication**: verified with strace — request arrives, reply is
   `[]` because `get_published_peer_info` is None on a fresh bootstrap. → **Fork patch 2**
   (`fac1a4d8`, extends d68c16b8): fall back to current *unpublished* PeerInfo when it has
   confirmed dial info.
3. **Relay requirements unsatisfiable in devnet**: `relay_requirements.rs` demands relay coverage
   for ALL transports (WS/WSS/IPv6 included). A UDP/TCP/IPv4-only devnet can never satisfy this
   → every node stuck `inbound=NeedsRelays` → publish never happens even after bootstrap works
   (verified: bootstrap succeeded in ~5ms via patches 1+2, but mesh never grew). → **Fork patch 3**
   (`1c3655b4`): scope requirement set to the node's `address_types` × `outbound_protocols`; plus
   devnet config sets `ws.connect=false` (playground `f68bec29` + market node.rs `8796968`) so the
   scope equals static coverage.
4. **Translated addresses demand relays even for Direct-class dial info**: ipspoof's 1.2.3.x
   addresses aren't interface addresses, so 0.5.7 classifies them as NAT-translated and demands a
   relay for the address type regardless of dial info class — still `NeedsRelays` after patch 3.
   → **Fork patch 4** (`b6c3fb2f`): Direct class (confirmed/static full inbound reachability)
   exempt from the translation-driven relay requirement.
- Also fixed: `--set-config core.network.dht.min_peer_count` hard-fails at 0.5.7 (moved to
  core.internal) — removed from playground (it killed all nodes at spawn; the "97s" root cause).
- Also: playground no longer strips connectivity capabilities from the bootstrap node
  (0.5.7 gates on them). Both in `f68bec29`.
- **Verified 2026-07-20**: fresh 20-node devnet with all four patches — every node bootstraps
  exactly once (7–138ms, no retry cycling); E2E setup gate reports **20/20 reachable in 5.1s**
  (was: timeout at 90s).
- **Track A gold**: the genesis deadlock + four patches is a coherent upstream contribution
  ("support fully-static/isolated network bootstrap"), with a repro harness (playground).

### Phase 4 — E2E revalidation + timing comparison
- [x] 3 E2E tests sequentially on repaired devnet (2026-07-20): **3/3 PASS**, suite 573.3s

  | Test | 0.5.3 baseline | 0.5.7 | Δ |
  |---|---|---|---|
  | sequential | 263.4s | **215.5s** | −18.2% |
  | concurrent | 207.8s | **210.3s** | +1.2% (flat) |
  | happy path | 116.2s | **142.3s** | +22.5% (regression) |
  | devnet setup gate | ~90s timeout-prone | **5.1s** | genesis patches |

- [x] Expectation partially met: sequential (heaviest MPC reuse of routes) benefits most from
  0.5.4–0.5.7 route work; happy path regressed — single-auction cold-route cost apparently
  moved, not removed. Candidate causes to profile in Phase 5g: rpc timeout back at 10s default
  (was 5s tuned — the Phase 3 watch-item), relay-compiler startup work, route optimizer warmup.
  - **5g correction (2026-07-20)**: rpc-timeout suspect **eliminated**. 0.5.7 internal defaults
    (`VeilidConfigInternalRPC.timeout_ms = 5000`, DHT get/set/resolve = 10000) are byte-identical
    to our old tuned values (5s rpc, 2× for DHT). Effective timeouts unchanged across the
    migration. Also: isolated happy-path re-run = **110.2s** (better than the 116.2s 0.5.3
    baseline) — the in-suite 142.3s appears to be a suite-ordering effect (runs 3rd), not
    intrinsic 0.5.7 cost. See Phase 5g findings.
- [x] No ConnectionManager deadlock symptoms under connect storms
- [x] Gate: 3/3 green → Phase 5 unlocked

### Phase 5 — Incremental strengthening (each sub-phase = own commit, idiomatic-Veilid pass)
- [x] **(a)** `max_concurrent_operations` — **evaluated, deliberately not set** (2026-07-22).
  Phase 3 removed the whole `VeilidConfigDHT` block; 0.5.7 default is 16. Code audit: zero
  concurrent fan-out in any market DHT path (no join/FuturesUnordered/buffer_unordered in
  dht.rs/registry.rs/bid_ops.rs/mpc_routes.rs — all sequential awaits, ≤ ~6 in-flight ops
  worst-case across an auction). The limit cannot be reached; re-adding hand-tuned config
  we just deleted would be anti-idiomatic. Revisit only if a fan-out path is introduced.
- [x] **(b)** `flush_dht_record` after critical writes — adopted at the two shared write
  choke points (`set_value_at_subkey`, `read_modify_write_subkey` in dht.rs), covering bid
  records, listings, registry RMW, and route blobs. Closes the announce-then-fetch race
  against 0.5.7 offline subkey writes; zero-cost when nothing pending, bounded 10s + WARN
  otherwise (non-fatal: locally durable + background retry + reader retry loops).
  Measured: happy path 72.3s (best yet), zero flush warnings. App `001a84f`.
- [x] **(c)** **HPKE design spike — done, investigate-only (no production code)**.
  Proof: `market/tests/hpke_spike.rs` (`cargo test --test hpke_spike -- --ignored`, passes
  in 40ms) — seller derives an x25519 KEM encapsulation key from the winner's *published*
  ed25519 `BidRecord.signing_pubkey` via `encapsulation_key_from_signing_key`, seals a
  32-byte AES-256-GCM content key with `hpke_seal` (AAD = listing key); winner opens with
  `decapsulation_key_from_signing_secret` from its existing signing secret. Negative cases
  verified: non-recipient cannot open; mismatched AAD cannot open.
  **Design if adopted** (needs sign-off): keep AES-256-GCM as content cipher (content.rs
  unchanged); replace the plaintext-over-private-route `DecryptionHashTransfer` payload with
  the HPKE-sealed blob, AAD = listing record key. Benefits: key transfer no longer relies
  solely on route confidentiality (defense in depth), sealed blob is safe to persist/resend
  via DHT (an offline-winner delivery path the current design can't do), sealer-cannot-open
  property removes the seller's ability to later prove which key it delivered. Costs:
  +~100 bytes payload, HPKE dependency on the app protocol, and the reveal-triggered resend
  path must carry the sealed blob. No further work without user sign-off.
- [x] **(d)** Richer `VeilidUpdate::Attachment` — reliable peer count, estimated network
  size, and median latency now in NodeState, the attachment log line, and the Network
  Status card. App `152f887`.
- [x] **(e)** Route-workaround simplification — per-candidate verdicts (2026-07-22):
  - **Post-barrier route refresh: REMOVED** (app `7be35f8`). It dated from 30–120s barriers
    killing Phase 1 routes; the barrier now completes in seconds. Phase 3 is re-import +
    reassemble only (−90 LoC, removes the fresh-route churn the refresh itself caused).
    Evidence: suite 3/3 at **284.9s** (best yet; 300.4s with refresh) — seq 109.2 / conc 81.2
    / happy 90.3.
  - **Fork patch `f2d3b461`: SUPERSEDED UPSTREAM** — nothing to remove. The 0.5.4
    optimization pass rewrote the hop cache to refcount duplicate hop sets ("Same public
    key is never permitted; duplicate hop sets are") and the release path logs instead of
    panicking. Our patch content is entirely absent from the merged tree; every green E2E
    since the merge validates it. Track A: not an MR candidate (upstream fixed independently);
    keep as evidence the Feb 2026 diagnosis was correct.
  - **Reactive refresh (`handle_dead_remote_routes` + own-route death detection): KEPT
    deliberately.** It's a correctness mechanism reacting to RouteChange events (which still
    fire in every run), not a timing workaround. Devnet E2E cannot exercise production route
    churn, so the removal protocol structurally cannot produce valid evidence here.
  - **Fresh-devnet-per-test: KEPT — removal definitively fails.** Trial (manual 20-node
    devnet + `E2E_FAST_MODE=1` suite): concurrent auctions **FAILED** (720s timeout), happy
    path passed but at 426s (~5×), suite 1244s. The workaround's rationale (stale market-node
    entries poisoning devnet routing tables across tests) still holds at 0.5.7. The ~10s/test
    restart is cheap insurance.
- [x] **(f)** DHT transactions — **deferred, no gap found** (2026-07-22). The condition
  ("only if (a)–(e) reveal a concurrency gap") was not met: every record has a single
  writer, the one same-record RMW race (BID_ANNOUNCEMENTS) is already serialized by
  `bid_registry_lock`, and the 5a audit found no concurrent DHT fan-out anywhere.
  Answer to NOTES.md's CAS wish: 0.5.7 transactions could replace the app-level lock with
  native begin/command semantics, but they'd add API surface to solve a race we don't have —
  the lock is sufficient for a single-process writer. Reconsider only if multiple
  processes ever write one record (e.g. multi-seller shared registries).
- [x] **(g)** E2E speedup pass (user-requested) — **done; suite halved+**. Final numbers
  (2026-07-22, after Findings 1–3 + 5b flush + 5e post-barrier removal):

  | Measurement | 0.5.3 baseline | Final | Δ |
  |---|---|---|---|
  | happy path (instrumented) | 116.2s | **67.2s** | −42% |
  | winner-key wait | ~74s (pre-fix) | **35.3s** | −52% |
  | route_exchange phase | 26.8–29.8s | **13.3–19.4s** | ~−45% |
  | auction_complete | 35–58s | **18.0–24.3s** | ~−50% |
  | full suite | 591.6s | **284.9s** | −52% |

  Residual opportunity (diminishing returns, one-knob-per-run if pursued): route_exchange's
  remaining ~14s is route collection polling + MpcReady barrier cadence
  (`MPC_SYN_ACK_ROUND_SECS=5` rounds, barrier poll 1s) plus party auction-end skew;
  the 15s fixed auction duration and ~16s teardown are test-design constants, not tunables.
  Feb 2026 caution stands: sleep reductions previously caused 849 route errors.

  **5g findings (2026-07-20, isolated happy-path profiling run, 110.2s total, PASS):**

  | Segment | Wall time | Notes |
  |---|---|---|
  | node spawn → ready → routes ready | ~14s | bootstrap 27–31ms/node |
  | create listing + place bids | ~4s | |
  | auction duration | 15s | fixed by test design |
  | **route_exchange (post-auction barrier)** | **~30s** | BENCH 26.8–29.8s across parties |
  | MASCOT MPC | **4.65s** | 188 rounds, 37MB/party — tunnel healthy |
  | verification logic itself | <150ms | challenge→reveal→verify→key |
  | **app_call reply retry storm** | **~23s** | see anomaly below |
  | teardown | ~16s | |

  - **The dominant pathology (~53s of 110s recoverable): app_call replies are lost while
    forward delivery works.** Every post-MPC message (WinnerDecryptionRequest, WinnerBidReveal,
    DecryptionHashTransfer) is *received in ~1ms* (receiver handler logs receipt) but the
    sender's `app_call` times out (5s), retries every ~6s, and remote routes churn dead
    (`dead_remote_routes` every ~5s). All three send loops hit their 20s overall deadlines at
    21:29:00 — and at that same moment the reply path heals for everyone simultaneously
    ("sent successfully via MPC route"); the reveal-triggered resend fallback delivers the key.
    Same signature as the `make demo` first-transfer timeout. The route_exchange 30s likely
    shares the mechanism (route-blob broadcasts also timed out: "Broadcast failed for all
    2 route blobs"; announcements only landed ~26s after auction end).
  - This is probably NOT a 0.5.7 regression — the Feb 2026 hardening (reveal-triggered resend,
    route death recovery) was built against exactly this cold-route pathology at 0.5.2/0.5.3.
    0.5.7's route work didn't fix it for our topology. Fixing the root cause is the single
    biggest E2E speedup available (~half the happy-path wall time).
  - **Finding 1 (2026-07-21, real defect but NOT the reply-loss cause): IPv6 leak through
    ipspoof + shared address-filter bucket.** Debug rerun showed `WARN net: Address filter rate exceeded:
    2a01:...:ffff` (host's real global IPv6 /56) on all three market nodes, starting *during*
    route_exchange. `ss` polling during a run confirmed: market-headless processes hold
    ESTABLISHED TCP connections to the host's real global IPv6 on ports 5150–5169 (the devnet
    nodes). Mechanism: playground binds listen_address `":port"` (unspecified → dual-stack),
    so devnet nodes enumerate real interfaces and advertise the host's global IPv6 as dial
    info; peers connect via it, **bypassing ipspoof** (only 1.2.3.x is rewritten); every node
    shares the host's single IPv6 /56 → one shared `max_connection_frequency_per_min=128`
    bucket (`address_filter.rs`) → connection storms trip it → all new v6 connections rejected
    → replies/broadcasts stall until the 60s window drains (the "simultaneous heal" at ~20s+).
    Also explains the phantom relay: address_types includes IPV6 with no IPv6 dial info →
    patch-3-scoped relay requirement demands IPV6 coverage → bootstrap selected as relay.
    Likely the same mechanism behind the pre-0.5.7 cold-route pathology (Feb 2026 hardening
    era) — the address filter predates 0.5.7.
  - **Fix (one knob)**: 0.5.7 first-class `VeilidConfigNetwork.address_types = ["IPV4"]`
    (idiomatic — public config, not footgun): playground main.rs set_config + market node.rs
    devnet block. Verified wired end-to-end in veilid-core (`configured_address_type_set` →
    `make_address_config` → family_global/binds/interface dial info).
  - IPv6 fix landed (fork `0af0ac69`, app `7fca3a1`) and verified (0 rate warnings, no relay,
    0 v6 devnet connections via `ss` polling) — but the ~20s stall persisted unchanged (110.2s,
    key after 74.2s), so it was a co-occurring defect, not the reply-loss cause.
  - **Finding 2 (2026-07-21): THE root cause — mutual dispatcher head-of-line blocking
    (app-side bug, ours).** Facility-filtered veilid-core debug run (`RUST_LOG=info,rpc=debug,
    net=debug,rtab=debug` — veilid_log targets are facilities `rpc`/`net`/`rtab`, not crate
    names) traced one challenge op end-to-end: sent 09:01.234 → received by winner 09:01.235
    (1ms) → winner's `app_call_reply` only at 09:24 → `RPCError: Ignore(Unmatched operation
    id)` (veilid's answer window long expired). `dispatch_veilid_update` awaited
    `process_app_call` to completion before replying, and handlers perform *nested* app_calls
    with 20s retry budgets (challenge handler sends reveal; reveal handler sends key transfer).
    Each side's answer can only be produced by the other side's dispatcher — which is blocked
    in its own nested send. Both nodes stall for exactly the retry budget, then all queued
    updates burst-deliver ("simultaneous heal", duplicate storms, unmatched-op-id replies).
    The Feb 2026 reveal-triggered-resend hardening was unknowingly papering over this: it fires
    precisely when the budgets expire. Explains `make demo`'s "first key transfer times out,
    resend delivers" too.
  - Approaches considered: (a) reply-first-then-send — rewrite handlers to compute the semantic
    response, reply, then do nested sends; minimal per-handler change but every future blocking
    handler silently reintroduces the bug, and it required changing 3 handler contracts.
    (b) spawn AppCall processing per update — dispatcher never blocks; requires out-of-order +
    duplicate tolerance, which is already the handler contract (MPC tunnel reorders by explicit
    per-stream seq in `deliver_ordered`; auction handlers observed idempotent under the storm's
    duplicate floods; CRDT G-Set is merge-safe by design). (c) outbound-send actor/queue —
    handlers enqueue sends instead of awaiting; most plumbing, orchestrator coupling.
    **Chose (b)**: one contained change in `dispatch_veilid_update` (AppCall arm spawns;
    AppMessage/RouteChange stay inline and serialized). Landed as app `a2a8221`.
  - **Fix verified (isolated happy path)**: 110.2s → **83.2s** (−28% vs the 0.5.3 baseline
    116.2s); winner-key wait 74.2s → **42.7s**; retry storm gone (0 send-failed warnings);
    route_exchange 26.8–29.8s → **17.6–20.7s**; auction_complete 35–58s → **22.7–26.8s**.
    One benign late-reply Unmatched-op-id remains pre-auction (watch item).
    Remaining happy-path budget: 15s fixed auction duration + ~20s route_exchange + ~5s MPC —
    route_exchange is now the top 5g target.
  - **Full suite with both fixes (2026-07-21): 3/3 PASS, 300.4s — the suite halved.**

    | Test | 0.5.3 baseline | 0.5.7 pre-fix | 0.5.7 fixed | Δ vs baseline |
    |---|---|---|---|---|
    | sequential | 263.4s | 215.5s | **119.8s** | **−54.5%** |
    | concurrent | 207.8s | 210.3s | **95.3s** | **−54.1%** |
    | happy path | 116.2s | 142.3s | **81.2s** | **−30.1%** |
    | suite total | 591.6s | 573.3s | **300.4s** | **−49.2%** |

    Sequential/concurrent gained most: every auction in them paid the 20s stall.
    The in-suite vs isolated happy-path discrepancy is gone (81.2s vs 83.2s) — it was the
    dispatcher stall interacting with suite state, not test ordering.
  - **Finding 3 (2026-07-21, exposed by the timing change): verification refetched commitments
    from the live DHT.** First post-fix `make demo`: winner (bid 95) challenged, accepted,
    revealed — seller's `verify_winner_reveal` FAILED in 9ms and withheld the key. The check
    refetched BID_ANNOUNCEMENTS + the winner's BidRecord from DHT (`force_refresh=true`)
    at verification time; with the dispatcher fix this now runs ~10ms after MPC end (mid
    connection churn) instead of ~20s later on a quiet network — any fetch miss = spurious
    FAIL + key withheld. Structurally wrong regardless of flakiness: the reveal must open the
    commitment the MPC actually *consumed* (BidIndex snapshot), not whatever the DHT currently
    says — refetching was also a TOCTOU hole (bidder could rewrite their record post-MPC).
    **Fix**: `VerificationState.winner_commitment` snapshot captured from the MPC-input
    BidIndex in `handle_seller_mpc_result`; `verify_winner_reveal` is now DHT-free and logs
    which sub-check failed. Landed as app `85db016`. Demo rerun: challenge → reveal → verify →
    key delivered in **25ms** (was 20+s via the timeout/resend path). E2E suite re-run below.

### Phase 6 — Publication track (gated on Phases 1–4 green; user picks 1–2 of A–E)
- [ ] Accumulate material per route in [Publication notes](#publication-notes)
- [ ] A: MR candidates = surviving fork patches (`d68c16b8`, `f2d3b461`) with repro evidence
- [ ] B: playground + ipspoof as standalone "local Veilid devnet without Docker" tool; README/announcement scope
- [ ] C: build-a-private-auction-on-Veilid narrative
- [ ] D: MPC-over-anonymous-routes transport characterization (Phase 4 before/after data is the kernel)
- [ ] E: private-route behavior under sustained load (route death, refresh strategies, 5e measurements)

### Phase 7 — Docs & memory
- [ ] Update `Dissertation/NOTES.md` ("Current State (Veilid 0.5.2)" §, CAS discussion)
- [ ] Update project memory: SHAs, timing deltas, patch dispositions, new constraints

## Publication notes

_Measurements and observations accumulate here per route until 1–2 routes are chosen._

- **A (upstream patches)**: the genesis-deadlock 4-patch series (`b979a4f9`/`fac1a4d8`/
  `1c3655b4`/`b6c3fb2f`) = "support fully-static/isolated network bootstrap", playground as
  repro harness. Bonus docs patch: upstream `sample.config` still lists removed `limit_*`.
  `f2d3b461` resolved: superseded by upstream's 0.5.4 hop-cache refcount redesign (not an MR
  candidate; validates the Feb 2026 diagnosis). `d68c16b8` folded into `fac1a4d8` (patch 2).
- **B (community tooling)**: playground + ipspoof now 0.5.7-native; IPv4-only lesson
  (dual-stack listeners leak the host's real IPv6 past LD_PRELOAD spoofing) is a good
  "gotchas" section for a release write-up.
- **C (general public)**: the dispatcher HOL-blocking story arcs well — "we blamed the
  anonymity network for 5 months; it was 12 lines of ours".
- **D (MPC community)**: MASCOT-over-private-routes at 0.5.7: ~188 rounds, 37MB/party,
  4.7s wall warm; auction end-to-end 18–24s including route setup. Before/after transport
  numbers in Phase 4 + 5g tables.
- **E (P2P community)**: the HOL-blocking case study generalizes: request/reply application
  protocols over anonymous routing layers must never block their dispatch loop on nested
  calls — the failure mode (mutual stall for exactly the retry budget, then burst heal)
  masquerades as network flakiness. Plus: address-filter interactions with shared-host
  testbeds; workaround-removal evidence log (5e).

## Session log

- **2026-07-19** — Plan researched & approved. Verified: fork = v0.5.3 + patches (stale fork tags
  make `git describe` misleading); v0.5.7 breaking surface identified (`limit_*` config fields
  gone; `Sequencing`/`Attachment` usage unaffected); HPKE/`flush_dht_record`/
  `max_concurrent_operations` adoption candidates confirmed present. Phase 0 started: preflight
  commits landed (app 718d62e+2f56b32, fork 8245b546+583edabd), stale app `master` repointed,
  ROADMAP.md created.
- **2026-07-19/20** — Phases 1–4 landed. Merged v0.5.7 (`19d2c0f7`), market compiles at 0.5.7
  (`00bb773`), clippy-1.95 baseline repair (`cb88483`). Root-caused + fixed the **genesis
  deadlock** (Phase 2b): four fork patches `b979a4f9`/`fac1a4d8`/`1c3655b4`/`b6c3fb2f` +
  playground `f68bec29` + market `8796968`. Devnet: 20/20 reachable in 5.1s. E2E **3/3 PASS**
  (573.3s suite): sequential −18%, concurrent flat, happy path +22% (profiling target for 5g).
  Fork pushed (`f68bec29` verified on remote).
- **2026-07-20 (later)** — Phase 5g profiling started. Isolated happy path = 110.2s (beats
  0.5.3 baseline); rpc-timeout suspect eliminated (0.5.7 internal defaults == old tuned values);
  root pathology identified: app_call reply loss with instant forward delivery (~53s recoverable
  per run). Details under Phase 5g.
- **2026-07-21** — Phase 5g root causes found & fixed. Finding 1: devnet IPv6 leak bypassing
  ipspoof into a shared address-filter rate bucket → `address_types=["IPV4"]` (fork `0af0ac69`,
  app `7fca3a1`). Finding 2 (THE cause): mutual dispatcher head-of-line blocking — inline
  AppCall handling serialized peers against each other for the full 20s retry budget → spawn
  AppCall processing (app `a2a8221`). E2E suite **halved**: 573.3s → 300.4s, 3/3 PASS
  (seq 119.8s / conc 95.3s / happy 81.2s). Feb 2026 resend-hardening was masking this bug.
  Finding 3 (exposed by 2): winner verification refetched commitments from live DHT → spurious
  FAIL + key withheld in demo; now verifies against the MPC-input BidIndex snapshot
  (app `85db016`). Re-verified: demo key delivery in 25ms end-to-end; E2E suite 3/3 (332.0s).
  All pushed: fork `0af0ac69`, app `85db016`, refs verified.
- **2026-07-22** — Phase 5 completed (a–g) + Phase 7. 5a evaluated-not-set; 5b flush at write
  choke points (`001a84f`); 5c HPKE spike proven (`c852230`); 5d attachment telemetry
  (`152f887`); 5e verdicts: post-barrier refresh REMOVED (`7be35f8`, suite 284.9s best),
  `f2d3b461` superseded upstream, reactive refresh + fresh-devnet-per-test KEPT (shared-devnet
  trial failed hard: conc 720s timeout); 5f deferred (no concurrency gap). Final: happy path
  **67.2s** (−42% vs 0.5.3), suite **284.9s** (−52%). `UPGRADE-0.5.7-SUMMARY.md` written for
  user perusal. NOTES.md + memory updated. Remaining: Phase 6 route choice (user decision).
