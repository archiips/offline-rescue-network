#include <stddef.h>
#ifndef RESCUE_DEMO_BRIDGE_H
#define RESCUE_DEMO_BRIDGE_H
#ifdef __cplusplus
extern "C" {
#endif
/* Caller owns each handle; serialize calls and destroy exactly once. Synthetic only. */
typedef struct rc_session rc_session;
enum rc_action { RC_SOS, RC_FOLLOWUP, RC_CORRECTION, RC_WITHDRAWAL, RC_ACKNOWLEDGE,
                 RC_REPLY, RC_ASSIGN, RC_RESOLVE, RC_REOPEN, RC_DISPOSITION };
typedef struct rc_endpoint rc_endpoint;
rc_endpoint* rc_endpoint_open(const char* path, int role);
/* Immutable conversation binding, 1...256 bytes. New stores only; rejects existing
   empty, unbound or differently bound stores. Not encrypted storage or tamper detection. */
rc_endpoint* rc_endpoint_open_bound(const char* path, int role, const char* binding);
void rc_endpoint_destroy(rc_endpoint*);
int rc_endpoint_perform(rc_endpoint*, int action, const char* value, const char* reference);
unsigned char* rc_endpoint_next(const rc_endpoint*, size_t* length);
int rc_endpoint_accept(rc_endpoint*, const unsigned char* packet, size_t length, unsigned char** receipt, size_t* receipt_length);
int rc_endpoint_confirm(rc_endpoint*, const unsigned char* receipt, size_t length);
/* Read-only: exact committed receipt -> original event. Null/length 0 means no match;
   null/length 1 means invalid input/allocation failure. Owned output: rc_free. */
unsigned char* rc_endpoint_confirmed_original(const rc_endpoint*, const unsigned char* receipt, size_t length, size_t* original_length);
char* rc_endpoint_snapshot(const rc_endpoint*);
int rc_endpoint_reset(rc_endpoint*);
/* Packet outputs are owned allocations freed by rc_free. Null next + length 0 means empty.
   accept publishes only after event and return receipt commit; confirm commits outbox removal.
   Result codes match rc_perform. These fixture roles/packets are not authenticated. */
rc_session* rc_create(void);
/* Absolute local path <=4096 bytes; opens validated saved sample state, or creates it.
   Existing corrupt/unsupported data is not replaced. Null on failure; no silent fallback. */
rc_session* rc_open(const char* path);
/* Atomically clears a sample session; 0 success, 7 save failure, -1 invalid handle. */
int rc_reset(rc_session*);
void rc_destroy(rc_session*);
/* 0 accepted, 1 duplicate, 2 invalid, 3 unauthorized, 4 missing dependency, 5 conflict,
   6 full, 7 store failure; -1 bridge failure before acceptance.
   Bridge limits: value <=2048 UTF-8 bytes, reference <=64 bytes; NUL-terminated/non-null.
   Model also bounds combined text/location to 2048 bytes; fixed SOS text uses part of that.
   Transfer failure after local acceptance preserves result 0; snapshot.error explains retry. */
int rc_perform(rc_session*, int action, const char* value, const char* reference);
int rc_set_connected(rc_session*, int connected);
/* New malloc-owned UTF-8 JSON snapshot. Never a transport message. Free with rc_free. */
char* rc_snapshot(const rc_session*);
void rc_free(void*);
#ifdef __cplusplus
}
#endif
#endif
