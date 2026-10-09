#include "RescueRelay.h"
#include "RescueDemoBridge.h"
#include <sqlite3.h>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <limits>
#include <memory>
#include <string>
#include <vector>
#include <fcntl.h>
#include <unistd.h>
#include <sys/wait.h>
using Relay=std::unique_ptr<rc_relay,decltype(&rc_relay_destroy)>;
using Item=std::unique_ptr<rc_relay_item,decltype(&rc_relay_item_free)>;
using Bytes=std::vector<unsigned char>;
constexpr int64_t later=1000;
void check(bool ok,const char* why){if(!ok){std::cerr<<why<<'\n';std::exit(1);}}
std::string hex(unsigned n){char buffer[65];std::snprintf(buffer,sizeof buffer,"%064x",n);return buffer;}
Bytes payload(std::size_t size,unsigned char seed){Bytes b(size);for(std::size_t i=0;i<size;++i)b[i]=static_cast<unsigned char>(seed+i);return b;}
std::string fileBytes(const std::string& path){std::ifstream file(path,std::ios::binary);return std::string((std::istreambuf_iterator<char>(file)),{});}
void sql(const std::string& path,const char* query){sqlite3* db=nullptr;check(sqlite3_open(path.c_str(),&db)==SQLITE_OK,"test DB open");const int r=sqlite3_exec(db,query,nullptr,nullptr,nullptr);sqlite3_close(db);check(r==SQLITE_OK,"test SQL");}
struct Hold{sqlite3* db=nullptr;Hold(const std::string& path,const char* begin){check(sqlite3_open(path.c_str(),&db)==SQLITE_OK,"lock DB");check(sqlite3_exec(db,begin,nullptr,nullptr,nullptr)==SQLITE_OK,"lock");}~Hold(){sqlite3_exec(db,"ROLLBACK",nullptr,nullptr,nullptr);sqlite3_close(db);}};
Relay open(const std::string& path){Relay r(rc_relay_open(path.c_str()),rc_relay_destroy);check(bool(r),"relay should open");return r;}
int enqueue(rc_relay* r,unsigned id,unsigned flow,int urgency,const Bytes& bytes,int64_t now=0,int64_t expiry=later,int hops=2){
    return rc_relay_enqueue(r,hex(id).c_str(),hex(flow).c_str(),urgency,expiry,hops,bytes.data(),bytes.size(),now);
}
Item select(rc_relay* r,int64_t now=0,int expected=RC_RELAY_OK){
    rc_relay_item* raw=reinterpret_cast<rc_relay_item*>(1);check(rc_relay_select(r,now,&raw)==expected,"select result");
    Item item(raw,rc_relay_item_free);check(expected==RC_RELAY_OK?item!=nullptr:item==nullptr,"selected output only on success");return item;
}
std::size_t count(rc_relay* r){std::size_t n=999;check(rc_relay_count(r,&n)==RC_RELAY_OK,"count");return n;}
bool is(const Item& item,unsigned id){return item && std::string(item->id)==hex(id);}
std::size_t descriptors(){std::size_t n=0;for(int fd=0;fd<4096;++fd)if(fcntl(fd,F_GETFD)!=-1)++n;return n;}

