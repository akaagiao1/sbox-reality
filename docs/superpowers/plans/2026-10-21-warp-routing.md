# WARP Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add reusable Cloudflare WARP credentials and MetaCubeX geosite based selective routing to `install.sh`, with interactive and standalone update commands.

**Architecture:** Keep all runtime logic in `install.sh` under `warp_` functions, as approved in the spec. Build and validate credentials and sing-box JSON in temporary files, then atomically install the configuration and roll back both configuration and credentials if the service cannot restart.

**Tech Stack:** Bash, jq, curl, OpenSSL X25519, sing-box 1.14+ WireGuard endpoints, shell integration tests.

**Spec:** `docs/superpowers/specs/2026-10-21-warp-routing-design.md`

## Global Constraints

- Runtime code remains in `install.sh`; do not add a sourced production module.
- Only MetaCubeX `sing/geo-lite/geosite/<name>.srs` rules are accepted.
- Managed tags are `sbox-warp-out`, `sbox-warp-direct`, and `sbox-warp-geosite-*`.
- Use `engage.cloudflareclient.com:2408`, peer public key `bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=`, MTU `1280`, and allowed IPs `0.0.0.0/0` plus `::/0`.
- Store credentials at `/etc/sing-box/sbox-warp-credentials.json` with mode `600` and never print the private key.
- Preserve Debian, Ubuntu, and Alpine support and existing protocol install behavior.
- Do not create a real Cloudflare device in automated tests.
- Preserve the current uncommitted backup, atomic-write, checksum, validation, and legacy-wrapper fixes.

## Review Focus

- Mixed separators, repeated names, case variants, empty tokens, and path-like rule names must normalize deterministically or fail before network access; Task 1 tests these inputs.
- A configuration whose direct outbound has no tag must still download rules through the managed `sbox-warp-direct`; Task 3 tests this existing default shape.
- User objects that resemble a managed tag must be rejected unless they match the expected managed structure; Task 3 tests endpoint, outbound, and rule-set conflicts.
- Reset or first registration followed by configuration or service failure must leave the old credential and configuration pair active; Task 4 tests both failure stages.
- Standalone actions, combined protocol installation, restore, partial uninstall, full uninstall, and repeated `--warp-off` must choose the correct credential lifecycle; Task 5 tests each action boundary.

---

### Task 1: WARP CLI State and Rule Normalization

**Files:**
- Modify: `install.sh:1-680`
- Create: `tests/test-warp-routing.sh`

**Interfaces:**
- Consumes: existing top-level argument parser and `usage()`.
- Produces: `warp_normalize_rules RAW` printing a compact JSON string array; `warp_validate_cli`; globals `WARP_RULES_INPUT`, `WARP_RULES_EXPLICIT`, `WARP_OFF`, and `WARP_RESET`; a source-safe `main` guard used by later tests.

- [ ] **Step 1: Write failing parsing and normalization tests**

Add shell cases asserting that `YouTube， netflix youtube;open_ai` becomes `["youtube","netflix","open_ai"]`; blank input and `../youtube`, URLs, slashes, or shell metacharacters fail; `--warp-off` conflicts with `--warp-rules` and `--warp-reset`; and sourcing `install.sh` does not execute `main`.

- [ ] **Step 2: Run the focused test and confirm failure**

Run: `bash tests/test-warp-routing.sh normalization`

Expected: FAIL because `warp_normalize_rules` and the source guard do not exist.

- [ ] **Step 3: Implement the CLI state and pure normalizer**

Add the four globals, parse `--warp-rules VALUE`, `--warp-off`, and `--warp-reset`, document them in `usage()`, and implement `warp_normalize_rules RAW`. Keep first occurrence order while lowercasing and deduplicating. Add `if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi` at the end.

- [ ] **Step 4: Add CLI routing tests**

Assert a WARP-only option prevents protocol mode prompting, a combined `--mode anytls --warp-rules youtube` remains an install action, missing `--warp-rules` value fails, and invalid flag combinations fail before root/platform checks.

- [ ] **Step 5: Run Task 1 tests**

Run: `bash tests/test-warp-routing.sh normalization && bash -n install.sh`

Expected: all assertions pass and Bash reports no syntax errors.

- [ ] **Step 6: Commit Task 1**

```bash
git add install.sh tests/test-warp-routing.sh
git commit -m "feat: parse warp routing options"
```

### Task 2: WARP Registration and Credential Validation

**Files:**
- Modify: `install.sh` in the WARP function block added by Task 1
- Modify: `tests/test-warp-routing.sh`

**Interfaces:**
- Consumes: normalized WARP action state from Task 1.
- Produces: `warp_generate_keypair`; `warp_post_registration PUBLIC_KEY RESPONSE_FILE`; `warp_parse_registration_response RESPONSE PRIVATE_KEY PUBLIC_KEY DESTINATION`; `warp_validate_credentials FILE`; `warp_register_credentials DESTINATION`.

