#ifndef RESCUE_FLOOR_GRAPH_H
#define RESCUE_FLOOR_GRAPH_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Synthetic research core only. All times belong to ONE monotonic replay domain; remote raw uptime
   is not a shared clock. Each invocation is one building/session. No confidence or radio accuracy.
   All times must be finite and nonnegative. Self-loop edges are invalid.
   Limits: 32 unique nonzero node IDs, 64 edges, 32 observations; freshness <=10 seconds inclusive.
   Levels -20...200 are hard research-domain constraints, which can narrow intervals at the extremes. Count bounds must be checked before any array read. No allocation/throwing. */
typedef struct rc_graph_edge {
    uint64_t from, to;
    int kind; /* 0 contact only: no floor constraint, min/max MUST be zero; 1 explicit relative level */
    int minimum_delta, maximum_delta; /* level(to)-level(from), each -220...220, min <= max */
    double elapsed;
} rc_graph_edge;
typedef struct rc_graph_observation {
    uint64_t node, origin, observation; /* original provenance; forwarded copies keep origin+ID */
    int source; /* 0 sensor, 1 surveyed Wi-Fi reference, 2 known reference. NOT a derived graph estimate */
    int minimum_level, maximum_level;
    double elapsed;
} rc_graph_observation;
typedef struct rc_graph_result {
    int minimum_level, maximum_level; /* populated only for CANDIDATE/AMBIGUOUS */
    size_t origins; /* distinct contributing origins, NOT independent probability/confidence */
    size_t skipped; /* stale/future edges + stale/future original observations (copies count once).
                       Complete only on CANDIDATE, AMBIGUOUS or NO_REFERENCE. */
} rc_graph_result;
typedef enum rc_graph_reason {
    RC_GRAPH_NO_OUTPUT = -1, RC_GRAPH_CANDIDATE = 0, RC_GRAPH_NO_REFERENCE = 1,
    RC_GRAPH_AMBIGUOUS = 2, RC_GRAPH_CONFLICT = 3, RC_GRAPH_INVALID = 4, RC_GRAPH_LIMIT = 5
} rc_graph_reason;
/* Unknown reasons never produce a single level. Output cleared before validation. Invalid input wins
   over expired evidence: all records are structurally validated first. Exact copies deduplicate;
   different contents with the same original origin+observation ID are CONFLICT even when expired.
   Contradiction anywhere fails this snapshot closed. Fresh contact edges never imply same floor.
   Actual argument buffers must have their declared length; ordinary C pointer contract applies. */
rc_graph_reason rc_floor_graph(const uint64_t* nodes, size_t node_count,
    const rc_graph_edge* edges, size_t edge_count,
    const rc_graph_observation* observations, size_t observation_count,
    uint64_t target, double now, rc_graph_result* output);
#ifdef __cplusplus
}
#endif
#endif
