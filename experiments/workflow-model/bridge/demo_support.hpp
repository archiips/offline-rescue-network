#pragma once
#include "workflow.hpp"
#include <locale>
#include <sstream>
namespace rescue_demo {
using namespace rescue;
inline const std::map<std::string,Role> members{{"public",Role::Public},{"command",Role::Command}};
inline bool bounded(const char* p, std::size_t max) {
    if (!p) return false;
    for (std::size_t n=0;n<=max;++n) if (p[n]=='\0') return true;
    return false;
}
inline std::string quote(const std::string& input) {
    std::string out="\"";constexpr char hex[]="0123456789abcdef";
    for (unsigned char c:input) {
        if (c=='"' || c=='\\') {out+='\\';out+=static_cast<char>(c);}
        else if(c<32) {out+="\\u00";out+=hex[c>>4];out+=hex[c&15];}
        else out+=static_cast<char>(c);
    }
    return out+'"';
}
inline const char* boolean(bool b) {return b?"true":"false";}
inline std::string errorFor(Result r) {
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
inline std::string deviceJSON(const Model& model,const char* local) {
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
