#include "workflow.hpp"
#include <iostream>
#include <stdexcept>
using namespace rescue;
static void check(bool condition, const char* message) { if (!condition) throw std::runtime_error(message); }
static const std::map<std::string, Role> members{{"public-a",Role::Public},{"public-b",Role::Public},{"command",Role::Command}};
static Event request() { Event e; e.id="sos";e.exercise="drill";e.request="req";e.author="public-a";e.destination="command";e.text="SYNTHETIC help";e.reportedLocation="Test building / floor unknown";return e; }
static Event update(Kind kind, std::string id, std::uint64_t seq) { auto e=request(); e.kind=kind;e.id=std::move(id);e.sequence=seq;e.reportedLocation.clear();return e; }
static Event action(Kind kind, std::string id, std::uint64_t seq) { auto e=update(kind,std::move(id),seq);e.author="command";e.destination="public-a";e.text="SYNTHETIC action";return e; }
static void seed(Model& a, Model& c) { check(a.submit(request())==Result::Accepted,"local SOS accepted");check(c.receive(request())==Result::Accepted,"destination accepts SOS"); }
static void transfer(Model& a, Model& c, const Event& e) { check(a.submit(e)==Result::Accepted,"submit action");check(c.receive(e)==Result::Accepted,"deliver action"); }
static void receipt(Model& source, Model& destination, const std::string& id, const std::string& receiptID) {
 auto r=destination.receiptFor(id,receiptID);check(r.has_value(),"receipt created only for accepted inbound event");transfer(destination,source,*r);
}
static void roundtrip() {
 Model a("public-a","drill",members),c("command","drill",members);seed(a,c);
 check(a.delivery("sos")==Delivery::Waiting,"receive alone cannot change sender state");
 receipt(a,c,"sos","r1");check(a.delivery("sos")==Delivery::DeviceReceived,"device receipt differs from acknowledgment");
 auto ack=action(Kind::Acknowledgment,"ack",1);ack.reference="sos";
 check(c.submit(ack)==Result::Accepted,"explicit human action");check(a.delivery("sos")==Delivery::DeviceReceived,"undelivered acknowledgment stays local");
 check(a.receive(ack)==Result::Accepted,"ack reaches requester");check(a.delivery("sos")==Delivery::HumanAcknowledged,"human acknowledged");
 check(c.delivery("ack")==Delivery::Waiting,"return acknowledgment has independent delivery");receipt(c,a,"ack","r2");
 check(c.delivery("ack")==Delivery::DeviceReceived,"requester device receipt never means read");
 auto reply=action(Kind::Reply,"reply",2);transfer(c,a,reply);receipt(c,a,"reply","r3");
 check(!a.receiptFor("r3","loop"),"no receipt loop");
 check(a.receive(ack)==Result::Duplicate,"duplicate acknowledgment idempotent");
}
static void updates() {
 Model a("public-a","drill",members),c("command","drill",members);seed(a,c);
 auto ack=action(Kind::Acknowledgment,"ack",1);ack.reference="sos";transfer(c,a,ack);
 auto corr=update(Kind::Correction,"corr",2);corr.reportedLocation="Test floor 4";check(a.submit(corr)==Result::Accepted,"correction queued");
 auto s=*a.snapshot("req");check(s.originalDelivery==Delivery::HumanAcknowledged,"original acknowledgment retained");check(s.latestPublicDelivery==Delivery::Waiting,"new correction not acknowledged implicitly");
 check(c.snapshot("req")->reportedLocation!=corr.reportedLocation,"outage preserves remote location");
 check(c.receive(corr)==Result::Accepted,"correction received");receipt(a,c,"corr","rc");
 auto withdraw=update(Kind::Withdrawal,"withdraw",3);transfer(a,c,withdraw);
 check(c.snapshot("req")->withdrawalRequested,"withdrawal visible");check(c.snapshot("req")->handling==Handling::Open,"withdrawal does not resolve");
 auto disposition=action(Kind::WithdrawalDisposition,"disposition",2);disposition.reference="withdraw";transfer(c,a,disposition);
 check(!a.snapshot("req")->withdrawalDisposition.empty(),"disposition preserved");check(a.snapshot("req")->handling==Handling::Open,"disposition independent of handling");
}
static void handling() {
 Model a("public-a","drill",members),c("command","drill",members);seed(a,c);
 auto assign=action(Kind::Assignment,"assign",1);assign.revision=1;transfer(c,a,assign);
 auto resolve=action(Kind::Resolution,"resolve",2);resolve.revision=2;resolve.seenPublicSequence=1;transfer(c,a,resolve);
 auto corr=update(Kind::Correction,"late",2);corr.reportedLocation="Test floor 5";transfer(a,c,corr);
 check(c.snapshot("req")->handling==Handling::Resolved && c.snapshot("req")->lateUpdate,"late update stays visible while resolved");
 auto reopen=action(Kind::Reopen,"reopen",3);reopen.revision=3;transfer(c,a,reopen);
 check(c.snapshot("req")->handling==Handling::Open && !c.snapshot("req")->lateUpdate,"explicit reopen");
 auto bad=resolve;bad.id="stale";bad.sequence=4;check(c.submit(bad)==Result::Conflict,"stale handling revision rejected");
}
static void ownership() {
 Model a("public-a","drill",members),c("command","drill",members);seed(a,c);
 auto fake=update(Kind::Correction,"fake",2);fake.author="public-b";fake.reportedLocation="Wrong floor";
 check(c.receive(fake)==Result::Unauthorized,"other requester cannot edit request");
 fake=action(Kind::Resolution,"fake-r",2);fake.author="public-a";fake.destination="command";fake.revision=1;
 check(c.receive(fake)==Result::Unauthorized,"public cannot act as responder");
 fake=request();fake.id="wrong-drill";fake.exercise="other";check(c.receive(fake)==Result::Invalid,"wrong exercise");
 auto ack=action(Kind::Acknowledgment,"ack",1);ack.reference="sos";check(a.submit(ack)==Result::Unauthorized,"cannot submit another actor action");
 fake=request();fake.id="wrong-recipient";fake.destination="public-b";check(c.receive(fake)==Result::Unauthorized,"wrong destination");
 check(c.events().size()==1,"rejections do not mutate state");
}
static void references() {
 Model a("public-a","drill",members),c("command","drill",members);seed(a,c);
 auto ack=action(Kind::Acknowledgment,"ack",1);ack.reference="unknown";check(a.receive(ack)==Result::MissingDependency,"missing acknowledgment target");
 auto r=c.receiptFor("sos","r");check(r.has_value(),"valid receipt fixture");r->author="public-b";check(a.receive(*r)==Result::Unauthorized,"receipt issuer must be intended destination");
 auto other=update(Kind::Request,"other",1);other.request="other-request";transfer(a,c,other);
 ack.reference="other";check(a.receive(ack)==Result::Invalid,"cross-request acknowledgment rejected");
 r=c.receiptFor("sos","r");r->request="other-request";check(a.receive(*r)==Result::Invalid,"cross-request receipt rejected");
}
static void failures() {
 Model a("public-a","drill",members),c("command","drill",members);a.failNextStore();
 check(a.submit(request())==Result::StoreFailure,"failed local store");check(a.events().empty()&&!a.snapshot("req"),"no queued success after failure");
 check(a.submit(request())==Result::Accepted,"retry local store");c.failNextStore();check(c.receive(request())==Result::StoreFailure,"failed inbound store");
 check(!c.receiptFor("sos","r"),"no receipt for failed inbound acceptance");check(c.receive(request())==Result::Accepted,"retry inbound");
 auto conflict=request();conflict.text="changed";check(c.receive(conflict)==Result::Conflict,"same ID altered content rejected");
}
static void ordering() {
 Model a("public-a","drill",members),c("command","drill",members);seed(a,c);
 auto newest=update(Kind::Correction,"newest",3);newest.reportedLocation="Floor 6";transfer(a,c,newest);
 auto old=update(Kind::Correction,"old",2);old.reportedLocation="Floor 2";transfer(a,c,old);
 check(c.snapshot("req")->reportedLocation=="Floor 6","old arrival cannot overwrite newer location");
 auto collision=old;collision.id="same-sequence";check(c.receive(collision)==Result::Conflict,"same author sequence conflicts");
 auto ack=action(Kind::Acknowledgment,"ack",1);ack.reference="sos";transfer(c,a,ack);receipt(a,c,"sos","late-receipt");
 check(a.delivery("sos")==Delivery::HumanAcknowledged,"late weaker receipt cannot regress acknowledgment");
 auto future=action(Kind::Resolution,"future",2);future.revision=2;future.seenPublicSequence=3;check(c.submit(future)==Result::MissingDependency,"handling gap rejected for retry");
}
static void limits() {
 Model a("public-a","drill",members,1);check(a.submit(request())==Result::Accepted,"fill bounded store");
 auto updateEvent=update(Kind::FollowUp,"update",2);check(a.submit(updateEvent)==Result::Full,"full store reports failure");check(a.events().size()==1,"full store unchanged");
 Model b("public-a","drill",members);auto oversized=request();oversized.text=std::string(2049,'x');check(b.submit(oversized)==Result::Invalid,"body limit");
 oversized=request();oversized.id=std::string(65,'x');check(b.submit(oversized)==Result::Invalid,"ID limit");
 auto unknown=request();unknown.kind=static_cast<Kind>(99);check(b.submit(unknown)==Result::Invalid,"unknown kind");
}

