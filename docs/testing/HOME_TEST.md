# First home session

Status: preparation only; no physical result yet. Run this before any Bothell visit. No beacons, campus access or three-device relay setup are needed for the first session.

## When the user steps in

The next hardware step needs the iPhone and a second compatible Apple device physically available, plus the Mac for initial installation. The project requires iOS/iPadOS 18 or later; the older iPad's model/OS is still unconfirmed. A device listed as unavailable by Xcode is not a connected test endpoint. Do not buy equipment before checking what is available.

The user handles unlocking, device trust, Apple account sign-in, development-team selection and any Developer Mode prompts. We can then inspect build/install errors together. Do not send credentials, device identifiers or provisioning profiles to chat or the repository.

Open `experiments/rescue-demo/iOS/RescueDemo.xcodeproj` and use scheme `RescueDemo`. Select the physical device and a valid development team under Signing & Capabilities. For the full RescueDemo build, the profile must support Access Wi-Fi Information. The free-account RescuePersonal scheme below omits that optional capability. Do not remove the entitlement or disable signing to report a successful physical install. If that capability cannot be provisioned, use the separately scoped RescuePersonal build; record Wi-Fi context capture as unavailable. No account purchase is assumed.

Apple references, checked 2026-10-09: [physical device workflow](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices), [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device), [Wi-Fi entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.wifi-info). Device signing/install remains unverified even if unsigned device compilation passes.

## Record results locally

Copy the three CSV templates in [templates](templates/) to a new folder under repository-root `private-data/` (ignored by Git). Use anonymous device labels A/B and generic site `home`. Add one session row per device, one messaging row per attempt and one floor row per sampled observation. All template files are header-only: they are not evidence of completed tests. Keep raw logs/screenshots/real network identifiers in that ignored folder too. Do not put physical observation data into sample rescue history or publish it automatically.

Use UTC timestamps with an explicit offset, for example `2026-10-10T18:00:00Z`. Record unavailable values as `unknown`, not zero. Record attempts that fail, are interrupted or are not run. Unknown floor is an estimator outcome, not a failed data row. If an observation ID is not visible, record `unknown`; do not make one up. Connected SSID/BSSID stay on-device in this checkpoint: record only capture available/unavailable, not their values.

## Session order

1. **Install and permissions.** Record each actual model, OS, commit and signed-install result. Verify Local Network behavior and optional location/sensor availability. Do not start by resetting saved histories. Set one public role and one responder role in Secure exchange and manually compare complete pairing fingerprints on the devices.
2. **Ordinary local network.** Start direct exchange explicitly on both devices. Send a synthetic SOS. Record destination device receipt, then separately perform human acknowledgment and reply. Keep the original request intact. Do not count Training mode as physical communication.
3. **Controlled Wi-Fi without WAN.** On an access point you control, disconnect WAN and make cellular internet unavailable on the participants while retaining Wi-Fi. Independently check internet unavailability. Repeat the request/receipt/ack/reply. Record the actual method and outcome; never alter campus infrastructure.
4. **Recovery.** Interrupt contact, queue a synthetic correction, stop/restart, explicitly reconnect and inspect recovery without duplicate requests. Test background/lock behavior as a stopped session; do not expect automatic delivery. Keep initial delivery and retries as separate rows.
5. **Research workspace.** Stop rescue exchange and open Setup → Automatic floor research → Live Wi-Fi + phone inputs. Start optional sensors. Capture connected-network context explicitly; unavailable is valid. On both devices select opposite research roles, use a matching context, exchange the independent research public cards and compare full fingerprints. Pair and start sharing explicitly, then request an observation. These research cards are separate from rescue cards; peers do not automatically determine your floor.
6. **Stop and expiry.** Wait more than ten seconds without refreshing a peer observation and check that it expires to Unknown. Stop/clear, leave or background; return and confirm nothing automatically resumes. Sensor estimates and research observations must not alter the reported SOS floor/history.

The no-shared-access-point experiment is a separate optional attempt after the controlled-LAN baseline; see [full physical protocol](../PHYSICAL_TEST_PLAN.md). Record failure as a result. Two devices cannot establish relay forwarding or a measured radio range.

## Floor sampling, if a safe known route is available

Start stationary on an independently known level. Record how signs map to logical ground=0. For relative altitude, measure the actual spacing and wait for the UI to permit stable calibration. Do not use guessed spacing, an estimated level as ground truth, or your own entered labels as evidence of automatic detection. Record Apple-floor, relative-altitude, local graph and peer-reported results separately, including source/age and Unknown. Stop if the route is inaccessible; a multi-floor home is not required for the messaging session.

This session establishes installation and basic behavior. It does not establish Wi-Fi localization accuracy, cooperative improvement or campus readiness. The current Wi-Fi capture has no floor map, and contact edges have no floor constraint. A full matched ablation evaluation requires an additional survey/replay workflow; the live screen does not implement a Wi-Fi classifier. Bothell is the first repeatable campus building trial, Seattle a later independent evaluation.

## Exit record

Mark each attempted case pass/fail/incomplete with a reason and evidence path. Record remaining signing/device/sensor/network blockers. Before planning Bothell, confirm that the two-device no-internet exchange was actually observed and choose one accessible building with independent floor labels. Keep LOC-01 open until measured data supports it.

## Free-account installation configuration

Use scheme **RescuePersonal** (configuration `PersonalDebug`, bundle `com.archiips.rescue.personal`) for the first free-account device test. It keeps normal development signing, encrypted networking and sensor research, but omits Access Wi-Fi Information and visibly disables connected-network capture. The original Debug/Release Wi-Fi-capable build remains available. Select your own development team locally; no paid membership is required for this bounded setup. This is a separate app sandbox and pairing identity; do not treat its history as the full build's history.

2026-10-09: signed PersonalDebug arm64 build passed and device installation succeeded on the connected iPhone 17. Launch was refused by iOS with a generic code-signature/entitlement/profile-trust security message. Installation is verified; successful launch, Keychain operation and physical communication are not yet verified. User must inspect the on-device prompt/trust state; do not claim this as a working physical exchange.