- [ ] **Step 1: Write failing credential parser tests**

Use a fixture response with IPv4 `172.16.0.2/32`, IPv6 `2606:4700:110:8765::2/128`, and base64 client ID `AQID`. Assert the credential JSON has schema `1`, address array with those normalized prefixes, `reserved: [1,2,3]`, MTU `1280`, and the fixed peer values. Add failures for missing address, malformed `client_id`, wrong reserved length, and malformed private/public keys.

- [ ] **Step 2: Run the credential test and confirm failure**

Run: `bash tests/test-warp-routing.sh credentials`

Expected: FAIL because credential functions are undefined.

- [ ] **Step 3: Implement parsing and validation**

Implement `warp_parse_registration_response` and `warp_validate_credentials`. Decode `client_id` with GNU or BSD base64 compatibility, require exactly three bytes, normalize the assigned address prefixes to `/32` and `/128`, and write only to the caller's destination.

- [ ] **Step 4: Write failing registration seam tests**

Override `warp_generate_keypair` and `warp_post_registration` inside a test subprocess. Assert `warp_register_credentials` passes the generated public key to the POST seam, writes a valid credential file, propagates HTTP/parse failures, and never writes a partial destination.

- [ ] **Step 5: Implement key generation and Cloudflare POST**

Generate X25519 raw keys using OpenSSL as in the approved upstream reference. POST to `https://api.cloudflareclient.com/v0a2158/reg` with `CF-Client-Version: a-6.11-2223`, bounded timeout/retries, generated serial number, current UTC TOS timestamp, and a temporary response file. Do not log request secrets or credential JSON.

- [ ] **Step 6: Run Task 2 tests**

Run: `bash tests/test-warp-routing.sh credentials && bash -n install.sh`

Expected: success, with no real network request from the tests.

- [ ] **Step 7: Commit Task 2**

```bash
git add install.sh tests/test-warp-routing.sh
git commit -m "feat: register and validate warp credentials"
```

### Task 3: Managed sing-box Configuration Merge

**Files:**
- Modify: `install.sh` in the WARP function block and `write_server_config()`
- Modify: `tests/test-warp-routing.sh`

**Interfaces:**
- Consumes: compact rules JSON from Task 1 and validated credential file from Task 2.
- Produces: `warp_rule_url NAME`; `warp_probe_url URL`; `warp_validate_rule_urls RULES_JSON`; `warp_current_rules CONFIG`; `warp_merge_config INPUT CREDENTIALS RULES_JSON OUTPUT`; `warp_remove_config INPUT OUTPUT`.

- [ ] **Step 1: Write failing generated-object tests**

Starting from the repository's default config shape with an untagged direct outbound, assert merging `youtube,netflix` adds one `sbox-warp-direct` outbound, one `sbox-warp-out` endpoint, two remote binary rule sets using raw MetaCubeX URLs and `download_detour: sbox-warp-direct`, and a leading sniff plus combined route rule. Assert `route.final` and all original objects remain byte-equivalent as JSON values.

- [ ] **Step 2: Run the merge test and confirm failure**

Run: `bash tests/test-warp-routing.sh config`

Expected: FAIL because merge functions are undefined.

- [ ] **Step 3: Implement URL generation, extraction, and merge**

Implement the Task 3 interfaces with jq. `warp_current_rules` derives service names only from valid managed rule sets. Replacement removes the prior managed pair and managed objects, then inserts the new objects. Preserve all unowned arrays and route properties.

- [ ] **Step 4: Add removal and ownership-conflict tests**

Assert `warp_remove_config` removes only managed objects and the exact managed sniff/route pair; a second removal is unchanged and successful. Add fixtures where `sbox-warp-direct`, `sbox-warp-out`, or `sbox-warp-geosite-youtube` is occupied by an unexpected type/shape and assert merge refuses to write output.

- [ ] **Step 5: Add rule probe and sing-box schema tests**

Override `warp_probe_url` to record URLs and simulate one missing rule; assert every normalized name is checked and one failure aborts. Build a fixture with valid dummy credentials and assert `/workspace/.sbox-dev/bin/sing-box check -c GENERATED` succeeds when that binary exists.

- [ ] **Step 6: Run Task 3 tests**

Run: `bash tests/test-warp-routing.sh config && bash -n install.sh`

Expected: all merge, removal, conflict, URL, and schema checks pass.

- [ ] **Step 7: Commit Task 3**

```bash
git add install.sh tests/test-warp-routing.sh
git commit -m "feat: merge managed warp routing config"
```

### Task 4: Atomic Standalone WARP Actions and Rollback

**Files:**
- Modify: `install.sh` around path constants, backup helpers, service helpers, and `main()`
- Modify: `tests/test-warp-routing.sh`

