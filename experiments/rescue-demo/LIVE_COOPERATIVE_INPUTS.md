# Live cooperative input checkpoint — 2026-10-09

Optional workspace: Setup → Automatic floor research → Live Wi-Fi + phone inputs. Shared by both rescue audiences. This connects foreground native inputs to the research graph; it is not a measured UW positioning system.

## Implemented boundary

- Explicit connected-network capture via `NEHotspotNetwork.fetchCurrent`: precise location authorization plus Access Wi-Fi Information signing capability. SSID/BSSID stay in memory on that device, expire as snapshots and are never transmitted or saved. No general AP scan, RSSI, AP coordinates or SSID-to-floor shortcut. Missing permission/capability/provider and deadline produce Unavailable.
- Foreground optional Apple logical floor and calibrated relative-altitude candidates retain original observation IDs and monotonic sample times. Fresh conflicting local sensors produce Unknown and are not shared. Calibration needs a known starting level and measured spacing; automatic absolute indoor floor without reference is not established.
- Independent in-memory opposite-role research identities and manually checked complete fingerprints. Explicit encrypted challenge-bound pulls use the existing signed HPKE envelope primitive on separate `_rescue-floor._tcp` discovery. Canonical domain-tagged JSON is bounded to 1024 bytes. No rescue keys/history changes, observation forwarding, automatic polling or persistence.
- Replies contain only the sender's original local sensor reading, source and UUID. Remote uptime is never sent or compared. Original age plus the entire measured round trip must be ≤10 seconds, round trip ≤3 seconds; age continues increasing locally. Authentication verifies the pinned sender, not sensor truth.
- Local readings become sensor references at node 1; paired readings become references at node 2 and a contact edge. Contact adds no same-floor constraint. Wi-Fi is contextual until a surveyed reference map exists. Peer-only evidence cannot locate node 1; derived graph estimates are never fed back as original sensor readings.
- Start/stop are explicit; stop, leave and background fence pending work and clear readings. Entering this workspace stops rescue endpoint networking without clearing its identity or saved histories. Restart does not auto-start research.

## Verification

Fresh full `swift test --package-path experiments/workflow-model --scratch-path /private/tmp/rescue-live-wifi-swift --no-parallel`: **153 Swift Testing + 6 XCTest pass**. Includes real loopback encrypted peers, correct signed hostile responses, stale/future age, wrong challenge/context/identity, replay, oversized/malformed/canonical encoding, stop/reset during pulls, source consistency, Wi-Fi permission/timeout/late callback and graph contact/conflict/expiry isolation. Full parallel load exposed an existing listener readiness timeout and Wi-Fi timeout scheduling race; callback now checks the absolute deadline independently and the full nonparallel run passes. No test rules were weakened.

`ctest --test-dir /private/tmp/rescue-graph-cmake --output-on-failure`: **53/53 sanitizer checks pass**. Signed `xcodebuild` for existing Rescue Location Check iPad Simulator succeeds. Computer Use inspected rendered live research, missing-floor Unknown, unavailable location permission, Wi-Fi permission-denied state, pairing/share disabled without checked participant, graph Unknown, Stop/Clear and background/return with sensors still stopped. Saved public/responder histories remain three entries with reported Floor 4. This is Simulator/UI and loopback evidence, not physical sensing, Bonjour/radio or provisioning evidence.

Implementation and independent review use explicit Claude Opus 5.5 medium; model metadata must be checked before recording a review result. Device signing capability still requires a real matching development-team profile. Simulator entitlement/build success does not verify a device profile.

## Next user involvement

Home first: install on two compatible physical devices, verify development signing/permissions, then encrypted request/receipt/ack/reply over controlled Wi-Fi without WAN; separately test no-shared-AP reachability. Three devices are needed for actual relay trials. Floor trials need supported sensors and independently recorded levels/spacing. No beacons are required. Hardware availability/model remains unconfirmed; ask when installation is the next step, not on every local checkpoint.

Bothell next: one accessible repeatable building, labeled stationary/stairs/elevator routes, baseline-versus-cooperative comparisons and mapping feasibility. Seattle follows as a separate evaluation site. Campus roaming/one SSID never supplies a floor map. Physical accuracy, measurable cooperative benefit, RSSI/ranging and UW reference mapping remain open; LOC-01 is not complete. See [roadmap](../../docs/UW_LOCALIZATION_ROADMAP.md) and [physical protocol](../../docs/PHYSICAL_TEST_PLAN.md).

Independent read-only review verified canonical model `claude-opus-5-5` with medium effort. It found a screen-clock freshness flicker (fixed by evaluating at current uptime), missing native Unknown replies (running sensor unavailability now sends an explicit level-less original status), ambiguous edited context (active configured context is shown) and unclear rescue-network stop wording (made explicit). Device-profile capability remains a physical signing gate. No core protocol/security defect was reported; tests/build were independently run by the parent, not inferred from reviewer output.
