#include "RescueDemoBridge.h"
#include "demo_support.hpp"
#include "session_store.hpp"
#include "event_wire.hpp"
#include <algorithm>
#include <cstring>
#include <cstdlib>
#include <set>
#include <type_traits>
using namespace rescue;
using namespace rescue_demo;
namespace {
struct State {
 Model model;
 std::deque<Event> pending;
 explicit State(const std::string& actor):model(actor,"training-demo",members){}
};
unsigned char* copy(const std::vector<unsigned char>& bytes){auto* p=static_cast<unsigned char*>(std::malloc(bytes.size()));if(!p)throw std::bad_alloc();std::memcpy(p,bytes.data(),bytes.size());return p;}
Event actionEvent(const Model& model,const std::string& actor,int action,const char* value,const char* reference){
 Event e;e.author=actor;e.destination=actor=="public"?"command":"public";e.exercise="training-demo";e.request="request-1";e.text=value;
 for(const auto& stored:model.events())if(stored.author==actor && stored.kind!=Kind::Receipt)e.sequence=std::max(e.sequence,stored.sequence+1);
 e.id=actor+"-"+std::to_string(e.sequence);const auto state=model.snapshot(e.request);
 switch(action){
 case RC_SOS:e.kind=Kind::Request;e.text="SYNTHETIC assistance request";e.reportedLocation=value;break;
 case RC_FOLLOWUP:e.kind=Kind::FollowUp;break;
 case RC_CORRECTION:e.kind=Kind::Correction;e.text="SYNTHETIC reported location correction";e.reportedLocation=value;break;
 case RC_WITHDRAWAL:e.kind=Kind::Withdrawal;break;
 case RC_ACKNOWLEDGE:e.kind=Kind::Acknowledgment;e.reference=*reference?reference:"public-1";e.text="Acknowledgment recorded for this training request";break;
 case RC_REPLY:e.kind=Kind::Reply;break;
 case RC_ASSIGN:e.kind=Kind::Assignment;break;
 case RC_RESOLVE:e.kind=Kind::Resolution;e.seenPublicSequence=state?state->publicSequence:0;break;
 case RC_REOPEN:e.kind=Kind::Reopen;break;
 case RC_DISPOSITION:e.kind=Kind::WithdrawalDisposition;e.reference=reference;
  if(e.reference.empty()){std::uint64_t highest=0;for(const auto& stored:model.events())if(stored.kind==Kind::Withdrawal && stored.sequence>highest){highest=stored.sequence;e.reference=stored.id;}}break;
 default:throw std::runtime_error("Invalid sample action.");
 }
 if(e.kind==Kind::Assignment || e.kind==Kind::Resolution || e.kind==Kind::Reopen)e.revision=state?state->commandRevision+1:1;
 return e;
}
}
struct rc_endpoint {
 std::string actor,error;
 State state;
 SessionStore store;
 rc_endpoint(const char* path,int role):actor(role==0?"public":"command"),state(actor),store(path,actor){
  const auto saved=store.load();const auto& history=actor=="public"?saved.publicEvents:saved.responderEvents;
  if(!(actor=="public"?saved.responderEvents:saved.publicEvents).empty() || !saved.connected)throw std::runtime_error("Invalid endpoint store.");
  for(const auto& e:history){rescue_wire::decode(rescue_wire::encode(e));const auto r=e.author==actor?state.model.submit(e):state.model.receive(e);if(r!=Result::Accepted)throw std::runtime_error("Invalid endpoint history.");}
  if(history.size()+saved.pending.size()>128)throw std::runtime_error("Saved endpoint has no receipt reserve.");
  std::set<std::string> ids;
  std::uint64_t lastQueuedSequence=0;
  for(const auto& e:saved.pending){if(e.sequence<=lastQueuedSequence)throw std::runtime_error("Invalid saved outbox order.");lastQueuedSequence=e.sequence;if(e.author!=actor || e.kind==Kind::Receipt || std::find(history.begin(),history.end(),e)==history.end() || !ids.insert(e.id).second || state.model.delivery(e.id)==Delivery::DeviceReceived)throw std::runtime_error("Invalid saved endpoint outbox.");}
  for(const auto& e:history){
   if(e.kind==Kind::Receipt)continue;
   if(e.author==actor){bool received=false;for(const auto& r:history)if(r.kind==Kind::Receipt && r.reference==e.id)received=true;
    if(received==ids.contains(e.id))throw std::runtime_error("Missing or obsolete endpoint transfer.");
   }else{const auto r=state.model.receiptFor(e.id,"receipt-"+e.id);if(!r || std::find(history.begin(),history.end(),*r)==history.end())throw std::runtime_error("Inbound event has no saved receipt.");}
  }
  state.pending=saved.pending;
 }
 int publish(State&& next){
  static_assert(std::is_nothrow_move_assignable_v<State>);
  try{SavedSession saved;saved.pending=next.pending;(actor=="public"?saved.publicEvents:saved.responderEvents)=next.model.events();store.save(saved);}
  catch(const std::exception& e){error=e.what();return 7;}
  state=std::move(next);error.clear();return 0;
 }
 int fail(Result r){error=errorFor(r);return static_cast<int>(r);}
};
rc_endpoint* rc_endpoint_open(const char* path,int role){if(!bounded(path,4096) || !*path || (role!=0 && role!=1))return nullptr;try{return new rc_endpoint(path,role);}catch(...){return nullptr;}}
void rc_endpoint_destroy(rc_endpoint* e){delete e;}
int rc_endpoint_perform(rc_endpoint* e,int action,const char* value,const char* reference){
 if(!e)return -1;
 try{
  if(action<0 || action>RC_DISPOSITION || !bounded(value,2048) || !bounded(reference,64))return e->fail(Result::Invalid);
  if((action<=RC_WITHDRAWAL)!=(e->actor=="public"))return e->fail(Result::Unauthorized);
  if(e->state.pending.size()>=64 || e->state.model.events().size()+e->state.pending.size()+2>128)return e->fail(Result::Full);
  State next=e->state;auto event=actionEvent(next.model,e->actor,action,value,reference);rescue_wire::decode(rescue_wire::encode(event));
  const auto r=next.model.submit(event);if(r!=Result::Accepted)return e->fail(r==Result::Duplicate?Result::Conflict:r);
  next.pending.push_back(event);return e->publish(std::move(next));
 }catch(...){return e->fail(Result::Invalid);}
}
unsigned char* rc_endpoint_next(const rc_endpoint* e,size_t* length){if(length)*length=0;if(!e || !length || e->state.pending.empty())return nullptr;try{auto bytes=rescue_wire::encode(e->state.pending.front());auto* result=copy(bytes);*length=bytes.size();return result;}catch(...){return nullptr;}}
int rc_endpoint_accept(rc_endpoint* e,const unsigned char* packet,size_t length,unsigned char** receipt,size_t* receiptLength){
 if(receipt)*receipt=nullptr;if(receiptLength)*receiptLength=0;if(!e || !packet || !receipt || !receiptLength)return -1;
 try{
  const auto event=rescue_wire::decode({packet,length});if(event.kind==Kind::Receipt)return e->fail(Result::Invalid);
  if(e->state.model.events().size()+e->state.pending.size()+2>128 && std::find(e->state.model.events().begin(),e->state.model.events().end(),event)==e->state.model.events().end())return e->fail(Result::Full);
  State next=e->state;const auto r=next.model.receive(event);if(r!=Result::Accepted && r!=Result::Duplicate)return e->fail(r);
  const auto returned=next.model.receiptFor(event.id,"receipt-"+event.id);if(!returned)return e->fail(Result::Invalid);
  const auto rr=next.model.submit(*returned);if(rr!=Result::Accepted && rr!=Result::Duplicate)return e->fail(rr);
  auto bytes=rescue_wire::encode(*returned);std::unique_ptr<unsigned char,decltype(&std::free)> output(copy(bytes),std::free);
  const int saved=e->publish(std::move(next));if(saved)return saved;
  *receipt=output.release();*receiptLength=bytes.size();return static_cast<int>(r);
 }catch(...){return e->fail(Result::Invalid);}
}
int rc_endpoint_confirm(rc_endpoint* e,const unsigned char* packet,size_t length){
 if(!e || !packet)return -1;
 try{
  const auto receipt=rescue_wire::decode({packet,length});if(receipt.kind!=Kind::Receipt || receipt.id!="receipt-"+receipt.reference)return e->fail(Result::Invalid);
  if((e->state.pending.empty() || e->state.pending.front().id!=receipt.reference) && std::find(e->state.model.events().begin(),e->state.model.events().end(),receipt)==e->state.model.events().end())return e->fail(Result::Invalid);
  State next=e->state;const auto r=next.model.receive(receipt);if(r!=Result::Accepted && r!=Result::Duplicate)return e->fail(r);
  std::erase_if(next.pending,[&receipt](const Event& event){return event.id==receipt.reference;});return e->publish(std::move(next));
 }catch(...){return e->fail(Result::Invalid);}
}
char* rc_endpoint_snapshot(const rc_endpoint* e){if(!e)return nullptr;try{auto s="{\"role\":"+quote(e->actor)+",\"pendingTransfers\":"+std::to_string(e->state.pending.size())+",\"error\":"+quote(e->error)+",\"state\":"+deviceJSON(e->state.model,e->actor.c_str())+"}";auto* p=static_cast<char*>(std::malloc(s.size()+1));if(!p)return nullptr;std::memcpy(p,s.c_str(),s.size()+1);return p;}catch(...){return nullptr;}}
int rc_endpoint_reset(rc_endpoint* e){if(!e)return -1;try{return e->publish(State(e->actor));}catch(...){return -1;}}
