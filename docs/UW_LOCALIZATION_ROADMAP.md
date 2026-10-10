# UW Seattle localization roadmap

User discussion, 2026-10-09. Preserve these ideas for later experimentation; none is a verified positioning capability. One rescue product retains public iPhone and responder iPad interfaces, C++ workflow/storage and Swift platform adapters. UW Seattle is the first proposed research setting, not a confirmed deployment or a restriction of the reusable engine.

## Chosen progression

1. Complete controlled foreground phone relay separately from location work.
2. Build an automatic floor-detection research mode: baseline Core Location, phone motion/relative-altitude signals and iOS-accessible Wi-Fi information. Begin with repeatable labeled routes in one authorized multi-floor UW building, not campus-wide claims.
3. Evaluate cooperative localization: participating phones as moving reference points, graphing recent proximity/ranging and available anchor observations. Compare baseline versus cooperation on held-out routes/devices/days.
4. If measurements show insufficient reliable floor reference evidence, evaluate a small authorized Bluetooth-beacon trial. No hardware purchase or placement is selected or authorized.

Automatic floor detection is an explicit intended milestone. Keep manually reported floor separate from estimated floor, confidence, observation time and provenance. Unknown is a valid output; never overwrite a person's report or label old observations live. The current implemented location feature is optional one-shot coordinates/accuracy/time, not Wi-Fi floor inference.

## Ideas and decisions

- NFC location checkpoints were discussed and rejected by the user because tapping is required.
- Bluetooth beacons are a possible hands-free fallback. Known installed anchors would be needed throughout the promised coverage areas; multiple per floor may be needed. One-per-floor is an experiment, not an established deployment requirement. Signal bleed between floors and walls must be measured. Anchors provide location clues, not SOS forwarding.
- Existing UW Wi-Fi is worth evaluating before installing equipment. Coverage/connectivity alone does not expose reliable building/floor coordinates. Access-point mapping or infrastructure-side location support would require accessible data and potentially UW-IT cooperation; neither is established.
- Nearby phones can be cooperative moving observations only when participating in our app. They are not fixed ground-truth anchors. Do not scan or track arbitrary campus users. Do not broadcast precise locations indiscriminately or give plaintext private bodies to relays.
- Bluetooth signal strength is noisy proximity evidence; detectability does not establish the same floor. UWB Nearby Interaction may contribute distance/direction on supported opted-in devices after exchanging tokens; unavailable readings remain missing evidence.
- A graph of uncertain phones alone cannot establish absolute building/floor. Trusted reference observations and enough geometric constraints are needed; a dense graph is not independent proof. Shared/forwarded measurements must retain origin IDs and timestamps to avoid circular confidence amplification. Avoid treating many correlated bad GPS fixes as independent votes.
- Model nodes as devices/known references and time-stamped edges as contact/proximity/ranging measurements with uncertainty. Treat building layout, known anchors, relative altitude and device observations as separate constraints. Use a transparent probabilistic baseline before considering learned prediction. No AI model is selected.

## Evaluation and decision gates

Measure correct-floor rate, wrong-floor rate, Unknown rate, time to detect transitions, stale-observation handling, battery/foreground limitations and results by stairs/elevator/stationary route. Compare baseline and cooperative methods against independently recorded floors; split sessions/buildings/devices/days to avoid leakage. A method that confidently worsens floor estimates fails even if coverage increases.

First experiment: survey one accessible building and repeat labeled routes with baseline inputs. Cooperative experiment: a small group of opted-in physical phones traverses the same routes, including adjacent floors, no reliable anchors, missing/stale peers and contradictory observations. Expand only after measured benefits; building size alone is not a reason to start campus-wide. Simulator fixtures can verify logic but cannot establish radio, altitude or floor accuracy.

No approved building, access-point inventory, campus API, equipment installation, hardware budget, agency partnership or physical results currently exist. Wi-Fi message reachability, phone-relay delivery and localization accuracy are separate experiments. Continue to work without sensor permission; SOS delivery and human acknowledgment remain separate.

## Primary-source evidence (consulted 2026-10-09)

- [Apple Wi-Fi API overview](https://developer.apple.com/documentation/technotes/tn3111-ios-wifi-api-overview): no general-purpose iOS Wi-Fi scanning API; Core Location uses Wi-Fi among other inputs. Hotspot Helper is not a workaround for positioning.
- [Current Wi-Fi information](https://developer.apple.com/documentation/networkextension/nehotspotnetwork/fetchcurrent(completionhandler:)): connected SSID/BSSID under entitlement/authorization conditions; not a scan of all APs or arbitrary signal strengths.
- [UW Wi-Fi coverage and policy](https://uwconnect.uw.edu/it?id=kb_article_view&sysparm_article=KB0034253): most campus buildings have Wi-Fi; UW-IT manages it and requires written authorization for non-UW-managed Wi-Fi. This does not itself establish the permission rules for Bluetooth placement; obtain the appropriate building/campus authorization before equipment installation.
- [Beacon accuracy](https://developer.apple.com/documentation/corelocation/clbeacon/accuracy): do not treat beacon ranging as a precise beacon location.
- [Nearby Interaction sessions](https://developer.apple.com/documentation/nearbyinteraction/initiating-and-maintaining-a-session): supported devices exchange discovery tokens; distance/direction can be unavailable.
- [Core Bluetooth advertising](https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager/startadvertising(_:)): best-effort and background advertisement restrictions.
- [Phone as iBeacon](https://developer.apple.com/documentation/corelocation/turning-an-ios-device-into-an-ibeacon-device): app must remain foregrounded for that beacon workflow. Custom Bluetooth background behavior is a separate platform-specific question, not a promised capability.

These sources support API constraints, not the hypothesis that the proposed fusion improves UW floor accuracy. That requires the physical comparisons above.
