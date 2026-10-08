#ifndef PROBE_WIRE_H
#define PROBE_WIRE_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Fixed synthetic frame only. No strings, location, keys, or user content. */
enum { PROBE_FRAME_SIZE = 24, PROBE_ID_SIZE = 16 };
int probe_encode(uint8_t kind, const uint8_t *id, uint8_t *output, size_t size);
int probe_decode(const uint8_t *input, size_t size, uint8_t *kind, uint8_t *id);
#ifdef __cplusplus
}
#endif
#endif
