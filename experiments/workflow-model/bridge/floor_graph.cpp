#include "RescueFloorGraph.h"
#include <cmath>
#include <cstdint>

// Bounded difference-constraint solver. Index 0 is the absolute reference (level 0); indices
// 1...node_count are registered nodes. d[u][v] = w encodes level(v) - level(u) <= w. Global
// research-domain bounds keep every interval finite, but they are NOT a reference: a target is only
// estimated when fresh explicit relative edges connect it to a node with a fresh observation.
// Domain bounds are hard constraints and may narrow an interval to one level at an extreme.
namespace {
constexpr size_t kMaxNodes = 32, kMaxEdges = 64, kMaxObservations = 32;
constexpr double kFreshness = 10.0;
constexpr int kMinLevel = -20, kMaxLevel = 200, kMaxDelta = 220;
constexpr int64_t kInfinity = INT64_C(1) << 40;
constexpr size_t kSize = kMaxNodes + 1;

bool index_of(const uint64_t* nodes, size_t count, uint64_t id, size_t* index) noexcept {
 for(size_t i = 0; i < count; ++i) if(nodes[i] == id) { *index = i + 1; return true; }
 return false;
}
bool same(const rc_graph_observation& a, const rc_graph_observation& b) noexcept {
 return a.node == b.node && a.source == b.source && a.minimum_level == b.minimum_level
  && a.maximum_level == b.maximum_level && a.elapsed == b.elapsed;
}
bool fresh(double elapsed, double now) noexcept {
 const double age = now - elapsed;
 return age >= 0 && age <= kFreshness;
}
void tighten(int64_t (&d)[kSize][kSize], size_t u, size_t v, int64_t w) noexcept {
 if(w < d[u][v]) d[u][v] = w;
}
size_t root(size_t (&parent)[kSize], size_t i) noexcept {
 while(parent[i] != i) i = parent[i] = parent[parent[i]];
 return i;
}
}

