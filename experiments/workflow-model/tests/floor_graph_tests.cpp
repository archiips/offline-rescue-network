#include "RescueFloorGraph.h"
#include <cassert>
#include <cmath>
#include <limits>
#include <string>
#include <random>
int main(int argc, char** argv) {
 assert(argc == 2);
 const std::string test=argv[1];
 uint64_t nodes[]={1,2,3};
 rc_graph_observation obs[]={{1,10,100,2,2,2,99},{3,11,101,1,4,4,99}};
 rc_graph_edge edges[]={{1,2,1,1,1,99},{2,3,1,1,1,99}};
 rc_graph_result out{};
 auto run=[&](size_t ec=2,size_t oc=2){return rc_floor_graph(nodes,3,edges,ec,obs,oc,2,100,&out);};
 auto reset=[&]{
  obs[0]={1,10,100,2,2,2,99};obs[1]={3,11,101,1,4,4,99};
  edges[0]={1,2,1,1,1,99};edges[1]={2,3,1,1,1,99};
 };
 if(test=="chain") {
  assert(run()==RC_GRAPH_CANDIDATE && out.minimum_level==3 && out.maximum_level==3 && out.origins==2);
  obs[1].minimum_level=5;obs[1].maximum_level=5;
  assert(run()==RC_GRAPH_CONFLICT);
  // Input permutation and an equivalent reversed edge give the same answer.
  reset();
  {rc_graph_observation po[]={obs[1],obs[0]};rc_graph_edge pe[]={{3,2,1,-1,-1,99},edges[0]};uint64_t pn[]={3,1,2};
   assert(rc_floor_graph(pn,3,pe,2,po,2,2,100,&out)==RC_GRAPH_CANDIDATE && out.minimum_level==3 && out.maximum_level==3 && out.origins==2);}
  // Interval references intersect: node2 in [2,3] from node1 and [3,4] from node3.
  obs[0].minimum_level=1;obs[0].maximum_level=2;obs[1].minimum_level=4;obs[1].maximum_level=5;
  assert(run()==RC_GRAPH_CANDIDATE && out.minimum_level==3 && out.maximum_level==3 && out.origins==2);
  // Overlapping but non-singleton intersection stays ambiguous.
  obs[0].minimum_level=2;obs[0].maximum_level=4;obs[1].minimum_level=3;obs[1].maximum_level=5;
  assert(run()==RC_GRAPH_AMBIGUOUS && out.minimum_level==3 && out.maximum_level==4);
  // Research-domain candidate bounds: anchor at 200 plus +1 cannot exist.
  reset();obs[0].minimum_level=200;obs[0].maximum_level=200;
  assert(run(1,1)==RC_GRAPH_CONFLICT && out.minimum_level==0 && out.maximum_level==0);
  // A wide edge is clamped to research-domain bounds but remains a connected (ambiguous) estimate.
  reset();edges[0]={1,2,1,-220,220,99};
  assert(run(1,1)==RC_GRAPH_AMBIGUOUS && out.minimum_level==-20 && out.maximum_level==200 && out.origins==1);
  // Lower research-domain edge: anchor at -20 minus one is impossible.
  reset();obs[0].minimum_level=-20;obs[0].maximum_level=-20;edges[0].minimum_delta=-1;edges[0].maximum_delta=-1;
  assert(run(1,1)==RC_GRAPH_CONFLICT);
  // Target's own reference.
  reset();obs[0].node=2;
  assert(run(0,1)==RC_GRAPH_CANDIDATE && out.minimum_level==2 && out.origins==1);
 } else if(test=="contact") {
  edges[0]={1,2,0,0,0,99};
  assert(run(1,1)==RC_GRAPH_NO_REFERENCE);
  edges[0]={1,2,1,0,1,99};
  assert(run(1,1)==RC_GRAPH_AMBIGUOUS && out.minimum_level==2 && out.maximum_level==3);
  // No edges and no references: global bounds alone are never a reference.
  assert(run(0,0)==RC_GRAPH_NO_REFERENCE && out.minimum_level==0 && out.maximum_level==0 && out.origins==0);
  // Contact to a referenced node never implies same floor, even with references on both sides.
  edges[0]={1,2,0,0,0,99};edges[1]={2,3,0,0,0,99};
  assert(run(2,2)==RC_GRAPH_NO_REFERENCE && out.origins==0);
  // Disconnected reference: target links only to an unreferenced node.
  edges[0]={2,3,1,0,0,99};
  assert(run(1,1)==RC_GRAPH_NO_REFERENCE);
  // Contact edges never count origins: node3 reference reachable only by contact.
  reset();edges[1]={2,3,0,0,0,99};
  assert(run()==RC_GRAPH_CANDIDATE && out.minimum_level==3 && out.origins==1);
  // Contact edge carrying a delta is malformed.
  edges[1]={2,3,0,0,1,99};
  assert(run()==RC_GRAPH_INVALID && out.minimum_level==0 && out.origins==0);
  edges[1]={2,3,0,-1,0,99};
  assert(run()==RC_GRAPH_INVALID);
  // Contradiction in another component still fails the snapshot closed.
  reset();
  {rc_graph_edge other[]={{2,3,1,1,1,99},{3,2,1,0,0,99}};
   assert(rc_floor_graph(nodes,3,other,2,obs,1,1,100,&out)==RC_GRAPH_CONFLICT && out.minimum_level==0);}
 } else if(test=="provenance") {
  obs[1]=obs[0];
  assert(run()==RC_GRAPH_CANDIDATE && out.origins==1);
  obs[1].minimum_level=3;obs[1].maximum_level=3;
  assert(run()==RC_GRAPH_CONFLICT);
  obs[1]=obs[0];obs[1].observation=101;
  assert(run()==RC_GRAPH_CANDIDATE && out.origins==1);
  // Same-origin conflicting copy is a conflict even when both copies are expired.
  obs[0].elapsed=10;obs[1]=obs[0];obs[1].maximum_level=3;
  assert(run()==RC_GRAPH_CONFLICT && out.skipped==0);
  // ... and even when one copy is expired and the other fresh.
  reset();obs[1]=obs[0];obs[1].elapsed=50;
  assert(run()==RC_GRAPH_CONFLICT);
  // Same ID claimed for another node or source is a conflict.
  reset();obs[1]=obs[0];obs[1].node=3;
  assert(run()==RC_GRAPH_CONFLICT);
  reset();obs[1]=obs[0];obs[1].source=1;
  assert(run()==RC_GRAPH_CONFLICT);
  // Same observation ID from a different origin is a distinct record.
  reset();obs[1]=obs[0];obs[1].origin=11;
  assert(run()==RC_GRAPH_CANDIDATE && out.origins==2);
  // Invalid input wins over a provenance conflict regardless of order.
  reset();obs[1]=obs[0];obs[1].maximum_level=3;edges[1].to=99;
  assert(run()==RC_GRAPH_INVALID);
  {rc_graph_observation po[]={obs[1],obs[0]};
   rc_graph_edge pe[]={edges[1],edges[0]};
   assert(rc_floor_graph(nodes,3,pe,2,po,2,2,100,&out)==RC_GRAPH_INVALID);}
  // Only fresh references in the target's relative component count as origins.
  reset();obs[1].elapsed=80;
  assert(run()==RC_GRAPH_CANDIDATE && out.origins==1 && out.skipped==1);
  // Three copies, two exact, one same origin new ID: still one origin, no inflation.
  reset();
  {rc_graph_observation po[]={obs[0],obs[0],{1,10,102,0,2,2,98}};
   assert(rc_floor_graph(nodes,3,edges,2,po,3,2,100,&out)==RC_GRAPH_CANDIDATE && out.origins==1 && out.minimum_level==3);}
 } else if(test=="time") {
  obs[0].elapsed=89;obs[1].elapsed=101;
  assert(run()==RC_GRAPH_NO_REFERENCE && out.skipped==2);
  obs[0].elapsed=90;
  assert(run()==RC_GRAPH_CANDIDATE && out.minimum_level==3 && out.skipped==1);
  edges[0].elapsed=89;
  assert(run(1,1)==RC_GRAPH_NO_REFERENCE);
  // Inclusive at now; just-future and just-stale edges are skipped.
  reset();obs[0].elapsed=100;edges[0].elapsed=100;
  assert(run(1,1)==RC_GRAPH_CANDIDATE && out.skipped==0);
  edges[0].elapsed=std::nextafter(100.0,200.0);
  assert(run(1,1)==RC_GRAPH_NO_REFERENCE && out.skipped==1);
  edges[0].elapsed=std::nextafter(90.0,0.0);
  assert(run(1,1)==RC_GRAPH_NO_REFERENCE && out.skipped==1);
  // Stale contact edges are counted as skipped too.
  reset();edges[1]={2,3,0,0,0,10};
  assert(run()==RC_GRAPH_CANDIDATE && out.skipped==1 && out.origins==1);
  // Stale contradictory edge does not constrain.
  reset();edges[1]={2,1,1,0,0,50};
  assert(run(2,1)==RC_GRAPH_CANDIDATE && out.minimum_level==3 && out.skipped==1);
  // Non-finite times are invalid, not merely stale.
  reset();obs[0].elapsed=-INFINITY;
  assert(run()==RC_GRAPH_INVALID && out.skipped==0);
  reset();edges[1].elapsed=NAN;
  assert(run()==RC_GRAPH_INVALID);
  reset();obs[1].elapsed=INFINITY;
  assert(run()==RC_GRAPH_INVALID);
 } else if(test=="abi") {
  assert(rc_floor_graph(nullptr,33,nullptr,0,nullptr,0,1,100,&out)==RC_GRAPH_LIMIT);
  assert(rc_floor_graph(nullptr,0,nullptr,0,nullptr,0,1,100,nullptr)==RC_GRAPH_NO_OUTPUT);
  assert(rc_floor_graph(nodes,3,nullptr,1,obs,2,2,100,&out)==RC_GRAPH_INVALID);
  assert(rc_floor_graph(nodes,3,edges,2,obs,2,2,NAN,&out)==RC_GRAPH_INVALID);
  assert(rc_floor_graph(nodes,3,edges,std::numeric_limits<size_t>::max(),obs,2,2,100,&out)==RC_GRAPH_LIMIT);
  nodes[2]=2;assert(run()==RC_GRAPH_INVALID);
  nodes[2]=3;
  // Output cleared before validation.
  out={7,7,7,7};
  assert(rc_floor_graph(nodes,3,edges,65,obs,2,2,100,&out)==RC_GRAPH_LIMIT && out.minimum_level==0 && out.maximum_level==0 && out.origins==0 && out.skipped==0);
  assert(rc_floor_graph(nodes,3,edges,2,nullptr,33,2,100,&out)==RC_GRAPH_LIMIT);
  assert(rc_floor_graph(nodes,3,edges,2,obs,std::numeric_limits<size_t>::max(),2,100,&out)==RC_GRAPH_LIMIT);
  assert(rc_floor_graph(nullptr,3,edges,2,obs,2,2,100,&out)==RC_GRAPH_INVALID);
  assert(rc_floor_graph(nodes,3,edges,2,nullptr,1,2,100,&out)==RC_GRAPH_INVALID);
  assert(rc_floor_graph(nodes,3,edges,2,obs,2,2,INFINITY,&out)==RC_GRAPH_INVALID);
  // Null with zero count is a valid empty array.
  assert(rc_floor_graph(nodes,3,nullptr,0,nullptr,0,2,100,&out)==RC_GRAPH_NO_REFERENCE);
  assert(rc_floor_graph(nullptr,0,nullptr,0,nullptr,0,2,100,&out)==RC_GRAPH_INVALID);
  // Target must be a registered nonzero node.
  assert(rc_floor_graph(nodes,3,edges,2,obs,2,0,100,&out)==RC_GRAPH_INVALID);
  assert(rc_floor_graph(nodes,3,edges,2,obs,2,9,100,&out)==RC_GRAPH_INVALID);
  nodes[0]=0;assert(run()==RC_GRAPH_INVALID);nodes[0]=1;
  // Edge structure.
  edges[1].to=9;assert(run()==RC_GRAPH_INVALID);reset();
  edges[1].from=0;assert(run()==RC_GRAPH_INVALID);reset();
  edges[1].to=2;assert(run()==RC_GRAPH_INVALID);reset();
  edges[1].kind=2;assert(run()==RC_GRAPH_INVALID);reset();
  edges[1].kind=-1;assert(run()==RC_GRAPH_INVALID);reset();
  edges[1].maximum_delta=221;assert(run()==RC_GRAPH_INVALID);reset();
  edges[1].minimum_delta=-221;assert(run()==RC_GRAPH_INVALID);reset();
  edges[1].minimum_delta=2;assert(run()==RC_GRAPH_INVALID);reset();
  edges[1].minimum_delta=std::numeric_limits<int>::min();assert(run()==RC_GRAPH_INVALID);reset();
  // Observation structure.
  obs[1].node=9;assert(run()==RC_GRAPH_INVALID);reset();
  obs[1].origin=0;assert(run()==RC_GRAPH_INVALID);reset();
  obs[1].observation=0;assert(run()==RC_GRAPH_INVALID);reset();
  obs[1].source=3;assert(run()==RC_GRAPH_INVALID);reset();
  obs[1].source=-1;assert(run()==RC_GRAPH_INVALID);reset();
  obs[1].maximum_level=201;assert(run()==RC_GRAPH_INVALID);reset();
  obs[1].minimum_level=-21;assert(run()==RC_GRAPH_INVALID);reset();
  obs[1].minimum_level=5;assert(run()==RC_GRAPH_INVALID);reset();
  obs[1].maximum_level=std::numeric_limits<int>::max();assert(run()==RC_GRAPH_INVALID);reset();
  // Invalid wins over stale evidence.
  obs[1].elapsed=0;obs[1].source=7;assert(run()==RC_GRAPH_INVALID && out.skipped==0);reset();
  // Exact capacity: 32 nodes, 64 edges (31 chain + 33 contact), 32 observations.
  {
   uint64_t n[32];rc_graph_edge e[64];rc_graph_observation o[32];
   for(int i=0;i<32;i++) n[i]=1000+static_cast<uint64_t>(31-i);
   for(int i=0;i<31;i++) e[i]={1000+static_cast<uint64_t>(i),1001+static_cast<uint64_t>(i),1,1,1,95};
   for(int i=31;i<64;i++) e[i]={1000+static_cast<uint64_t>(i%32),1000+static_cast<uint64_t>((i+1)%32),0,0,0,95};
   for(int i=0;i<32;i++) o[i]={1000,500+static_cast<uint64_t>(i),1,2,-20,-20,95};
   assert(rc_floor_graph(n,32,e,64,o,32,1031,100,&out)==RC_GRAPH_CANDIDATE && out.minimum_level==11 && out.maximum_level==11 && out.origins==32);
   assert(rc_floor_graph(n,32,e,64,o,32,1031,1000,&out)==RC_GRAPH_NO_REFERENCE && out.skipped==96);
  }
  // Deterministic full-capacity contradictory snapshots must never overflow before rejecting.
  {
   std::mt19937 generator(42); uint64_t n[32]; rc_graph_edge e[64];
   for(int i=0;i<32;i++) n[i]=static_cast<uint64_t>(i+1);
   for(int trial=0;trial<2000;trial++) {
    for(auto& edge:e) {
     uint64_t a=generator()%32+1,b=generator()%32+1;if(a==b)b=b%32+1;
     int delta=static_cast<int>(generator()%441)-220;
     edge={a,b,1,delta,delta,99};
    }
    auto reason=rc_floor_graph(n,32,e,64,nullptr,0,1,100,&out);
    assert(reason==RC_GRAPH_CONFLICT || reason==RC_GRAPH_NO_REFERENCE);
   }
  }
 } else if(test=="cycle") {
  edges[1]={2,1,1,0,0,99};
  assert(run(2,1)==RC_GRAPH_CONFLICT);
  // Consistent cycle 1->2->3->1 resolves.
  {rc_graph_edge c[]={{1,2,1,1,1,99},{2,3,1,1,1,99},{3,1,1,-2,-2,99}};
   assert(rc_floor_graph(nodes,3,c,3,obs,1,3,100,&out)==RC_GRAPH_CANDIDATE && out.minimum_level==4 && out.origins==1);
   c[2].minimum_delta=c[2].maximum_delta=-3;
   assert(rc_floor_graph(nodes,3,c,3,obs,1,3,100,&out)==RC_GRAPH_CONFLICT && out.minimum_level==0);
   // Interval cycle narrows: 1->2 [0,2], 2->3 [0,2], 3->1 [-1,-1] => node2 in {2,3}.
   rc_graph_edge w[]={{1,2,1,0,2,99},{2,3,1,0,2,99},{3,1,1,-1,-1,99}};
   assert(rc_floor_graph(nodes,3,w,3,obs,1,2,100,&out)==RC_GRAPH_AMBIGUOUS && out.minimum_level==2 && out.maximum_level==3);
   assert(rc_floor_graph(nodes,3,w,3,obs,1,3,100,&out)==RC_GRAPH_CANDIDATE && out.minimum_level==3 && out.maximum_level==3);
  }
  // Parallel edges intersect; disjoint parallel edges conflict.
  {rc_graph_edge p[]={{1,2,1,0,2,99},{2,1,1,-3,-1,99}};
   assert(rc_floor_graph(nodes,3,p,2,obs,1,2,100,&out)==RC_GRAPH_AMBIGUOUS && out.minimum_level==3 && out.maximum_level==4);
   p[1]={1,2,1,3,4,99};
   assert(rc_floor_graph(nodes,3,p,2,obs,1,2,100,&out)==RC_GRAPH_CONFLICT);}
  // Contradictory cycle with no references anywhere still fails closed.
  {rc_graph_edge c[]={{2,3,1,1,1,99},{3,2,1,1,1,99}};
   assert(rc_floor_graph(nodes,3,c,2,obs,0,1,100,&out)==RC_GRAPH_CONFLICT);}
  // Two references on one node with disjoint intervals conflict; overlapping ones intersect.
  {rc_graph_observation two[]={{1,10,100,0,2,4,99},{1,11,100,1,6,7,99}};
   assert(rc_floor_graph(nodes,3,edges,1,two,2,2,100,&out)==RC_GRAPH_CONFLICT);
   two[1].minimum_level=4;
   assert(rc_floor_graph(nodes,3,edges,1,two,2,2,100,&out)==RC_GRAPH_CANDIDATE && out.minimum_level==5 && out.origins==2);}
 } else {assert(false);}
}
