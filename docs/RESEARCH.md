# Research and source register

Status: initial evidence baseline, v0.1 · 2026-10-07

The register separates sourced capabilities from design proposals and commercial hypotheses. Sources were consulted during this conversation, with selected platform and validation sources revisited on 2026-10-07. A source's publication date is not its access date. A vendor claim is not an independent performance result.

## Main findings

- Store-carry-forward is an established architecture; proximity does not guarantee an end-to-end path [R02].
- Phone mesh messaging already exists [R07–R09]. Our proposed distinction is the complete assistance workflow and its measured behavior, not the invention of offline chat.
- Indoor responder location is an active research and commercial field [R10–R14]. We have no evidence yet of an unmet customer requirement our system can satisfy better.
- Phone pressure/relative altitude is not a guaranteed labeled floor. The original paper's strong result depends on experimental conditions and building height information [R01, R06].
- Apple platform capabilities vary by API, device, OS, permission, and lifecycle state [R03–R06]. Physical tests are mandatory.

## Sources

### R01

**Predicting floor level for 911 Calls with Neural Networks and Smartphone Sensor Data.** [Paper, v4](https://arxiv.org/html/1710.11122v4), September 15, 2018.

Supports pressure-based relative height plus indoor/outdoor detection as a research direction. The paper reports 65% exact-floor accuracy with a common floor-height assumption and 100% under building-specific conditions in 63 trials. Its distinction between physical floor level and labeled floor number matters. The text is inconsistent about building count; do not turn this study into a universal or structural-fire accuracy claim.

### R02

**Bundle Protocol Version 7.** [IETF RFC 9171](https://www.rfc-editor.org/rfc/rfc9171.html), January 2022.

Standards-track reference for a store-carry-forward overlay under disrupted communication. Useful architectural foundation. Our initial application protocol is not claimed to implement BPv7 or to interoperate with DTN products.

### R03

**Multipeer Connectivity.** [Apple documentation](https://developer.apple.com/documentation/multipeerconnectivity?changes=_3), living documentation.

Supports nearby Apple-device communication. Apple documents that backgrounding stops advertising/browsing and disconnects sessions. Foreground prototyping is plausible; unattended relay capability is not established. Permissions and discovery declarations must be checked during implementation.

### R04

**Wi-Fi Aware.** [Apple framework documentation](https://developer.apple.com/documentation/WiFiAware?changes=__2) and [WWDC25 session](https://developer.apple.com/videos/play/wwdc2025/228/), 2025 introduction / living documentation.

Supports paired peer-to-peer connections on compatible Apple devices. Background connection availability depends on app runtime; it does not confer continuous execution. Pairing, compatible hardware, entitlements, and Android/laptop interoperability need measured validation. Candidate later transport, not automatic stranger discovery.

### R05

**Core Bluetooth background processing.** [Apple programming guide](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html), archived guide; also consult [current advertising API](https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager/startadvertising(_:)).

Background roles have restrictions on discovery/advertising and execution. BLE merits an experiment, not an assumed always-on transport. The archived guide cannot replace current-device tests.

### R06

**Core Motion relative altitude.** [Apple property reference](https://developer.apple.com/documentation/coremotion/cmaltitudedata/relativealtitude?changes=_4), living documentation.

Reports altitude change in meters relative to the first event, not a floor label. Capability and permission checks remain necessary. Document units at the adapter boundary before recording data.

### R07

**Bitchat.** [Official repository](https://github.com/permissionlesstech/bitchat), living implementation.

Documents BLE multi-hop messaging, private encryption, compression, adaptive power behavior, and internet transport. Inspect a pinned revision for future comparisons. Do not infer independently audited security or universal performance from its README.

### R08

**Briar.** [How it works](https://briarproject.org/how-it-works/), living project documentation.

Documents direct synchronization through Bluetooth/Wi-Fi and other transports. Evidence of offline communication capability; not evidence that every private message crosses arbitrary strangers' devices.

### R09

**Bridgefy.** [iOS SDK usage](https://docs.bridgefy.me/sdk/ios/usage), living vendor documentation.

Describes direct, mesh, and broadcast modes. Existing competitor/SDK alternative. License, provisioning, security, platform support, and actual deployment behavior require review before considering adoption.

### R10

**NIST First Responder Smart Tracking Challenge results.** [Announcement](https://www.nist.gov/news-events/news/2024/01/saving-seconds-saving-lives-nist-funded-challenge-crowns-winners-3d), January 9, 2024.

Documents a funded challenge and finalist testing in responder scenarios. Demonstrates investment and existing teams; neither funding nor an award proves our product's adoption case.

### R11

**NIST's continuing indoor tracking evaluation.** [Research update](https://www.nist.gov/blogs/taking-measure/how-thousands-tiny-dots-can-save-first-responders-lives), February 4, 2026.

Describes May 2025 testing against surveyed points and the need for practical wearability, communication, durability, affordability, and evidence. Relevant validation context, not a current grant invitation.

### R12

**MSA LUNAR.** [Manufacturer product description](https://us.msasafety.com/connected-firefighter/lunar?locale=en), living vendor source.

Describes teammate search through an ad-hoc network and distance/direction assistance. This establishes a competitor capability claim, not equivalence to floor estimation or our proposed workflow.

### R13

**FLORIAN.** [Manufacturer](https://3aminnovations.com/) and [official installation instructions](https://support.3aminnovations.com/hc/en-us/articles/37590097920525-How-do-I-install-the-app-on-my-Phone), installation instructions updated July 3, 2025.

Vendor materials describe personnel tracking and incident management; app availability has official installation documentation. The homepage intermittently failed to open during the final refresh. Verify current detailed capabilities before a sales comparison; no pricing or deployment superiority is established here.

### R14

**Ascent Integrated Tech.** [Official product walkthrough](https://ascentitech.com/product-news/product-walkthrough-series-real-time-firefighter-tracking-in-action/), January 29, 2025.

Shows vendor-described responder tracking during training, with wearable integration. Training/replay alone is not a novel category. A direct comparison requires equivalent tests and current product details.

### R15

**Localization test and evaluation.** [NIST testing guidance](https://www.nist.gov/ctl/pscr/testing-indoor-localization-systems), updated March 14, 2024; [Z-axis facility](https://www.nist.gov/news-events/news/2026/05/z-axis-test-facility-improving-indoor-localization-public-safety), May 2026.

Provides test-method context, including ISO/IEC 18305, and a possible future collaboration channel. It is not a certification of this project or guaranteed facility access.

### R16

**Apple device environmental limits.** [Apple support](https://support.apple.com/en-us/118431), living documentation.

States a 0–35°C ambient operating range for iPhones/iPads. Ordinary consumer devices must not be assumed suitable for structural-fire exposure. Equipment suitability depends on the intended deployment and must be evaluated separately.

### R17

**Swift/C++ interoperability.** [Swift reference](https://www.swift.org/documentation/cxx-interop/), living documentation.

Supports mixed-language integration with constraints on imported APIs and lifetime handling. A thin bridge is a design choice, not a platform requirement.

### R18

**Post-disaster prioritization.** [Author-hosted NetSys paper](https://www.kom.tu-darmstadt.de/papers/LRL%2B19.pdf), 2019.

Its evaluated policies show that prioritization can favor outdated information, starve traffic, or respond poorly to changing demand. Motivates freshness, fairness, and baseline comparisons; does not prove our proposed scheduler is better.

### R19

**Smartphone emergency-network field trial.** [Paper](https://arxiv.org/html/1808.04684v1), 2018.

Reports a 125-participant scripted exercise. Movement, obstacles, and grouping affected network behavior. Evidence for realistic tests; its results cannot be generalized to a new iOS implementation.

## Unresolved feasibility questions

| Question | Cheapest useful investigation | Related task |
|---|---|---|
| Do physical devices exchange data without internet or access point? | Prepared two-device transport experiment | NET-01 |
| Does useful forwarding survive lock/background conditions? | Device/OS/lifecycle matrix, including force quit | NET-01, NET-04 |
| Is there a reachable enrolled responder in the intended deployment? | Topology drill plus partner workflow interview | DISC-03, NET-03 |
| Does pressure improve location without an entry reference? | Explicit no-baseline cohort, including unavailable results | LOC-03 |
| Will organizations use both interfaces? | Workflow interview and scripted usability test | DISC-01, UX-01 |
| Is the differentiator worth procurement and support effort? | Alternative comparison, budget-owner interviews, pilot proposal | BIZ-01, BIZ-03 |

## Research practice

Before implementing an external API, review its current official docs and pin the actual development toolchain. Before claiming a competitor gap, compare its current equivalent workflow. Before a pilot, review partner equipment and intended-use requirements. Record dated evidence in the decision register; never fill gaps with vendor marketing or a single tutorial.