int main(int argc,char** argv){
    check(argc==2,"scenario required");const std::string scenario=argv[1];
    const auto dir=std::filesystem::temp_directory_path()/("rescue-relay-"+scenario+"-"+std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    std::filesystem::create_directories(dir);const auto path=(dir/"relay.sqlite").string();
    auto relay=open(path);auto* r=relay.get();
    const auto sealed=payload(181,1);
    if(scenario=="durable"){
        check(count(r)==0,"new queue empty");check(enqueue(r,1,10,1,sealed)==RC_RELAY_OK,"enqueue");
        auto other=open(path);check(count(other.get())==1,"independent handle sees committed item");
        auto item=select(other.get());check(is(item,1) && std::string(item->flow)==hex(10) && item->urgency==1 && item->expiry==later && item->remaining_hops==1 && item->attempts==1,"selected fields");
        check(Bytes(item->payload,item->payload+item->length)==sealed,"exact opaque bytes");
        relay.reset();other.reset();relay=open(path);r=relay.get();
        auto again=select(r);check(is(again,1) && again->attempts==2 && again->remaining_hops==1,"attempts persist; stored hop budget kept for retry");
        check(rc_relay_remove(r,hex(1).c_str())==RC_RELAY_OK && rc_relay_remove(r,hex(1).c_str())==RC_RELAY_EMPTY,"remove then absent");
        relay.reset();relay=open(path);check(count(relay.get())==0,"removal persists");
    }else if(scenario=="duplicate"){
        check(enqueue(r,1,10,0,sealed)==RC_RELAY_OK && enqueue(r,1,10,0,sealed)==RC_RELAY_DUPLICATE,"identical duplicate");
        check(enqueue(r,1,11,0,sealed)==RC_RELAY_CONFLICT,"changed flow");check(enqueue(r,1,10,1,sealed)==RC_RELAY_CONFLICT,"changed urgency");
        check(enqueue(r,1,10,0,sealed,0,later+1)==RC_RELAY_CONFLICT,"changed expiry");check(enqueue(r,1,10,0,sealed,0,later,1)==RC_RELAY_CONFLICT,"changed hops");
        auto altered=sealed;altered[100]^=1;check(enqueue(r,1,10,0,altered)==RC_RELAY_CONFLICT,"changed ciphertext");
        check(enqueue(r,1,10,0,payload(182,1))==RC_RELAY_CONFLICT,"changed length");
        select(r);check(enqueue(r,1,10,0,sealed,5)==RC_RELAY_DUPLICATE,"attempts and logical time are not identity");
        check(count(r)==1,"no duplicate rows");
        auto item=select(r);check(Bytes(item->payload,item->payload+item->length)==sealed && item->attempts==2,"original retained");
        const auto upper=std::string(63,'0')+"A",shortId=std::string(63,'0'),nonhex=std::string(63,'0')+"g";
        for(const auto& bad:{upper,shortId,nonhex,hex(1)+"0"})
            check(rc_relay_enqueue(r,bad.c_str(),hex(2).c_str(),0,later,1,sealed.data(),sealed.size(),0)==RC_RELAY_INVALID && rc_relay_enqueue(r,hex(2).c_str(),bad.c_str(),0,later,1,sealed.data(),sealed.size(),0)==RC_RELAY_INVALID && rc_relay_remove(r,bad.c_str())==RC_RELAY_INVALID,"exact lowercase hex64");
        check(rc_relay_enqueue(r,nullptr,hex(2).c_str(),0,later,1,sealed.data(),sealed.size(),0)==RC_RELAY_INVALID && rc_relay_enqueue(r,hex(2).c_str(),nullptr,0,later,1,sealed.data(),sealed.size(),0)==RC_RELAY_INVALID && rc_relay_enqueue(r,hex(2).c_str(),hex(2).c_str(),0,later,1,nullptr,181,0)==RC_RELAY_INVALID,"null inputs");
        check(rc_relay_remove(r,nullptr)==RC_RELAY_INVALID && rc_relay_select(r,0,nullptr)==RC_RELAY_INVALID && rc_relay_count(r,nullptr)==RC_RELAY_INVALID,"null outputs");
        rc_relay_item* item2=nullptr;std::size_t n=0;
        check(rc_relay_enqueue(nullptr,hex(2).c_str(),hex(2).c_str(),0,later,1,sealed.data(),sealed.size(),0)==RC_RELAY_NULL_HANDLE && rc_relay_select(nullptr,0,&item2)==RC_RELAY_NULL_HANDLE && !item2 && rc_relay_remove(nullptr,hex(1).c_str())==RC_RELAY_NULL_HANDLE && rc_relay_count(nullptr,&n)==RC_RELAY_NULL_HANDLE,"null handle");
        rc_relay_destroy(nullptr);rc_relay_item_free(nullptr);check(count(r)==1,"rejections do not mutate");
    }else if(scenario=="fifo"){
        check(enqueue(r,1,10,1,sealed)==0 && enqueue(r,2,10,1,payload(200,2))==0 && enqueue(r,3,20,1,sealed)==0,"two flows");
        for(int attempt=1;attempt<=8;++attempt){auto item=select(r);check(is(item,1) && item->attempts==attempt,"oldest flow head retried to limit");}
        for(int i=0;i<3;++i)check(is(select(r),3),"exhausted head blocks its own flow only");
        relay.reset();relay=open(path);r=relay.get();check(count(r)==3,"exhausted head retained");
        check(rc_relay_remove(r,hex(3).c_str())==0,"remove other flow");select(r,0,RC_RELAY_EMPTY);
        check(rc_relay_remove(r,hex(1).c_str())==0,"administrative removal of exhausted head");
        auto next=select(r);check(is(next,2) && next->attempts==1 && next->length==200,"dependency released in order");
        auto dependencies=open((dir/"dependencies.sqlite").string());
        check(enqueue(dependencies.get(),4,30,0,sealed)==0 && enqueue(dependencies.get(),5,30,1,sealed)==0 && enqueue(dependencies.get(),6,40,1,sealed)==0,"ordinary prerequisite and urgent follow-up");
        check(is(select(dependencies.get()),6),"independent urgent head wins");
        check(rc_relay_remove(dependencies.get(),hex(6).c_str())==0,"remove independent urgent");
        check(is(select(dependencies.get()),4),"urgent follow-up cannot bypass ordinary prerequisite");
        check(rc_relay_remove(dependencies.get(),hex(4).c_str())==0 && is(select(dependencies.get()),5),"follow-up eligible after prerequisite removed");
    }else if(scenario=="fairness"){
        unsigned id=1;
        auto add=[&](int urgency){check(enqueue(r,id,id,urgency,sealed)==0,"enqueue flow");return id++;};
        auto take=[&](int expected){auto item=select(r);check(item && item->urgency==expected,"fairness order");check(rc_relay_remove(r,item->id)==0,"delivered");};
        for(int i=0;i<8;++i)add(1);
        for(int i=0;i<2;++i)add(0);
        take(1);take(1);take(1);take(0);take(1);
        relay.reset();relay=open(path);r=relay.get();
        take(1);take(1);take(0);
        take(1);take(1);check(count(r)==0,"all delivered");
        for(int i=0;i<5;++i)add(1);
        take(1);take(1);take(1);take(1);add(0);
        relay.reset();relay=open(path);r=relay.get();take(0);take(1);check(count(r)==0,"late ordinary served after capped burst");
        add(0);add(1);take(1);take(0);
    }else if(scenario=="capacity"){
        const auto largest=payload(4276,9);
        for(unsigned i=1;i<=64;++i)check(enqueue(r,i,i,0,largest,0,i<=32?100:later)==0,"64 largest items");
        check(enqueue(r,65,65,1,sealed)==RC_RELAY_CAPACITY,"item bound without eviction");
        check(enqueue(r,64,64,0,largest)==RC_RELAY_DUPLICATE,"duplicate at capacity");
        relay.reset();relay=open(path);r=relay.get();check(count(r)==64,"full queue reopens");
        check(is(select(r,99),1),"oldest unexpired retained");
        check(enqueue(r,65,65,1,sealed,100)==RC_RELAY_OK && count(r)==33,"expired rows pruned on admission");
        check(is(select(r,100),65) && rc_relay_remove(r,hex(65).c_str())==0,"urgent admitted after pruning");
        check(enqueue(r,1,1,1,sealed,100,200,1)==RC_RELAY_OK,"expired ID reused with future expiry");
        check(is(select(r,199),1) && count(r)==33,"reused ID selectable");
        select(r,later,RC_RELAY_EMPTY);check(count(r)==0,"selection prunes expired rows");
    }else if(scenario=="bounds"){
        check(enqueue(r,1,1,0,payload(180,1))==RC_RELAY_INVALID && enqueue(r,1,1,0,payload(4277,1))==RC_RELAY_INVALID,"payload bounds");
        check(enqueue(r,1,1,2,sealed)==RC_RELAY_INVALID && enqueue(r,1,1,-1,sealed)==RC_RELAY_INVALID,"urgency bounds");
        check(enqueue(r,1,1,0,sealed,0,later,0)==RC_RELAY_INVALID && enqueue(r,1,1,0,sealed,0,later,3)==RC_RELAY_INVALID,"hop bounds");
        check(enqueue(r,1,1,0,sealed,-5,0)==RC_RELAY_INVALID && enqueue(r,1,1,0,sealed,-5,-1)==RC_RELAY_INVALID && enqueue(r,1,1,0,sealed,10,10)==RC_RELAY_INVALID,"positive future expiry");
        constexpr auto lowest=std::numeric_limits<int64_t>::min(),highest=std::numeric_limits<int64_t>::max();
        check(enqueue(r,1,1,0,payload(4276,3),lowest,highest,1)==0 && enqueue(r,2,2,1,sealed,lowest,1,2)==0,"signed64 logical time extremes");
        auto two=select(r,lowest);check(is(two,2) && two->remaining_hops==1,"two-hop budget decremented once");
        auto one=select(r,1);check(is(one,1) && one->expiry==highest && one->remaining_hops==0 && one->length==4276 && count(r)==1,"exclusive expiry boundary; single-hop budget");
        for(int attempt=2;attempt<=8;++attempt)check(select(r,highest-1)->attempts==attempt,"attempt count");
        select(r,highest-1,RC_RELAY_EMPTY);check(count(r)==1,"exhausted retained");
        check(rc_relay_remove(r,hex(1).c_str())==0,"cleanup");relay.reset();
        sql(path,"UPDATE relay_meta SET admissions=9223372036854775807");relay=open(path);r=relay.get();
        check(enqueue(r,3,3,0,sealed)==RC_RELAY_CAPACITY && count(r)==0,"admission counter overflow fails safely");
    }else if(scenario=="locks"){
        check(enqueue(r,1,1,0,sealed)==0,"saved");
        {Hold lock(path,"BEGIN IMMEDIATE");
         check(enqueue(r,2,2,0,sealed)==RC_RELAY_STORAGE,"locked enqueue");select(r,0,RC_RELAY_STORAGE);
         check(rc_relay_remove(r,hex(1).c_str())==RC_RELAY_STORAGE,"locked remove");}
        {Hold reader(path,"BEGIN; SELECT * FROM relay_items;");
         select(r,0,RC_RELAY_STORAGE);check(enqueue(r,2,2,0,sealed)==RC_RELAY_STORAGE,"commit lock enqueue");}
        check(count(r)==1,"failed writes rolled back");
        auto item=select(r);check(is(item,1) && item->attempts==1,"failed selections did not consume attempts");
        sql(path,"CREATE TRIGGER fail_save BEFORE UPDATE ON relay_items BEGIN SELECT RAISE(ABORT,'injected'); END;");
        select(r,0,RC_RELAY_STORAGE);check(rc_relay_open(path.c_str())==nullptr,"altered schema blocked");
        sql(path,"DROP TRIGGER fail_save");check(select(r)->attempts==2,"same handle recovers");
    }else if(scenario=="tamper"){
        check(enqueue(r,0xabc,1,1,sealed)==0 && enqueue(r,2,1,0,payload(300,4))==0,"base rows");select(r);relay.reset();
        const char* alterations[]={
            "CREATE TRIGGER extra AFTER INSERT ON relay_items BEGIN SELECT 1; END;",
            "CREATE INDEX extra ON relay_items(flow);",
            "CREATE TABLE extra(x);",
            "ALTER TABLE relay_items ADD COLUMN extra;",
            "PRAGMA application_id=1;","PRAGMA user_version=2;","PRAGMA user_version=17;",
            "UPDATE relay_items SET urgency='1' WHERE urgency=1;",
            "UPDATE relay_items SET urgency=2 WHERE urgency=1;",
            "UPDATE relay_items SET urgency=1.0 WHERE urgency=1;",
            "UPDATE relay_items SET attempts=9;","UPDATE relay_items SET attempts=-1;","UPDATE relay_items SET attempts='1';",
            "UPDATE relay_items SET hops=3;","UPDATE relay_items SET hops=0;",
            "UPDATE relay_items SET expiry=0;","UPDATE relay_items SET expiry='1000';",
            "UPDATE relay_items SET admitted=admitted+10;","UPDATE relay_items SET admitted=0 WHERE admitted=1;","UPDATE relay_items SET admitted='1' WHERE admitted=1;",
            "UPDATE relay_items SET payload=CAST(payload AS TEXT);","UPDATE relay_items SET payload=zeroblob(180);","UPDATE relay_items SET payload=zeroblob(4277);",
            "UPDATE relay_items SET id=upper(id) WHERE admitted=1;","UPDATE relay_items SET flow=substr(flow,2) WHERE admitted=1;","UPDATE relay_items SET id=CAST(id AS BLOB) WHERE admitted=1;",
            "UPDATE relay_meta SET urgent_burst=4;","UPDATE relay_meta SET urgent_burst='1';","UPDATE relay_meta SET admissions=1;","UPDATE relay_meta SET admissions=-1;",
            "DELETE FROM relay_meta;",
            "UPDATE relay_items SET admitted=CASE admitted WHEN 1 THEN 9223372036854775807 ELSE 'late' END; UPDATE relay_meta SET admissions=9223372036854775807;",
        };
        const auto base=fileBytes(path);int index=0;
        for(const char* change:alterations){
            const auto copy=(dir/("tamper-"+std::to_string(index++)+".sqlite")).string();
            {std::ofstream out(copy,std::ios::binary);out<<base;}
            auto live=open(copy);sql(copy,change);const auto altered=fileBytes(copy);
            std::size_t n=0;if(rc_relay_count(live.get(),&n)!=RC_RELAY_STORAGE){std::cerr<<change<<'\n';check(false,"open handle revalidates");}live.reset();
            if(rc_relay_open(copy.c_str())!=nullptr){std::cerr<<change<<'\n';check(false,"tampered store must not open");}
            check(fileBytes(copy)==altered,"tampered file preserved");
        }
        relay=open(path);check(count(relay.get())==2,"untampered original still valid");
    }else if(scenario=="incompatible"){
        relay.reset();
        check(rc_relay_open(nullptr)==nullptr && rc_relay_open("relative.sqlite")==nullptr && rc_relay_open(std::string(4097,'/').c_str())==nullptr && rc_relay_open(dir.c_str())==nullptr,"invalid paths");
        const auto endpoint=(dir/"endpoint.sqlite").string(),training=(dir/"training.sqlite").string();
        auto* e=rc_endpoint_open(endpoint.c_str(),0);check(e!=nullptr,"endpoint store");rc_endpoint_destroy(e);
        auto* t=rc_open(training.c_str());check(t!=nullptr,"training store");rc_destroy(t);
        for(const auto& foreign:{endpoint,training}){const auto before=fileBytes(foreign);check(rc_relay_open(foreign.c_str())==nullptr && fileBytes(foreign)==before,"foreign store rejected and preserved");}
        check(rc_open(path.c_str())==nullptr && rc_endpoint_open(path.c_str(),0)==nullptr && rc_endpoint_open(path.c_str(),1)==nullptr,"relay store distinct from endpoint/training");
        const auto junk=(dir/"junk.sqlite").string();{std::ofstream out(junk);out<<"Not a SQLite database, synthetic junk bytes";}
        check(rc_relay_open(junk.c_str())==nullptr && fileBytes(junk)=="Not a SQLite database, synthetic junk bytes","junk preserved");
        const auto wal=(dir/"wal.sqlite").string();{auto w=open(wal);check(enqueue(w.get(),1,1,0,sealed)==0,"wal base");}
        sql(wal,"PRAGMA journal_mode=WAL;");const auto walBytes=fileBytes(wal);
        check(rc_relay_open(wal.c_str())==nullptr && fileBytes(wal)==walBytes,"WAL store rejected and preserved");
        relay=open(path);check(count(relay.get())==0,"relay store still opens");
    }else if(scenario=="journal"){
        relay.reset();
        const auto foreign=(dir/"foreign.sqlite").string();
        sql(foreign,"CREATE TABLE notes(body); WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<64) INSERT INTO notes SELECT zeroblob(8192) FROM n;");
        const auto committed=fileBytes(foreign);
        const auto child=fork();check(child>=0,"fork crash fixture");
        if(child==0){
            sqlite3* db=nullptr;
            if(sqlite3_open(foreign.c_str(),&db)!=SQLITE_OK)_exit(2);
            if(sqlite3_exec(db,"PRAGMA cache_size=1; PRAGMA cache_spill=ON; BEGIN IMMEDIATE; UPDATE notes SET body=randomblob(8192);",nullptr,nullptr,nullptr)!=SQLITE_OK)_exit(3);
            _exit(0); // Intentionally abandon the transaction without SQLite cleanup.
        }
        int status=0;check(waitpid(child,&status,0)==child && WIFEXITED(status) && WEXITSTATUS(status)==0,"child crashed after writes");
        const auto before=fileBytes(foreign),journal=fileBytes(foreign+"-journal");
        check(before!=committed && journal.size()>512,"real spilled transaction needs recovery");
        check(rc_relay_open(foreign.c_str())==nullptr,"foreign hot journal rejected");
        check(fileBytes(foreign)==before && fileBytes(foreign+"-journal")==journal,"foreign main file and hot journal preserved before recovery");
        relay=open(path);r=relay.get();
        for(unsigned i=1;i<=64;++i)check(enqueue(r,i,i,0,payload(4276,i))==0,"owned recovery fixture");
        relay.reset();const auto owned=fileBytes(path);
        const auto writer=fork();check(writer>=0,"fork owned fixture");
        if(writer==0){
            sqlite3* db=nullptr;if(sqlite3_open(path.c_str(),&db)!=SQLITE_OK)_exit(2);
            if(sqlite3_exec(db,"PRAGMA cache_size=1; PRAGMA cache_spill=ON; BEGIN IMMEDIATE; UPDATE relay_items SET attempts=7;",nullptr,nullptr,nullptr)!=SQLITE_OK)_exit(3);
            _exit(0);
        }
        check(waitpid(writer,&status,0)==writer && WIFEXITED(status) && WEXITSTATUS(status)==0,"owned crash after writes");
        check(fileBytes(path)!=owned && fileBytes(path+"-journal").size()>512,"owned transaction spilled");
        relay=open(path);r=relay.get();
        check(count(r)==64 && select(r)->attempts==1,"owned hot journal recovers committed queue and attempts");

    }else if(scenario=="descriptors"){
        check(enqueue(r,1,1,0,sealed)==0,"saved");relay.reset();
        const auto junk=(dir/"junk.sqlite").string();{std::ofstream out(junk);out<<"Not a SQLite database, synthetic junk bytes";}
        const auto future=(dir/"future.sqlite").string();{auto f=open(future);}sql(future,"PRAGMA user_version=17");
        const auto before=descriptors();
        for(int i=0;i<10;++i){check(rc_relay_open(junk.c_str())==nullptr && rc_relay_open(future.c_str())==nullptr,"rejected open");}
        check(descriptors()==before,"rejected opens close SQLite descriptors");
        for(int i=0;i<10;++i){auto again=open(path);check(count(again.get())==1,"reopen");}
        check(descriptors()==before,"successful handles close descriptors");
        relay=open(path);
    }else check(false,"unknown scenario");
    relay.reset();std::filesystem::remove_all(dir);
}
