#include "ProbeWire.h"
#include <array>
#include <cstring>

int probe_encode(uint8_t kind, const uint8_t *id, uint8_t *output, size_t size) {
    if ((kind != 1 && kind != 2) || !id || !output || size != PROBE_FRAME_SIZE) return 0;
    std::array<uint8_t, PROBE_FRAME_SIZE> frame{'O','R','P','1',kind,0,0,0};
    std::memcpy(frame.data() + 8, id, PROBE_ID_SIZE);
    std::memcpy(output, frame.data(), frame.size());
    return 1;
}
int probe_decode(const uint8_t *input, size_t size, uint8_t *kind, uint8_t *id) {
    if (!input || !kind || !id || size != PROBE_FRAME_SIZE) return 0;
    if (std::memcmp(input, "ORP1", 4) || (input[4] != 1 && input[4] != 2)
        || input[5] || input[6] || input[7]) return 0;
    const auto decodedKind = input[4];
    std::array<uint8_t, PROBE_ID_SIZE> decodedID{};
    std::memcpy(decodedID.data(), input + 8, decodedID.size());
    std::memcpy(id, decodedID.data(), decodedID.size());
    *kind = decodedKind;
    return 1;
}