rc_graph_reason rc_floor_graph(const uint64_t* nodes, size_t node_count,
    const rc_graph_edge* edges, size_t edge_count,
    const rc_graph_observation* observations, size_t observation_count,
    uint64_t target, double now, rc_graph_result* output) {
 if(!output) return RC_GRAPH_NO_OUTPUT;
 *output = {};
 if(node_count > kMaxNodes || edge_count > kMaxEdges || observation_count > kMaxObservations)
  return RC_GRAPH_LIMIT;
 if((node_count && !nodes) || (edge_count && !edges) || (observation_count && !observations)
  || !std::isfinite(now) || now < 0) return RC_GRAPH_INVALID;

 // Structural validation of every record, fresh or not.
 for(size_t i = 0; i < node_count; ++i) {
  if(nodes[i] == 0) return RC_GRAPH_INVALID;
  for(size_t j = 0; j < i; ++j) if(nodes[j] == nodes[i]) return RC_GRAPH_INVALID;
 }
 size_t target_index = 0;
 if(target == 0 || !index_of(nodes, node_count, target, &target_index)) return RC_GRAPH_INVALID;
 size_t edge_from[kMaxEdges] = {}, edge_to[kMaxEdges] = {};
 for(size_t i = 0; i < edge_count; ++i) {
  const rc_graph_edge& e = edges[i];
  if(!index_of(nodes, node_count, e.from, &edge_from[i]) || !index_of(nodes, node_count, e.to, &edge_to[i])
   || e.from == e.to || !std::isfinite(e.elapsed) || e.elapsed < 0) return RC_GRAPH_INVALID;
  if(e.kind == 0) {
   if(e.minimum_delta != 0 || e.maximum_delta != 0) return RC_GRAPH_INVALID;
  } else if(e.kind == 1) {
   if(e.minimum_delta < -kMaxDelta || e.maximum_delta > kMaxDelta || e.minimum_delta > e.maximum_delta)
    return RC_GRAPH_INVALID;
  } else return RC_GRAPH_INVALID;
 }
 size_t observation_node[kMaxObservations] = {};
 for(size_t i = 0; i < observation_count; ++i) {
  const rc_graph_observation& o = observations[i];
  if(!index_of(nodes, node_count, o.node, &observation_node[i]) || o.origin == 0 || o.observation == 0
   || o.source < 0 || o.source > 2 || o.minimum_level < kMinLevel || o.maximum_level > kMaxLevel
   || o.minimum_level > o.maximum_level || !std::isfinite(o.elapsed) || o.elapsed < 0) return RC_GRAPH_INVALID;
 }

 // Provenance: exact copies collapse; differing content under one origin+ID fails closed, expired or not.
 bool duplicate[kMaxObservations] = {};
 for(size_t i = 0; i < observation_count; ++i) for(size_t j = 0; j < i; ++j) {
  const rc_graph_observation &a = observations[j], &b = observations[i];
  if(a.origin != b.origin || a.observation != b.observation) continue;
  if(!same(a, b)) return RC_GRAPH_CONFLICT;
  duplicate[i] = true;
 }

 // Time filter, then constraints from fresh evidence only.
 const size_t size = node_count + 1;
 int64_t d[kSize][kSize];
 size_t parent[kSize];
 bool referenced[kSize] = {};
 for(size_t u = 0; u < size; ++u) {
  parent[u] = u;
  for(size_t v = 0; v < size; ++v) d[u][v] = u == v ? 0 : kInfinity;
 }
 for(size_t v = 1; v < size; ++v) { tighten(d, 0, v, kMaxLevel); tighten(d, v, 0, -kMinLevel); }
 bool fresh_observation[kMaxObservations] = {};
 size_t skipped = 0;
 for(size_t i = 0; i < edge_count; ++i) {
  const rc_graph_edge& e = edges[i];
  if(!fresh(e.elapsed, now)) { ++skipped; continue; }
  if(e.kind != 1) continue; // contact establishes reachability only, never a floor relation
  tighten(d, edge_from[i], edge_to[i], e.maximum_delta);
  tighten(d, edge_to[i], edge_from[i], -static_cast<int64_t>(e.minimum_delta));
  const size_t a = root(parent, edge_from[i]), b = root(parent, edge_to[i]);
  if(a != b) parent[a < b ? b : a] = a < b ? a : b;
 }
 for(size_t i = 0; i < observation_count; ++i) {
  if(duplicate[i]) continue;
  const rc_graph_observation& o = observations[i];
  if(!fresh(o.elapsed, now)) { ++skipped; continue; }
  fresh_observation[i] = true;
  referenced[observation_node[i]] = true;
  tighten(d, 0, observation_node[i], o.maximum_level);
  tighten(d, observation_node[i], 0, -static_cast<int64_t>(o.minimum_level));
 }
 output->skipped = skipped;

 // All-pairs shortest paths; a negative cycle anywhere is a contradiction.
 for(size_t k = 0; k < size; ++k) for(size_t u = 0; u < size; ++u) {
  if(d[u][k] >= kInfinity) continue;
  for(size_t v = 0; v < size; ++v)
   if(d[k][v] < kInfinity) {
    const int64_t bound = d[u][k] + d[k][v];
    // Stop at the first proved negative cycle. Continuing closure on contradictory inputs can
    // repeatedly amplify negative paths and overflow even a 64-bit table at bounded graph sizes.
    if(u == v && bound < 0) return RC_GRAPH_CONFLICT;
    tighten(d, u, v, bound);
   }
 }
 for(size_t u = 0; u < size; ++u) if(d[u][u] < 0) return RC_GRAPH_CONFLICT;

 // Reference and provenance come only from the target's explicit relative-edge component.
 const size_t component = root(parent, target_index);
 bool connected = false;
 for(size_t v = 1; v < size; ++v) if(referenced[v] && root(parent, v) == component) connected = true;
 if(!connected) return RC_GRAPH_NO_REFERENCE;
 size_t origins = 0;
 for(size_t i = 0; i < observation_count; ++i) {
  if(!fresh_observation[i] || root(parent, observation_node[i]) != component) continue;
  bool seen = false;
  for(size_t j = 0; j < i; ++j)
   if(fresh_observation[j] && root(parent, observation_node[j]) == component
    && observations[j].origin == observations[i].origin) seen = true;
  if(!seen) ++origins;
 }
 const int64_t maximum = d[0][target_index], minimum = -d[target_index][0];
 output->minimum_level = static_cast<int>(minimum);
 output->maximum_level = static_cast<int>(maximum);
 output->origins = origins;
 return minimum == maximum ? RC_GRAPH_CANDIDATE : RC_GRAPH_AMBIGUOUS;
}
