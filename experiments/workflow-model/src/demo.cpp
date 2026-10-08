#include "workflow.hpp"
#include <iostream>
#include <stdexcept>
using namespace rescue;
static void accepted(Result r) { if(r!=Result::Accepted) throw std::runtime_error("Synthetic scenario rejected an event"); }
static const char* deliveryName(Delivery d) {
 switch(d) { case Delivery::Waiting:return "Waiting";case Delivery::DeviceReceived:return "Simulated device received";case Delivery::HumanAcknowledged:return "Simulated human acknowledged"; } return "Unknown";
}
static void show(const char* step,const Model& requester,const Model& command) {
 const auto p=*requester.snapshot("request-1"),c=*command.snapshot("request-1");
 std::cout<<"\n"<<step<<"\n  Requester: original="<<deliveryName(p.originalDelivery)
 <<", latest update="<<deliveryName(p.latestPublicDelivery)<<", pending public messages="<<p.pendingPublicMessages<<"\n  Reported location: "<<p.reportedLocation
 <<"\n  Command: handling="<<(c.handling==Handling::Resolved?"Resolved":c.handling==Handling::Assigned?"Assigned":"Open")
 <<", late update="<<(c.lateUpdate?"yes":"no")<<", withdrawal="<<(c.withdrawalRequested?"requested":"none")<<'\n';
}
int main() {
 try {
  std::cout<<"SYNTHETIC TWO-DEVICE WORKFLOW — in memory; no radio, durable storage or authentication\n";
  const std::map<std::string,Role> members{{"public",Role::Public},{"command",Role::Command}};
  Model p("public","test-drill",members),c("command","test-drill",members);
  Event sos;sos.id="sos";sos.exercise="test-drill";sos.request="request-1";sos.author="public";sos.destination="command";sos.text="SYNTHETIC assistance request";sos.reportedLocation="Test building, floor unknown";
  accepted(p.submit(sos));accepted(c.receive(sos));show("1. SOS accepted at command; return path not delivered",p,c);
  auto receipt=[&](Model& source,Model& destination,const std::string& id,const std::string& rid) {
   auto r=destination.receiptFor(id,rid);if(!r)throw std::runtime_error("Receipt cannot be created");accepted(destination.submit(*r));accepted(source.receive(*r));
  };
  receipt(p,c,"sos","sos-receipt");show("2. Device receipt returned",p,c);
  auto action=[&](Kind kind,std::string id,std::uint64_t seq) { Event e=sos;e.id=std::move(id);e.kind=kind;e.author="command";e.destination="public";e.sequence=seq;e.reportedLocation.clear();e.text="SYNTHETIC responder action";return e; };
  auto ack=action(Kind::Acknowledgment,"ack",1);ack.reference="sos";accepted(c.submit(ack));show("3. Responder acknowledged locally; acknowledgment not yet delivered",p,c);
  accepted(p.receive(ack));receipt(c,p,"ack","ack-receipt");show("4. Human acknowledgment and its return receipt delivered",p,c);
  auto reply=action(Kind::Reply,"reply",2);reply.text="SYNTHETIC reply: clarify reported floor";accepted(c.submit(reply));accepted(p.receive(reply));receipt(c,p,"reply","reply-receipt");
  std::cout<<"\n5. Reply reached requester; responder sees "<<deliveryName(c.delivery("reply"))<<" (not read)\n";
  auto correction=sos;correction.id="correction";correction.kind=Kind::Correction;correction.sequence=2;correction.reportedLocation="Test building, reported floor 4";accepted(p.submit(correction));show("6. Correction queued during simulated outage",p,c);
  accepted(c.receive(correction));receipt(p,c,"correction","correction-receipt");
  auto assignment=action(Kind::Assignment,"assignment",3);assignment.revision=1;assignment.text="SYNTHETIC team A";accepted(c.submit(assignment));accepted(p.receive(assignment));
  auto resolution=action(Kind::Resolution,"resolution",4);resolution.revision=2;resolution.seenPublicSequence=2;resolution.text="SYNTHETIC drill complete";accepted(c.submit(resolution));accepted(p.receive(resolution));show("7. Explicit assignment and resolution",p,c);
  auto withdrawal=sos;withdrawal.id="withdrawal";withdrawal.kind=Kind::Withdrawal;withdrawal.sequence=3;withdrawal.reportedLocation.clear();accepted(p.submit(withdrawal));accepted(c.receive(withdrawal));show("8. Late withdrawal visible; resolved request is not silently reopened",p,c);
  auto disposition=action(Kind::WithdrawalDisposition,"disposition",5);disposition.text="SYNTHETIC withdrawal reviewed";disposition.reference="withdrawal";accepted(c.submit(disposition));accepted(p.receive(disposition));
  auto reopen=action(Kind::Reopen,"reopen",6);reopen.revision=3;reopen.text="SYNTHETIC review late information";accepted(c.submit(reopen));accepted(p.receive(reopen));show("9. Explicit withdrawal disposition and reopen",p,c);
  return 0;
 }catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}
}