static void lateGap() {
 Model a("public-a","drill",members),c("command","drill",members);seed(a,c);
 auto corr=update(Kind::Correction,"delayed-correction",2);corr.reportedLocation="Floor 7";check(a.submit(corr)==Result::Accepted,"queue correction");
 auto follow=update(Kind::FollowUp,"follow",3);transfer(a,c,follow);
 auto resolve=action(Kind::Resolution,"resolve",1);resolve.revision=1;resolve.seenPublicSequence=3;transfer(c,a,resolve);
 check(!c.snapshot("req")->lateUpdate,"no late arrival yet");
 check(c.receive(corr)==Result::Accepted,"older gap correction accepted");
 check(c.snapshot("req")->lateUpdate,"late gap must flag changed location after resolution");
}
static void repeatedWithdrawal() {
 Model a("public-a","drill",members),c("command","drill",members);seed(a,c);
 auto first=update(Kind::Withdrawal,"withdraw",2);transfer(a,c,first);
 auto decision=action(Kind::WithdrawalDisposition,"decision",1);decision.reference="withdraw";transfer(c,a,decision);
 auto second=update(Kind::Withdrawal,"withdraw-again",3);transfer(a,c,second);
 check(a.snapshot("req")->withdrawalPending,"latest withdrawal requires own disposition");
 check(a.snapshot("req")->withdrawalDisposition.empty(),"new withdrawal cannot inherit old disposition");
 decision.id="wrong-target";decision.sequence=2;decision.reference="sos";check(c.submit(decision)==Result::Invalid,"disposition must reference withdrawal");
}
static void dependencyRetry() {
 Model a("public-a","drill",members),c("command","drill",members);
 auto follow=update(Kind::FollowUp,"follow",2);
 check(c.receive(follow)==Result::MissingDependency && c.events().empty(),"pre-SOS update stored nowhere");seed(a,c);
 check(a.submit(follow)==Result::Accepted && c.receive(follow)==Result::Accepted,"retry update after SOS");
 auto assign=action(Kind::Assignment,"assign",1);assign.revision=1;check(c.submit(assign)==Result::Accepted,"local assignment");
 auto resolve=action(Kind::Resolution,"resolve",2);resolve.revision=2;resolve.seenPublicSequence=2;check(c.submit(resolve)==Result::Accepted,"local resolution");
 const auto size=a.events().size();check(a.receive(resolve)==Result::MissingDependency && a.events().size()==size,"missing handling predecessor stores nothing");
 check(a.receive(assign)==Result::Accepted && a.receive(resolve)==Result::Accepted,"retry after predecessor");
 check(a.events().size()==size+2 && a.snapshot("req")->handling==Handling::Resolved,"retried projection correct");
}
static void invalidHandling() {
 Model a("public-a","drill",members),c("command","drill",members);seed(a,c);
 auto reopen=action(Kind::Reopen,"reopen",1);reopen.revision=1;check(c.submit(reopen)==Result::Invalid,"open cannot reopen");
 auto disposition=action(Kind::WithdrawalDisposition,"disposition",1);disposition.reference="missing";check(c.submit(disposition)==Result::MissingDependency,"unknown withdrawal");
 auto resolution=action(Kind::Resolution,"resolve",1);resolution.revision=1;resolution.seenPublicSequence=1;transfer(c,a,resolution);
 auto assign=action(Kind::Assignment,"assign",2);assign.revision=2;check(c.submit(assign)==Result::Invalid,"resolved cannot assign");
 resolution.id="resolve-again";resolution.sequence=2;resolution.revision=2;check(c.submit(resolution)==Result::Invalid,"resolved cannot resolve again");
 reopen.sequence=2;reopen.revision=2;reopen.text.clear();check(c.submit(reopen)==Result::Invalid,"reopen requires reason");
}


