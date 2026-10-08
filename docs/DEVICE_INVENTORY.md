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
| Public test iPhone | Not yet provided | Need model, OS, installation/provisioning access |
| Responder test iPad or alternative endpoint | Not yet provided | Need model, OS, installation/provisioning access |
| Test environment | Not yet provided | Need permission for a non-emergency indoor drill and basic topology |

These observations verify tool availability only. They do not prove that an app builds, signing is configured, phones are connected, or local transport works. No device identifiers, serial numbers, or signing credentials are included.

Next: complete the physical endpoint inventory, then run [NET-01](TODO.md#net-01--select-the-baseline-local-transport). An alternate responder device requires an explicit supported-role/transport decision rather than an assumption that an iPhone/iPad/laptop combination interoperates.
