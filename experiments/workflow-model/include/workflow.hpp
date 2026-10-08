#pragma once
#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <vector>

namespace rescue {
enum class Role { Public, Command };
enum class Kind { Request, FollowUp, Correction, Withdrawal, Receipt, Acknowledgment,
                  Reply, Assignment, Resolution, Reopen, WithdrawalDisposition };
enum class Result { Accepted, Duplicate, Invalid, Unauthorized, MissingDependency,
                    Conflict, Full, StoreFailure };
enum class Delivery { Waiting, DeviceReceived, HumanAcknowledged };
enum class Handling { Open, Assigned, Resolved };
struct Event {
    std::string id, exercise, request, author, destination;
    Kind kind = Kind::Request;
    std::uint64_t sequence = 1, revision = 0, seenPublicSequence = 0;
    std::string reference, text, reportedLocation;
    bool operator==(const Event&) const = default;
};
struct PublicMessageDelivery {
    std::string eventID;
    Kind kind;
    std::uint64_t sequence;
    Delivery delivery;
};
struct Snapshot {
    std::string creator, reportedLocation, assignedTo, reason, withdrawalDisposition;
    std::string latestPublicEvent;
    Delivery originalDelivery = Delivery::Waiting;
    Delivery latestPublicDelivery = Delivery::Waiting;
    Handling handling = Handling::Open;
    std::uint64_t commandRevision = 0, publicSequence = 0;
    bool withdrawalRequested = false, withdrawalPending = false, lateUpdate = false;
    std::size_t pendingPublicMessages = 0;
    std::vector<PublicMessageDelivery> publicMessages;
};
// Supplied fixture identities are not authenticated credentials. In-memory only.
class Model {
public:
    Model(std::string localActor, std::string exercise,
          std::map<std::string, Role> members, std::size_t capacity = 128);
    Result submit(const Event&);
    Result receive(const Event&);
    std::optional<Event> receiptFor(const std::string& eventID, const std::string& receiptID) const;
    std::optional<Snapshot> snapshot(const std::string& requestID) const;
    Delivery delivery(const std::string& eventID) const;
    const std::vector<Event>& events() const { return events_; }
    void failNextStore() { failStore_ = true; }
private:
    Result accept(const Event&);
    const Event* find(const std::string&) const;
    const Event* creation(const std::string&) const;
    std::string local_, exercise_;
    std::map<std::string, Role> members_;
    std::size_t capacity_;
    bool failStore_ = false;
    std::vector<Event> events_;
};
}
