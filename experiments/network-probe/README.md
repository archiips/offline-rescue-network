# Synthetic Network Probe

Throwaway feasibility tool, **not the rescue app**. Swift handles Apple transport; a C++20 codec with a C ABI accepts only fixed synthetic frames. No third-party packages. No personal data, text input, location, durable queue, responder authentication, encryption, human acknowledgment or relay.

## Run with the iPhone and Mac

From the repository root:

```sh
swift run --package-path experiments/network-probe rescue-probe-host
open experiments/network-probe/iOS/NetworkProbe.xcodeproj
```

In Xcode select the NetworkProbe scheme, your connected iPhone, and your own development team under Signing & Capabilities. Run the app. No signing identity is committed. Allow Local Network on both devices if asked. Keep the host terminal and phone app active. Tap **Find test host**, choose the name printed by the host, and send the fixed frame. A successful screen reports **Synthetic device receipt**. Host names are unverified; this is only a diagnostic.

First use the same Wi-Fi with internet unavailable. Then follow the [no-access-point run sheet](../../docs/NETWORK_PROBE.md#hardware-run-sheet). Wi-Fi must stay enabled. A localhost or same-LAN result does not prove peer-to-peer radio exchange. Repeat permission denial, host loss/restart, retry, phone lock and background/foreground. The probe deliberately stops when the app enters the background. **Host on this device** allows the same app to be tested on an iPad later; it does not make the tablet a verified responder.

If nothing appears, verify permissions, host state and topology. macOS may associate a CLI permission prompt with Terminal/Xcode/the executable; check System Settings → Privacy & Security → Local Network. Record the failure instead of assuming Wi-Fi peer-to-peer is supported. No additional background modes or multicast entitlement are requested by this probe.

## Build and verify

```sh
swift test --package-path experiments/network-probe --scratch-path /private/tmp/rescue-probe-build
xcodebuild -project experiments/network-probe/iOS/NetworkProbe.xcodeproj \
  -scheme NetworkProbe -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/rescue-probe-derived CODE_SIGNING_ALLOWED=NO build
```

The package specifies macOS 14/iOS 18 minimum and C++20. These are build targets, not a verified device-support matrix. Physical iPhone/iPad networking, signing and older-OS runtime behavior still need evidence.

## Wire and resource limits

One 24-byte frame per TCP connection: ASCII `ORP1` (4 bytes), kind (1=request, 2=receipt), three zero reserved bytes, and 16 random correlation bytes. The host echoes only the correlation bytes with kind 2. C++ rejects wrong length/magic/kind/reserved values before modifying outputs. There is no variable body. TCP chunks are accumulated with a 25-byte cap; incomplete/malformed frames fail. An extra byte in the same read rejects the frame; extra bytes arriving after the first frame are ignored. Once the first frame is handled the connection closes; later trailing stream data is never processed as another frame.

Swift uses NWBrowser/NWListener/NWConnection, `_rescue-probe._tcp`, and `includePeerToPeer=true`. This opts into available peer-to-peer technology; it cannot promise a route. Discovery stops before connection. Sessions have an 8-second absolute deadline, maximum 8 concurrent sessions, maximum 20 listed results, 100 in-memory log entries. Stop/restart invalidates old callbacks. Correlation prevents an accidental wrong receipt from counting; an attacker who reads the request can forge it. Plain TCP and Bonjour identities are not trustworthy rescue messaging.

No production C++ domain engine/backend is built here. After transport/security gates, reuse lessons rather than automatically adopting spike code.

## Evidence

See [probe record](../../docs/NETWORK_PROBE.md) and [candidate product security contract](../../docs/PROTOCOL_SECURITY_DRAFT.md). Never use this probe during an emergency or enter private data into it.

Path logs record NWPath interface types and available interface names on both sides. Available interfaces are candidates, not proof of the actual packet interface. Record controlled topology separately; packet-level corroboration may be needed for no-access-point evidence. The session cap is a resource bound, not denial-of-service resistance: eight idle peers can temporarily prevent new sessions.
