#include "RescueDemoBridge.h"
#include "event_wire.hpp"
#include <sqlite3.h>
#include <chrono>
#include <filesystem>
#include <iostream>
#include <memory>
#include <string>
#include <vector>
#include <cstdlib>
using Endpoint=std::unique_ptr<rc_endpoint,decltype(&rc_endpoint_destroy)>;
void check(bool b,const char* m){if(!b){std::cerr<<m<<'\n';std::exit(1);}}
std::string snap(rc_endpoint* e){char* p=rc_endpoint_snapshot(e);check(p,"snapshot");std::string s(p);rc_free(p);return s;}
bool has(rc_endpoint* e,const char* v){return snap(e).find(v)!=std::string::npos;}
std::vector<unsigned char> next(rc_endpoint* e){size_t n=0;auto p=rc_endpoint_next(e,&n);check(p && n,"pending packet");std::vector<unsigned char> b(p,p+n);rc_free(p);return b;}
std::vector<unsigned char> accept(rc_endpoint* e,const std::vector<unsigned char>& packet,int expected=0){size_t n=0;unsigned char* p=nullptr;check(rc_endpoint_accept(e,packet.data(),packet.size(),&p,&n)==expected,"receiver result");check(p && n,"committed receipt");std::vector<unsigned char>b(p,p+n);rc_free(p);return b;}
void transfer(rc_endpoint* a,rc_endpoint* b){auto receipt=accept(b,next(a));check(rc_endpoint_confirm(a,receipt.data(),receipt.size())==0,"sender commits receipt");}
void action(rc_endpoint* e,int a,const char* v=""){check(rc_endpoint_perform(e,a,v,"")==0,"queued action");}
struct Lock{sqlite3* db=nullptr;explicit Lock(const std::string& path){check(sqlite3_open(path.c_str(),&db)==SQLITE_OK,"lock DB");check(sqlite3_exec(db,"BEGIN IMMEDIATE",nullptr,nullptr,nullptr)==SQLITE_OK,"lock");}~Lock(){sqlite3_exec(db,"ROLLBACK",nullptr,nullptr,nullptr);sqlite3_close(db);}};
int main(int argc,char** argv){
 check(argc==2,"scenario");const std::string scenario=argv[1];
 const auto dir=std::filesystem::temp_directory_path()/("rescue-endpoint-"+scenario+std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));std::filesystem::create_directory(dir);
 const auto pp=(dir/"public.sqlite").string(),cp=(dir/"command.sqlite").string();
 auto open=[&](const std::string& path,int role){Endpoint e(rc_endpoint_open(path.c_str(),role),rc_endpoint_destroy);check(bool(e),"independent endpoints must open");return e;};
 auto p=open(pp,0),c=open(cp,1);
 if(scenario=="exchange"){
  action(p.get(),RC_SOS,"Sample floor");check(has(c.get(),"\"hasRequest\":false"),"remote stays empty before exchange");
  auto packet=next(p.get()),receipt=accept(c.get(),packet);check(has(p.get(),"\"originalDelivery\":0"),"sender waiting before receipt");check(rc_endpoint_confirm(p.get(),receipt.data(),receipt.size())==0,"durable receipt");
  check(has(p.get(),"\"originalDelivery\":1"),"device receipt");action(c.get(),RC_ACKNOWLEDGE);check(has(p.get(),"\"originalDelivery\":1"),"human action not remotely visible before exchange");transfer(c.get(),p.get());check(has(p.get(),"\"originalDelivery\":2"),"human ack received");
  action(c.get(),RC_REPLY,"Sample reply");transfer(c.get(),p.get());action(p.get(),RC_CORRECTION,"Sample floor 4");transfer(p.get(),c.get());action(c.get(),RC_ASSIGN,"Sample team");transfer(c.get(),p.get());action(c.get(),RC_RESOLVE,"Sample completion");transfer(c.get(),p.get());action(p.get(),RC_WITHDRAWAL,"Sample withdrawal");transfer(p.get(),c.get());check(has(c.get(),"\"lateUpdate\":true"),"late flag local");action(c.get(),RC_DISPOSITION,"Sample decision");transfer(c.get(),p.get());action(c.get(),RC_REOPEN,"Sample reopen");transfer(c.get(),p.get());
 }else if(scenario=="retry"){
  action(p.get(),RC_SOS,"Sample floor");auto packet=next(p.get()),receipt=accept(c.get(),packet);const auto before=snap(c.get());p.reset();c.reset();p=open(pp,0);c=open(cp,1);
  check(next(p.get())==packet && snap(c.get())==before,"independent restart retains pending and committed history");auto repeated=accept(c.get(),packet,1);check(repeated==receipt && snap(c.get())==before,"lost receipt retry idempotent");
  action(c.get(),RC_ACKNOWLEDGE);transfer(c.get(),p.get());check(has(p.get(),"\"originalDelivery\":2") && has(p.get(),"\"pendingTransfers\":1"),"human ack may precede original receipt");p.reset();p=open(pp,0);check(has(p.get(),"\"pendingTransfers\":1"),"ack-before-receipt outbox reopens");check(rc_endpoint_confirm(p.get(),repeated.data(),repeated.size())==0,"repeated receipt confirms");check(rc_endpoint_confirm(p.get(),repeated.data(),repeated.size())==0,"duplicate receipt idempotent");
  action(c.get(),RC_REPLY,"Queued sample return");auto queued=next(c.get());c.reset();c=open(cp,1);check(next(c.get())==queued,"return outbox survives restart");transfer(c.get(),p.get());
 }else if(scenario=="locks"){
  action(p.get(),RC_SOS,"Sample floor");auto packet=next(p.get());{Lock lock(cp);size_t rn=99;unsigned char* r=nullptr;check(rc_endpoint_accept(c.get(),packet.data(),packet.size(),&r,&rn)==7 && !r && rn==0,"failed receiver commit yields no receipt");check(has(c.get(),"\"hasRequest\":false"),"failed inbound not visible");}
  auto receipt=accept(c.get(),packet);{Lock lock(pp);check(rc_endpoint_confirm(p.get(),receipt.data(),receipt.size())==7,"failed sender receipt commit");check(next(p.get())==packet && has(p.get(),"\"originalDelivery\":0"),"sender failure retains outbox and waiting");check(rc_endpoint_reset(p.get())==7,"failed local reset retains queue");}
  check(rc_endpoint_confirm(p.get(),receipt.data(),receipt.size())==0,"same handle retries sender receipt");p.reset();p=open(pp,0);check(has(p.get(),"\"pendingTransfers\":0"),"receipt removal persists");
 }else if(scenario=="isolation"){
  check(rc_endpoint_open(pp.c_str(),1)==nullptr && rc_open(pp.c_str())==nullptr,"role/simulation cannot open endpoint store");const auto sim=(dir/"sim.sqlite").string();auto* demo=rc_open(sim.c_str());check(demo,"simulation open");rc_destroy(demo);check(rc_endpoint_open(sim.c_str(),0)==nullptr,"endpoint cannot open simulation store");
  auto stale=open(pp,0);action(p.get(),RC_SOS,"Newer sample");check(rc_endpoint_perform(stale.get(),RC_SOS,"Stale sample","")==7,"stale endpoint rejected");stale.reset();p.reset();p=open(pp,0);check(has(p.get(),"Newer sample"),"newer data retained");check(rc_endpoint_perform(p.get(),RC_ACKNOWLEDGE,"","")==3,"wrong role action rejects");check(rc_endpoint_open(nullptr,0)==nullptr && rc_endpoint_open(pp.c_str(),2)==nullptr,"invalid args");
  action(p.get(),RC_FOLLOWUP,"Queued second event");p.reset();
  {sqlite3* db=nullptr;check(sqlite3_open(pp.c_str(),&db)==SQLITE_OK,"tamper open");check(sqlite3_exec(db,"UPDATE events SET position=position+100 WHERE area=2; UPDATE events SET position=CASE position WHEN 100 THEN 1 ELSE 0 END WHERE area=2",nullptr,nullptr,nullptr)==SQLITE_OK,"swap outbox");sqlite3_close(db);}
  check(rc_endpoint_open(pp.c_str(),0)==nullptr,"reordered outbox cannot reopen");
 }else if(scenario=="malformed"){
  action(p.get(),RC_SOS,"Sample floor");auto packet=next(p.get());const auto initial=snap(c.get());
  auto rejects=[&](std::vector<unsigned char> bad){size_t rn=0;unsigned char* r=nullptr;check(rc_endpoint_accept(c.get(),bad.data(),bad.size(),&r,&rn)==2 && !r && !rn,"invalid packet rejected");check(has(c.get(),"\"hasRequest\":false"),"invalid packet no mutation");};
  auto bad=packet;bad[0]='X';rejects(bad);bad=packet;bad.push_back(0);rejects(bad);bad=packet;bad.resize(20);rejects(bad);rejects(std::vector<unsigned char>(4097,1));bad=packet;bad[4]=255;rejects(bad);
  auto aliased=rescue_wire::decode(packet);aliased.id="command-1";rejects(rescue_wire::encode(aliased));
  auto e=rescue_wire::decode(packet);e.text=std::string(1,static_cast<char>(0xff));rejects(rescue_wire::encode(e));
  auto receipt=accept(c.get(),packet);auto wrongAuthor=rescue_wire::decode(receipt);wrongAuthor.author="public";wrongAuthor.destination="command";auto wrongBytes=rescue_wire::encode(wrongAuthor);check(rc_endpoint_confirm(p.get(),wrongBytes.data(),wrongBytes.size())==3,"head receipt must come from destination");
  action(p.get(),RC_FOLLOWUP,"Sample update");auto followup=next(p.get());check(followup==packet,"original remains first while waiting");
  auto forged=rescue_wire::decode(receipt);forged.reference="public-2";forged.id="receipt-public-2";auto wrong=rescue_wire::encode(forged);check(rc_endpoint_confirm(p.get(),wrong.data(),wrong.size())==2,"unrelated queued receipt cannot confirm first exchange");check(next(p.get())==packet,"mismatch retains head");
 }else if(scenario=="capacity"){
  action(p.get(),RC_SOS,"Sample floor");transfer(p.get(),c.get());for(int i=0;i<62;++i){action(p.get(),RC_FOLLOWUP,"Sample update");transfer(p.get(),c.get());}
  action(p.get(),RC_FOLLOWUP,"Sample last arrival");auto queued=next(p.get());accept(c.get(),queued);
  check(has(c.get(),"\"hasRequest\":true"),"receiver full committed");check(rc_endpoint_perform(p.get(),RC_FOLLOWUP,"Rejected receiver sample","")==6,"reserve space for all outstanding receipts");size_t n=0;unsigned char* r=nullptr;auto last=rescue_wire::decode(queued);++last.sequence;last.id="public-"+std::to_string(last.sequence);last.text="Rejected receiver sample";auto packet=rescue_wire::encode(last);check(rc_endpoint_accept(c.get(),packet.data(),packet.size(),&r,&n)==6 && !r,"receiver exhaustion returns no receipt");check(has(p.get(),"\"pendingTransfers\":1"),"full receiver leaves sender queued");
  p.reset();c.reset();p=open(pp,0);c=open(cp,1);check(has(p.get(),"\"pendingTransfers\":1"),"full pending reopens");auto recoveredReceipt=accept(c.get(),queued,1);check(rc_endpoint_confirm(p.get(),recoveredReceipt.data(),recoveredReceipt.size())==0,"reserved slot confirms receipt at capacity");check(rc_endpoint_reset(p.get())==0 && rc_endpoint_reset(c.get())==0,"coordinated reset");
  action(p.get(),RC_SOS,"Sample new exercise");for(int i=0;i<63;++i)action(p.get(),RC_FOLLOWUP,"Sample queued update");check(rc_endpoint_perform(p.get(),RC_FOLLOWUP,"Overflow","")==6 && has(p.get(),"\"pendingTransfers\":64"),"outbox bound rejects without dropping");p.reset();p=open(pp,0);check(has(p.get(),"\"pendingTransfers\":64"),"full queue reopens");
 }else check(false,"unknown scenario");
 p.reset();c.reset();std::filesystem::remove_all(dir);
}
