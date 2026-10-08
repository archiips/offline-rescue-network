#include "RescueDemoBridge.h"
#include "workflow.hpp"
#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <locale>
#include <sstream>
#include <type_traits>
using namespace rescue;
namespace {
// Pin the public C result contract and internal Swift snapshot schema.
static_assert(static_cast<int>(Result::Accepted)==0 && static_cast<int>(Result::Duplicate)==1 &&
 static_cast<int>(Result::Invalid)==2 && static_cast<int>(Result::Unauthorized)==3 &&
 static_cast<int>(Result::MissingDependency)==4 && static_cast<int>(Result::Conflict)==5 &&
 static_cast<int>(Result::Full)==6 && static_cast<int>(Result::StoreFailure)==7);
static_assert(static_cast<int>(Kind::Request)==0 && static_cast<int>(Kind::FollowUp)==1 &&
 static_cast<int>(Kind::Correction)==2 && static_cast<int>(Kind::Withdrawal)==3 &&
 static_cast<int>(Kind::Receipt)==4 && static_cast<int>(Kind::Acknowledgment)==5 &&
 static_cast<int>(Kind::Reply)==6 && static_cast<int>(Kind::Assignment)==7 &&
 static_cast<int>(Kind::Resolution)==8 && static_cast<int>(Kind::Reopen)==9 &&
 static_cast<int>(Kind::WithdrawalDisposition)==10);
static_assert(static_cast<int>(Delivery::Waiting)==0 && static_cast<int>(Delivery::DeviceReceived)==1 &&
 static_cast<int>(Delivery::HumanAcknowledged)==2);
static_assert(static_cast<int>(Handling::Open)==0 && static_cast<int>(Handling::Assigned)==1 &&
 static_cast<int>(Handling::Resolved)==2);
const std::map<std::string,Role> members{{"public",Role::Public},{"command",Role::Command}};
bool bounded(const char* p, std::size_t max) {
    if (!p) return false;
    for (std::size_t n=0;n<=max;++n) if (p[n]=='\0') return true;
    return false;
}
std::string quote(const std::string& input) {
    std::string out="\"";constexpr char hex[]="0123456789abcdef";
    for (unsigned char c:input) {
        if (c=='"' || c=='\\') {out+='\\';out+=static_cast<char>(c);}
        else if(c<32) {out+="\\u00";out+=hex[c>>4];out+=hex[c&15];}
        else out+=static_cast<char>(c);
    }
    return out+'"';
}
const char* boolean(bool b) {return b?"true":"false";}
std::string errorFor(Result r) {
    switch(r) {
    case Result::Accepted:case Result::Duplicate:return "";
    case Result::Full:return "Demo memory is full. Reset the exercise to continue.";
    case Result::MissingDependency:return "The referenced request or update has not arrived yet.";
    case Result::Conflict:return "This action conflicts with an existing event or handling revision.";
    case Result::Unauthorized:return "This demo role cannot perform that action.";
    case Result::StoreFailure:return "Could not save the action in demo memory.";
    case Result::Invalid:return "That action is not valid for the current request state.";
    }
    return "Unknown demo error.";
}
std::string deviceJSON(const Model& model,const char* local) {
    const auto optional=model.snapshot("request-1");const Snapshot s=optional.value_or(Snapshot{});
    std::ostringstream out;out.imbue(std::locale::classic());
    out<<"{\"hasRequest\":"<<boolean(optional.has_value())<<",\"reportedLocation\":"<<quote(s.reportedLocation)
       <<",\"originalDelivery\":"<<static_cast<int>(s.originalDelivery)<<",\"handling\":"<<static_cast<int>(s.handling)
       <<",\"assignedTo\":"<<quote(s.assignedTo)<<",\"reason\":"<<quote(s.reason)
       <<",\"withdrawalPending\":"<<boolean(s.withdrawalPending)<<",\"withdrawalDisposition\":"<<quote(s.withdrawalDisposition)
       <<",\"lateUpdate\":"<<boolean(s.lateUpdate)<<",\"pendingPublicMessages\":"<<s.pendingPublicMessages<<",\"messages\":[";
    bool first=true;
    for (const auto& e:model.events()) {
        if(e.kind==Kind::Receipt) continue;
        if(!first) out<<',';first=false;
        out<<"{\"id\":"<<quote(e.id)<<",\"kind\":"<<static_cast<int>(e.kind)<<",\"text\":"<<quote(e.text)
           <<",\"location\":"<<quote(e.reportedLocation)<<",\"reference\":"<<quote(e.reference)
           <<",\"outgoing\":"<<boolean(e.author==local)<<",\"delivery\":"<<static_cast<int>(model.delivery(e.id))<<'}';
    }
    return out.str()+"]}";
}
}
struct rc_session {
    Model requester{"public","training-demo",members};
    Model responder{"command","training-demo",members};
    std::deque<Event> pending;
    bool connected=true;
    std::string error;
    Model& destination(const Event& e) {return e.destination=="public"?requester:responder;}
    void pump() {
        if(!connected) return;
        static_assert(std::is_nothrow_move_assignable_v<Event> && std::is_nothrow_move_constructible_v<Event>);
        std::size_t stalled=0,budget=256;
        while(!pending.empty() && budget--) {
            const Event& e=pending.front();
            auto& target=destination(e);
            const auto accepted=target.receive(e);
            if(accepted!=Result::Accepted && accepted!=Result::Duplicate) {
                error=errorFor(accepted);
                std::rotate(pending.begin(),pending.begin()+1,pending.end());
                if(++stalled>=pending.size()) break;
                continue;
            }
            if(e.kind!=Kind::Receipt) {
                auto receipt=target.receiptFor(e.id,"receipt-"+e.id);
                if(!receipt) {error="Could not create a model receipt.";break;}
                const auto result=target.submit(*receipt);
                if(result!=Result::Accepted && result!=Result::Duplicate) {
                    error=errorFor(result);
                    std::rotate(pending.begin(),pending.begin()+1,pending.end());
                    if(++stalled>=pending.size()) break;
                    continue;
                }
                // Replace only after receipt acceptance. No allocation or queue removal.
                pending.front()=std::move(*receipt);
            } else {
                pending.pop_front();
            }
            stalled=0;
        }
        if(pending.empty()) error.clear();
    }
    void pumpSafely() noexcept {
        try {pump();} catch(...) {
            // The original action is already accepted; retain transfers for retry.
            try {error="Transfer interrupted. Reconnect to retry, or reset the sample session.";} catch(...) {}
        }
    }
    int perform(int action,const char* value,const char* reference) {
        error.clear();
        if(action<RC_SOS || action>RC_DISPOSITION || !bounded(value,2048) || !bounded(reference,64)) {
            error="Invalid demo action or input length.";return 2;
        }
        if(pending.size()>=64) {error="Demo transfer queue is full. Reconnect to retry; reset if demo memory is full.";return 6;}
        const bool publicAction=action<=RC_WITHDRAWAL;
        auto& origin=publicAction?requester:responder;
        std::uint64_t sequence=1;
        for(const auto& stored:origin.events()) if(stored.author==(publicAction?"public":"command") && stored.kind!=Kind::Receipt)
            sequence=std::max(sequence,stored.sequence+1);
        Event e;e.author=publicAction?"public":"command";e.destination=publicAction?"command":"public";
        e.id=e.author+"-"+std::to_string(sequence);e.sequence=sequence;e.request="request-1";e.exercise="training-demo";
        e.text=value;
        const auto state=responder.snapshot(e.request);
        switch(action) {
        case RC_SOS:e.kind=Kind::Request;e.text="SYNTHETIC assistance request";e.reportedLocation=value;break;
        case RC_FOLLOWUP:e.kind=Kind::FollowUp;break;
        case RC_CORRECTION:e.kind=Kind::Correction;e.reportedLocation=value;e.text="SYNTHETIC reported location correction";break;
        case RC_WITHDRAWAL:e.kind=Kind::Withdrawal;break;
        case RC_ACKNOWLEDGE:e.kind=Kind::Acknowledgment;e.reference=*reference?reference:"public-1";e.text="Acknowledgment recorded for this training request";break;
        case RC_REPLY:e.kind=Kind::Reply;break;
        case RC_ASSIGN:e.kind=Kind::Assignment;break;
        case RC_RESOLVE:e.kind=Kind::Resolution;e.seenPublicSequence=state?state->publicSequence:0;break;
        case RC_REOPEN:e.kind=Kind::Reopen;break;
        case RC_DISPOSITION:
            e.kind=Kind::WithdrawalDisposition;e.reference=reference;
            if(e.reference.empty()) {
                std::uint64_t highest=0;
                for(const auto& stored:responder.events()) if(stored.kind==Kind::Withdrawal && stored.sequence>highest) {
                    highest=stored.sequence;e.reference=stored.id;
                }
            }
            if(e.reference.empty()) {error="No withdrawal has arrived to review.";return 4;}
            break;
        }
        if(e.kind==Kind::Assignment || e.kind==Kind::Resolution || e.kind==Kind::Reopen) e.revision=state?state->commandRevision+1:1;
        pending.push_back(e); // Allocate queue entry before model acceptance.
        Result result;
        try {result=origin.submit(e);}catch(...) {pending.pop_back();throw;}
        if(result!=Result::Accepted && result!=Result::Duplicate) {pending.pop_back();error=errorFor(result);return static_cast<int>(result);}
        pumpSafely();return static_cast<int>(result);
    }
};
rc_session* rc_create(void) {try{return new rc_session;}catch(...){return nullptr;}}
void rc_destroy(rc_session* s) {delete s;}
int rc_perform(rc_session* s,int action,const char* value,const char* reference) {
    if(!s)return -1;try{return s->perform(action,value,reference);}catch(...){return -1;}
}
int rc_set_connected(rc_session* s,int connected) {
    if(!s || (connected!=0 && connected!=1))return -1;
    try {s->connected=connected!=0;s->error.clear();s->pumpSafely();return 0;}catch(...){return -1;}
}
char* rc_snapshot(const rc_session* s) {
    if(!s)return nullptr;
    try {
        std::string json="{\"connected\":"+std::string(boolean(s->connected))+",\"pendingTransfers\":"+std::to_string(s->pending.size())
            +",\"error\":"+quote(s->error)+",\"publicState\":"+deviceJSON(s->requester,"public")+",\"responderState\":"+deviceJSON(s->responder,"command")+"}";
        auto* copy=static_cast<char*>(std::malloc(json.size()+1));if(!copy)return nullptr;
        std::memcpy(copy,json.c_str(),json.size()+1);return copy;
    }catch(...){return nullptr;}
}
void rc_free(char* p) {std::free(p);}
