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
- [ ] Merge `v0.5.7` into fork `main` (merge, not rebase — matches prior v0.5.3 workflow)
- [ ] Per-patch disposition:
  - [ ] `a59bb1b3` recursion_limit CI fix → **drop** (superseded upstream 0.5.4)
  - [ ] `f2d3b461` route-cache panic→graceful → **keep tentatively**, re-evaluate in 5e
  - [ ] `d68c16b8` BOOT v0 self-PeerInfo → **test-gated**: playground bootstrap smoke with/without (0.5.5 fixed direct-reply bootstrap failures); keep only if regression without. Outcome feeds track A.
  - [ ] `07587551` devnet ping span → **drop at merge** (mechanism removed upstream; the
    conflict). Equivalent tuning point at 0.5.7: `UNRELIABLE_ANSWER_SPAN` (60s) in
    `bucket_entry/state_reason.rs:30` — re-apply there as a fresh commit ONLY if Phase 2
    measures slow devnet convergence.
  - [ ] `ecb1ade8` playground limits → defer to Phase 2
  - [x] `ipspoof/` + `playground/` crates → confirmed clean auto-merge in dry-run
- [ ] Regenerate `Cargo.lock` via build (both workspaces — fork and app resolve independently)
- [ ] Verify: fork `cargo build --workspace` + `cargo test -p veilid-core`; **compile market immediately** (catch capnp-0.26/veilid-tools transitive breakage before Phase 3)

### Phase 2 — Playground/devnet repair
- [x] Investigated (pre-merge, via v0.5.7 source): attachment limits are no longer config at all —
  0.5.7 computes attachment level adaptively (`attachment_manager/attachment_level_calculator.rs`,
  `SATURATION_TARGET_RELIABLE_NODES = 32`, latency-penalty tiers). The old high-limit hack is
  obsolete for 20-node devnets (all peers fit under saturation target). `doc/config/sample.config`
  upstream still lists `limit_*` — stale docs (candidate upstream docs patch, track A).
  veilid-server warns-and-ignores unknown/moved `--set-config` keys (settings.rs:1198) — playground
  won't hard-fail, but the calls must go.
- [ ] Remove `limit_*` `set_config` calls from playground; 20-node devnet → all attach + bootstrap
  converges? Escalate 100/254 only if needed for benchmarks.
- [ ] If large-N tuning is ever needed: `core.internal.*` paths exist, honored only when
  veilid-server is built with `footgun-settings` (→ `veilid-core/footgun-config`); devnet-only, never production
- [ ] Keep `detect_address_changes=false` (still valid at 0.5.7)
- [ ] Validate `--set-config` parser accepts our syntax across 4 minor versions
- [ ] Re-validate ipspoof LD_PRELOAD hooks vs 0.5.4 "dynamic source binding" change
- [ ] Verify: 20-node devnet attaches; `make demo` completes an auction

### Phase 3 — Market compile fix
- [ ] `node.rs:179-190`: drop 5 `limit_*` fields from `VeilidConfigRoutingTable` literal
- [ ] Remove dead plumbing: `DevNetConfig.limit_over_attached` (node.rs:41,57),
  `MarketConfig.limit_over_attached` (config.rs:205,294,317) — hardcoded literal never consumed them
  (repurpose instead if Phase 2 found internal tuning is needed)
- [ ] Fix whatever the compiler surfaces (`Bare*` keys, `RouteBlob`, `AppCall`, `RouteChange`,
  DHT signatures — expected clean per exploration)
- [ ] Verify: 4 bins compile; `cargo clippy --all-targets -- -D warnings`; `cargo fmt --check`;
  unit + integration tests green

### Phase 4 — E2E revalidation + timing comparison
- [ ] 3 E2E tests sequentially on repaired devnet; record wall-times vs baseline
- [ ] Expectation: 0.5.4/0.5.7 route work cuts cold-route `app_call` latency (~1.5–2s/round cold)
  that dominates MASCOT's ~188 rounds
- [ ] Watch for behavior change from 0.5.7 ConnectionManager deadlock fix under connect storms
- [ ] Gate: 3/3 green before Phase 5

### Phase 5 — Incremental strengthening (each sub-phase = own commit, idiomatic-Veilid pass)
- [ ] **(a)** `VeilidConfigDHT.max_concurrent_operations` — set/tune (node.rs:173,223), measure
- [ ] **(b)** `flush_dht_record` after critical writes (bid_storage, bid_announcement, registry);
  verify E2E timing doesn't regress
- [ ] **(c)** **HPKE design spike (investigate only — no production code without sign-off)**:
  design note here; prototype key-derivation round-trip (VLD0 signing identity →
  `encapsulation_key_from_signing_key`/`decapsulation_key_from_signing_secret` → seal/open)
  in a throwaway test
- [ ] **(d)** Richer `VeilidUpdate::Attachment` — network-size estimates in UI status/logs
- [ ] **(e)** Route-workaround simplification, evidence-based per candidate (remove on branch,
  full E2E 3/3, equal-or-better timing): post-barrier refresh · reactive refresh ·
  fresh-devnet-per-test · fork patch `f2d3b461`
- [ ] **(f)** Optional: DHT transactions for `read_modify_write_subkey` — only if (a)–(e) reveal
  a concurrency gap (NOTES.md:322 wished for native CAS; transactions may answer it)

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

## Session log

- **2026-07-19** — Plan researched & approved. Verified: fork = v0.5.3 + patches (stale fork tags
  make `git describe` misleading); v0.5.7 breaking surface identified (`limit_*` config fields
  gone; `Sequencing`/`Attachment` usage unaffected); HPKE/`flush_dht_record`/
  `max_concurrent_operations` adoption candidates confirmed present. Phase 0 started: preflight
  commits landed (app 718d62e+2f56b32, fork 8245b546+583edabd), stale app `master` repointed,
  ROADMAP.md created.