static void hiddenUpdate() {
 Model a("public-a","drill",members),c("command","drill",members);seed(a,c);
 auto ack=action(Kind::Acknowledgment,"ack",1);ack.reference="sos";transfer(c,a,ack);
 auto corr=update(Kind::Correction,"lost-correction",2);corr.reportedLocation="Floor 8";check(a.submit(corr)==Result::Accepted,"queue correction");
 auto follow=update(Kind::FollowUp,"follow",3);transfer(a,c,follow);
 auto ackFollow=action(Kind::Acknowledgment,"ack-follow",2);ackFollow.reference="follow";transfer(c,a,ackFollow);
 auto s=*a.snapshot("req");check(s.latestPublicDelivery==Delivery::HumanAcknowledged,"latest message acknowledged");
 check(s.pendingPublicMessages==1,"latest delivery cannot hide pending correction");
 check(s.publicMessages.size()==3,"all public message delivery states available");
 bool found=false;for(const auto& m:s.publicMessages) if(m.eventID=="lost-correction") found=m.delivery==Delivery::Waiting;
 check(found,"correction retains own waiting status");
}

int main(int argc,char**argv) {
 try {
  check(argc==2,"scenario argument required");const std::map<std::string,void(*)()> cases{{"roundtrip",roundtrip},{"updates",updates},{"handling",handling},{"ownership",ownership},{"references",references},{"failures",failures},{"ordering",ordering},{"limits",limits},{"late_gap",lateGap},{"repeated_withdrawal",repeatedWithdrawal},{"dependency_retry",dependencyRetry},{"invalid_handling",invalidHandling},{"hidden_update",hiddenUpdate}};
  cases.at(argv[1])();std::cout<<"PASS "<<argv[1]<<'\n';return 0;
 } catch(const std::exception& e) { std::cerr<<"FAIL: "<<e.what()<<'\n';return 1; }
}
