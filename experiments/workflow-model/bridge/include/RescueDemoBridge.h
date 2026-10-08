#ifndef RESCUE_DEMO_BRIDGE_H
#define RESCUE_DEMO_BRIDGE_H
#ifdef __cplusplus
extern "C" {
#endif
/* Caller owns each handle; serialize calls and destroy exactly once. Synthetic only. */
typedef struct rc_session rc_session;
enum rc_action { RC_SOS, RC_FOLLOWUP, RC_CORRECTION, RC_WITHDRAWAL, RC_ACKNOWLEDGE,
                 RC_REPLY, RC_ASSIGN, RC_RESOLVE, RC_REOPEN, RC_DISPOSITION };
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
void rc_free(char*);
#ifdef __cplusplus
}
#endif
#endif
