#include <stddef.h>
#ifndef RESCUE_FLOOR_PROBE_H
#define RESCUE_FLOOR_PROBE_H
#ifdef __cplusplus
extern "C" {
#endif
/* Experimental anchor-relative floor feasibility estimator. Pure, stateless and allocation free; no
   sensors, storage or rescue workflow state. A candidate is an unvalidated logical level (0 = ground),
   not building signage, a probability or a physical accuracy claim. Thresholds are research defaults.
   Times are monotonic session seconds, finite and nonnegative. Altitudes are relative-altimeter metres
   from one session baseline; height is the latest sample minus the anchor altitude. */
typedef struct rc_floor_sample {
    double altitude; /* |altitude| <= 10000 */
    double elapsed;
} rc_floor_sample;
typedef struct rc_floor_anchor {
    int level;           /* known logical level -20...200 */
    double altitude;     /* session altitude captured at elapsed; |altitude| <= 10000 */
    double elapsed;
    double floor_height; /* measured uniform floor height 2...8 metres */
} rc_floor_anchor;
typedef enum rc_floor_reason {
    RC_FLOOR_NO_OUTPUT = -1,       /* null level output; nothing evaluated */
    RC_FLOOR_CANDIDATE = 0,        /* *level holds the unvalidated candidate */
    RC_FLOOR_NO_ANCHOR = 1,
    RC_FLOOR_INVALID_INPUT = 2,    /* nonfinite/negative time, absurd altitude or null samples */
    RC_FLOOR_INVALID_HEIGHT = 3,
    RC_FLOOR_INVALID_LEVEL = 4,
    RC_FLOOR_FUTURE = 5,           /* anchor or sample later than now */
    RC_FLOOR_STALE_ANCHOR = 6,     /* anchor older than 600 seconds */
    RC_FLOOR_TOO_FEW = 7,          /* fewer than 3 samples */
    RC_FLOOR_TOO_MANY = 8,         /* more than 64 samples; samples are never read */
    RC_FLOOR_ANCHOR_AFTER_SAMPLE = 9,
    RC_FLOOR_UNORDERED = 10,       /* elapsed not strictly increasing */
    RC_FLOOR_STALE_SAMPLES = 11,   /* any sample older than 10 seconds */
    RC_FLOOR_SHORT_WINDOW = 12,    /* samples span less than 2 seconds */
    RC_FLOOR_NOISY = 13,           /* window altitude range above 0.35 metres */
    RC_FLOOR_TRANSITION = 14,      /* latest displacement more than 0.2 floors from an integer */
    RC_FLOOR_OUT_OF_RANGE = 15     /* candidate outside -20...200 */
} rc_floor_reason;
/* First failure wins: output; now; anchor presence, values, height, level, future, age; count (too many,
   then too few) before samples is dereferenced, then null samples; sample values, future, before anchor,
   order, age; window span, noise, transition, candidate bounds. *level is set to 0 first and to the
   candidate only on RC_FLOOR_CANDIDATE. Never throws. */
rc_floor_reason rc_floor_relative(const rc_floor_anchor* anchor, const rc_floor_sample* samples, size_t count,
                                  double now, int* level);
#ifdef __cplusplus
}
#endif
#endif