**Interfaces:**
- Consumes: registration and JSON merge interfaces from Tasks 2 and 3.
- Produces: `warp_prepare_credentials STAGED_FILE`; `warp_apply_existing`; `warp_disable_existing`; rollback behavior using `SERVER_CONF` and `WARP_CREDENTIALS_FILE`, both overridable before sourcing for tests.

- [ ] **Step 1: Write failing standalone lifecycle tests**

Use a temporary config and credential path. Assert first enable validates URLs, registers once, writes both files mode `600`, and restarts once; a second rules update reuses credentials and does not register; `--warp-reset` stages new credentials; `--warp-off` preserves credentials and is idempotent.

- [ ] **Step 2: Run the lifecycle test and confirm failure**

Run: `bash tests/test-warp-routing.sh transaction`

Expected: FAIL because standalone orchestration is absent.

- [ ] **Step 3: Implement staging and standalone actions**

Make `SERVER_CONF` environment-overridable without changing its default, add `WARP_CREDENTIALS_FILE`, and implement the Task 4 interfaces. Require an existing valid config for standalone enable/reset, validate rule URLs before registration, use `mktemp` files in the destination filesystem, call `run_sing_box check -c`, back up before replacement, install with mode `600`, then restart.

- [ ] **Step 4: Write failing rollback tests**

Assert URL, registration, jq merge, and sing-box check failures leave both formal files unchanged. Simulate a restart failure after replacement and assert both old files are restored and the old service restart is attempted. Assert a failed reset never replaces the old credentials.

- [ ] **Step 5: Implement paired rollback**

Snapshot the exact pre-operation presence and content of both files. On post-replacement failure, restore existing files or remove newly created ones as appropriate, then attempt to restart the previous configuration. Return failure even when rollback succeeds.

- [ ] **Step 6: Run Task 4 tests**

Run: `bash tests/test-warp-routing.sh transaction && bash -n install.sh`

Expected: lifecycle and every failure-injection assertion pass.

- [ ] **Step 7: Commit Task 4**

```bash
git add install.sh tests/test-warp-routing.sh
git commit -m "feat: apply warp updates atomically"
```

### Task 5: Installer, Backup, Uninstall, and Documentation Integration

**Files:**
- Modify: `install.sh` around `backup_existing_files()`, restore helpers, `write_server_config()`, `cleanup_all_sing_box_configs()`, interaction, summary, and `main()`
- Modify: `README.md`
- Modify: `tests/test-warp-routing.sh`

**Interfaces:**
- Consumes: every WARP interface from Tasks 1-4.
- Produces: interactive WARP prompts, combined protocol/WARP installation, credential backup/restore/removal lifecycle, user documentation, and the completed feature.

- [ ] **Step 1: Write failing integration boundary tests**

Assert combined install merges protocol inbounds and WARP objects before one final sing-box check; interactive mode accepts multiple names; backup includes the credential file; restore restores it when present; partial protocol uninstall retains WARP; full uninstall removes it; `--config new` plus WARP creates a fresh selective-routing config. Verify legacy wrappers continue forwarding WARP arguments.

- [ ] **Step 2: Run integration tests and confirm failure**

Run: `bash tests/test-warp-routing.sh integration`

Expected: FAIL at the first missing installer integration.

- [ ] **Step 3: Integrate WARP with install, backup, restore, and uninstall flows**

For normal installs, prepare WARP state after dependencies are available and merge WARP into the same temporary server configuration before its final validation/install. Add the credential path to backup and restore lists, preserve it during partial uninstall and `--warp-off`, and remove it during full sing-box cleanup. Print selected WARP rules without printing keys or assigned addresses.

- [ ] **Step 4: Update README usage and security notes**

Document the four CLI forms, interactive behavior, MetaCubeX geosite source, replacement semantics, managed direct rule downloader, credential reuse/reset/off behavior, and the sensitivity of `/etc/sing-box/sbox-warp-credentials.json`.

- [ ] **Step 5: Run the complete local suite**

Run: `bash tests/test-warp-routing.sh all && bash -n install.sh install-anytls-reality.sh install-hysteria2-surge.sh reality.sh && /workspace/.sbox-dev/bin/sing-box check -c /tmp/sbox-warp-generated-test.json`

Expected: all tests and syntax checks pass; the generated fixture is accepted by sing-box.

- [ ] **Step 6: Run the real ruleset reachability smoke test**

Run: `curl -fsSIL --retry 2 --connect-timeout 10 --max-time 30 https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo-lite/geosite/youtube.srs`

Expected: final HTTP status is `200`.

- [ ] **Step 7: Inspect the final diff for secret leakage and scope**

Run: `git diff --check && git diff --stat && rg -n 'private_key|WARP.*KEY' README.md docs tests install.sh`

Expected: no whitespace errors, no literal live private key, and changes are limited to the approved feature plus the pre-existing fixes.

- [ ] **Step 8: Commit Task 5**

```bash
git add install.sh README.md tests/test-warp-routing.sh docs/superpowers
git commit -m "docs: document selective warp routing"
```
