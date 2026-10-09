#include <stddef.h>
#include <stdint.h>
#ifndef RESCUE_RELAY_H
#define RESCUE_RELAY_H
#ifdef __cplusplus
extern "C" {
#endif
/* Experimental local custody queue for opaque sealed packets. Trusted local callers only: no network
   listener, no keys or plaintext, no authenticated routing metadata and no replay defense.
   Caller owns each handle; serialize calls per handle and destroy exactly once. Synthetic only. */
typedef struct rc_relay rc_relay;
typedef enum rc_relay_result {
    RC_RELAY_NULL_HANDLE = -1,
    RC_RELAY_OK = 0,
    RC_RELAY_DUPLICATE = 1, /* same ID and identical immutable fields/payload already retained */
    RC_RELAY_INVALID = 2,
    RC_RELAY_CONFLICT = 5,  /* same ID with any different immutable field or payload */
    RC_RELAY_CAPACITY = 6,  /* 64 items, 273664 payload bytes or admission counter exhausted; no eviction */
    RC_RELAY_STORAGE = 7,   /* lock, validation, save or commit failure; nothing changed */
    RC_RELAY_EMPTY = 8      /* no eligible item, or remove target absent */
} rc_relay_result;
typedef enum rc_relay_urgency { RC_RELAY_ORDINARY = 0, RC_RELAY_URGENT = 1 } rc_relay_urgency;
/* Selected copy. Free with rc_relay_item_free exactly once. */
typedef struct rc_relay_item {
    char id[65];
    char flow[65];
    int urgency;
    int64_t expiry;
    int remaining_hops; /* stored budget minus this forward */
    int attempts;       /* including this selection, 1...8 */
    unsigned char* payload;
    size_t length;
} rc_relay_item;
/* Absolute path <=4096 bytes. Creates an empty queue or opens an exactly validated one; incompatible
   or damaged files are never replaced. Nonempty headers must carry this format before SQLite opens.
   Marked relay files may undergo hot-journal recovery before strict validation. Null on failure. */
rc_relay* rc_relay_open(const char* path);
void rc_relay_destroy(rc_relay*);
/* id/flow: 64 lowercase hex chars. urgency 0/1. expiry: positive logical time later than now.
   hops 1...2. payload 181...4276 bytes. Expired items are pruned first; an expired ID may be reused. */
rc_relay_result rc_relay_enqueue(rc_relay*, const char* id, const char* flow, int urgency, int64_t expiry,
                                 int hops, const unsigned char* payload, size_t length, int64_t now);
/* Oldest unexpired item per flow is its head; a head with 8 attempts blocks its flow. Oldest urgent head
   unless 3 urgent selections occurred in a row and an ordinary head is eligible. Attempts and fairness
   commit before *item is set; on any failure *item is null. */
rc_relay_result rc_relay_select(rc_relay*, int64_t now, rc_relay_item** item);
/* Deletes custody. The caller must already have validated the destination's receipt, or be an
   administrator; the queue verifies no proof. */
rc_relay_result rc_relay_remove(rc_relay*, const char* id);
rc_relay_result rc_relay_count(rc_relay*, size_t* count);
void rc_relay_item_free(rc_relay_item*);
#ifdef __cplusplus
}
#endif
#endif
