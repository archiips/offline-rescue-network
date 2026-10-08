# Device and development inventory

Status: partial inventory · 2026-10-07 · DISC-02 remains incomplete

| Item | Observed value | Evidence / limitation |
|---|---|---|
| Development operating system | macOS 26.2, build 25C56 | `sw_vers` |
| Development architecture | arm64 | `uname -m` |
| Xcode | 26.4, build 17E192 | `xcodebuild -version` |
| Selected developer directory | `/Applications/Xcode.app/Contents/Developer` | `xcode-select -p` |
| Swift compiler | Apple Swift 6.3 | `xcrun swift --version` |
| Exact Mac model | Not verified | Model query was unavailable in the sandbox; no model assumption made |
| Public test iPhone | iPhone 17; user reports iOS 26, exact minor version unconfirmed | User-reported; installation/provisioning access and physical transport tests remain unverified |
| Responder test iPad or alternative endpoint | Older iPad temporarily unavailable for a few days; model and OS unconfirmed | User-reported; need model, OS, installation/provisioning access |
| Test environment | Not yet provided | Need permission for a non-emergency indoor drill and basic topology |

These observations verify tool availability only. They do not prove that an app builds, signing is configured, phones are connected, or local transport works. No device identifiers, serial numbers, or signing credentials are included.

Next: complete the physical endpoint inventory, then run [NET-01](TODO.md#net-01--select-the-baseline-local-transport). An alternate responder device requires an explicit supported-role/transport decision rather than an assumption that an iPhone/iPad/laptop combination interoperates.

## Compatibility intent

The iPhone 17 is an available test endpoint, not the minimum supported model. The user wants broad support across device generations. D-08's iOS/iPadOS 18 floor remains provisional until NET-01 records the actual device/transport matrix; neither a working newer phone nor an older tablet's availability proves broad compatibility.

The first experiment can use currently installed operating systems. The user mentioned possibly updating the phone to iOS 27; no update or installed version is assumed. Record the exact version for each run and treat a later OS update as a separate test configuration.

To finish the missing inventory, obtain Model Name and operating-system version from each device's Settings → General → About. Serial numbers, IMEI, account details, and device identifiers are unnecessary.

The user authorized preparing an iPhone/Mac synthetic transport probe while the iPad is unavailable. The Mac is a diagnostic host, not a substituted production responder endpoint. See [probe](NETWORK_PROBE.md).
