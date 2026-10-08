#include "workflow.hpp"
#include <algorithm>
#include <stdexcept>
#include <utility>

namespace rescue {
namespace {
bool publicKind(Kind k) { return k==Kind::Request || k==Kind::FollowUp || k==Kind::Correction || k==Kind::Withdrawal; }
bool handlingKind(Kind k) { return k==Kind::Assignment || k==Kind::Resolution || k==Kind::Reopen; }
bool validID(const std::string& s) { return !s.empty() && s.size()<=64; }
bool knownKind(Kind k) {
    switch(k) {
    case Kind::Request: case Kind::FollowUp: case Kind::Correction: case Kind::Withdrawal:
    case Kind::Receipt: case Kind::Acknowledgment: case Kind::Reply: case Kind::Assignment:
    case Kind::Resolution: case Kind::Reopen: case Kind::WithdrawalDisposition: return true;
    }
    return false;
}
}
Model::Model(std::string local, std::string exercise, std::map<std::string, Role> members, std::size_t capacity)
 : local_(std::move(local)), exercise_(std::move(exercise)), members_(std::move(members)), capacity_(capacity) {
    if (!validID(local_) || !validID(exercise_) || !members_.contains(local_) || capacity_==0 || capacity_>4096 || members_.size()>16)
        throw std::invalid_argument("Invalid synthetic model configuration");
    std::size_t commandCount=0;
    for (const auto& [id,role]:members_) {
        if (!validID(id) || (role!=Role::Public && role!=Role::Command)) throw std::invalid_argument("Invalid fixture member");
        if (role==Role::Command) ++commandCount;
    }
    if (commandCount!=1) throw std::invalid_argument("Exactly one fixture command authority required");
}
const Event* Model::find(const std::string& id) const {
    for (const auto& e:events_) if (e.id==id) return &e;
    return nullptr;
}
const Event* Model::creation(const std::string& request) const {
    for (const auto& e:events_) if (e.request==request && e.kind==Kind::Request) return &e;
    return nullptr;
}
Result Model::submit(const Event& e) {
    if (e.author!=local_) return Result::Unauthorized;
    return accept(e);
}
Result Model::receive(const Event& e) {
    if (e.destination!=local_) return Result::Unauthorized;
    return accept(e);
}
Result Model::accept(const Event& e) {
    if (!knownKind(e.kind) || !validID(e.id) || !validID(e.exercise) || !validID(e.request)
        || !validID(e.author) || !validID(e.destination) || e.reference.size()>64
        || e.exercise!=exercise_ || e.text.size()>2048 || e.reportedLocation.size()>2048-e.text.size()) return Result::Invalid;
    if (!members_.contains(e.author) || !members_.contains(e.destination)) return Result::Unauthorized;
    if (const auto* existing=find(e.id)) return *existing==e ? Result::Duplicate : Result::Conflict;
    const auto authorRole=members_.at(e.author), destinationRole=members_.at(e.destination);
    if (e.kind==Kind::Receipt) {
        if (e.reference.empty() || e.sequence || e.revision || e.seenPublicSequence || !e.text.empty() || !e.reportedLocation.empty()) return Result::Invalid;
        const auto* target=find(e.reference);
        if (!target) return Result::MissingDependency;
        if (target->kind==Kind::Receipt || target->request!=e.request) return Result::Invalid;
        if (e.author!=target->destination || e.destination!=target->author) return Result::Unauthorized;
    } else {
        if (e.sequence==0) return Result::Invalid;
        if (publicKind(e.kind)) {
            if (authorRole!=Role::Public || destinationRole!=Role::Command) return Result::Unauthorized;
        } else if (authorRole!=Role::Command || destinationRole!=Role::Public) return Result::Unauthorized;
        const auto* original=creation(e.request);
        if (e.kind==Kind::Request) {
            if (original) return Result::Conflict;
            if (e.sequence!=1 || e.text.empty()) return Result::Invalid;
        } else {
            if (!original) return Result::MissingDependency;
            if (publicKind(e.kind) && e.author!=original->author) return Result::Unauthorized;
            if (!publicKind(e.kind) && e.destination!=original->author) return Result::Unauthorized;
        }
        for (const auto& stored:events_)
            if (stored.kind!=Kind::Receipt && stored.request==e.request && stored.author==e.author && stored.sequence==e.sequence) return Result::Conflict;
        if (e.kind==Kind::Acknowledgment || e.kind==Kind::WithdrawalDisposition) {
            if (e.reference.empty()) return Result::Invalid;
            const auto* target=find(e.reference);
            if (!target) return Result::MissingDependency;
            if (!publicKind(target->kind) || target->request!=e.request || target->destination!=e.author
                || (e.kind==Kind::WithdrawalDisposition && target->kind!=Kind::Withdrawal)) return Result::Invalid;
        } else if (!e.reference.empty()) return Result::Invalid;
        if (e.kind==Kind::Correction && e.reportedLocation.empty()) return Result::Invalid;
        if (e.kind!=Kind::Request && e.kind!=Kind::Correction && !e.reportedLocation.empty()) return Result::Invalid;
        if (!publicKind(e.kind) && e.kind!=Kind::Acknowledgment && e.text.empty()) return Result::Invalid;
        if (handlingKind(e.kind)) {
            const auto state=*snapshot(e.request);
            if (e.revision==0) return Result::Invalid;
            if (e.revision<=state.commandRevision) return Result::Conflict;
            if (state.commandRevision==UINT64_MAX || e.revision!=state.commandRevision+1) return Result::MissingDependency;
            if (e.kind==Kind::Reopen ? state.handling!=Handling::Resolved : state.handling==Handling::Resolved) return Result::Invalid;
            if (e.kind==Kind::Resolution) {
                if (e.seenPublicSequence>state.publicSequence) return Result::MissingDependency;
                if (e.seenPublicSequence==0 || (e.author==local_ && e.seenPublicSequence!=state.publicSequence)) return Result::Invalid;
            } else if (e.seenPublicSequence) return Result::Invalid;
        } else if (e.revision || e.seenPublicSequence) return Result::Invalid;
    }
    if (events_.size()>=capacity_) return Result::Full;
    if (failStore_) { failStore_=false; return Result::StoreFailure; }
    events_.push_back(e);
    return Result::Accepted;
}
std::optional<Event> Model::receiptFor(const std::string& eventID, const std::string& receiptID) const {
    const auto* e=find(eventID);
    if (!e || e->destination!=local_ || e->kind==Kind::Receipt || !validID(receiptID)) return {};
    Event r; r.id=receiptID;r.exercise=exercise_;r.request=e->request;r.author=local_;
    r.destination=e->author;r.kind=Kind::Receipt;r.sequence=0;r.reference=e->id;
    return r;
}
Delivery Model::delivery(const std::string& eventID) const {
    if (!find(eventID)) return Delivery::Waiting;
    Delivery result=Delivery::Waiting;
    for (const auto& e:events_) if (e.reference==eventID) {
        if (e.kind==Kind::Acknowledgment) return Delivery::HumanAcknowledged;
        if (e.kind==Kind::Receipt) result=Delivery::DeviceReceived;
    }
    return result;
}
std::optional<Snapshot> Model::snapshot(const std::string& requestID) const {
    const auto* original=creation(requestID);
    if (!original) return {};
    Snapshot result;result.creator=original->author;result.reportedLocation=original->reportedLocation;
    result.originalDelivery=delivery(original->id);
    std::uint64_t locationSequence=original->sequence, dispositionSequence=0, resolvedSeen=0, withdrawalSequence=0;
    std::string latestWithdrawal;
    for (const auto& e:events_) if (e.request==requestID) {
        if (publicKind(e.kind)) {
            const auto state=delivery(e.id);
            result.publicMessages.push_back({e.id,e.kind,e.sequence,state});
            if (state==Delivery::Waiting) ++result.pendingPublicMessages;
            if (result.handling==Handling::Resolved && e.kind!=Kind::Request) result.lateUpdate=true;
        }
        if (publicKind(e.kind) && e.sequence>result.publicSequence) { result.publicSequence=e.sequence;result.latestPublicEvent=e.id; }
        if (e.kind==Kind::Correction && e.sequence>locationSequence) { result.reportedLocation=e.reportedLocation;locationSequence=e.sequence; }
        if (e.kind==Kind::Withdrawal && e.sequence>withdrawalSequence) { latestWithdrawal=e.id;withdrawalSequence=e.sequence; }
        if (handlingKind(e.kind) && e.revision>result.commandRevision) {
            result.commandRevision=e.revision;
            if (e.kind==Kind::Assignment) { result.handling=Handling::Assigned;result.assignedTo=e.text;result.reason.clear();result.lateUpdate=false; }
            else if (e.kind==Kind::Resolution) { result.handling=Handling::Resolved;result.reason=e.text;resolvedSeen=e.seenPublicSequence;result.lateUpdate=false; }
            else { result.handling=Handling::Open;result.reason=e.text;result.assignedTo.clear();result.lateUpdate=false; }
        }
    }
    result.withdrawalRequested=!latestWithdrawal.empty();
    for (const auto& e:events_) if (e.kind==Kind::WithdrawalDisposition && e.reference==latestWithdrawal && e.sequence>dispositionSequence) {
        result.withdrawalDisposition=e.text;dispositionSequence=e.sequence;
    }
    result.withdrawalPending=result.withdrawalRequested && result.withdrawalDisposition.empty();
    std::sort(result.publicMessages.begin(),result.publicMessages.end(),[](const auto& a,const auto& b){return a.sequence<b.sequence;});
    result.latestPublicDelivery=delivery(result.latestPublicEvent);
    result.lateUpdate=result.handling==Handling::Resolved && (result.lateUpdate || result.publicSequence>resolvedSeen);
    return result;
}
}
