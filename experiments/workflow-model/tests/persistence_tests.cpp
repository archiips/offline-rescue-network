#include "RescueDemoBridge.h"
#include <sqlite3.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <memory>
#include <string>
#include <cstdlib>
#include <unistd.h>
#include <sys/wait.h>
using Session=std::unique_ptr<rc_session,decltype(&rc_destroy)>;
void check(bool ok,const char* why) {if(!ok){std::cerr<<why<<'\n';std::exit(1);}}
std::string snapshot(rc_session* s) {char* p=rc_snapshot(s);check(p,"snapshot");std::string r(p);rc_free(p);return r;}
void sql(sqlite3* db,const char* q) {check(sqlite3_exec(db,q,nullptr,nullptr,nullptr)==SQLITE_OK,"test SQL");}
struct DB {sqlite3* value=nullptr;explicit DB(const std::string& path){check(sqlite3_open(path.c_str(),&value)==SQLITE_OK,"test DB open");}~DB(){sqlite3_close(value);}};
Session open(const std::string& p){Session s(rc_open(p.c_str()),rc_destroy);check(bool(s),"persistent session should open");return s;}
std::string fileBytes(const std::string& path) {std::ifstream file(path,std::ios::binary);return std::string((std::istreambuf_iterator<char>(file)),{});}
void act(rc_session* s,int action,const char* value="",const char* ref="") {check(rc_perform(s,action,value,ref)==0,"action accepted");}
bool contains(rc_session* s,const char* value){return snapshot(s).find(value)!=std::string::npos;}
int main(int argc,char** argv) {
    check(argc==2,"scenario required");const std::string scenario=argv[1];
    const auto dir=std::filesystem::temp_directory_path()/("rescue-persistence-"+scenario+"-"+std::to_string(getpid()));
    std::filesystem::create_directories(dir);const auto path=(dir/"session.sqlite").string();
    auto s=open(path);
    if(scenario=="restart") {
        check(rc_set_connected(s.get(),0)==0,"disconnect");act(s.get(),RC_SOS,"Sample floor 4");
        const auto before=snapshot(s.get());s.reset();s=open(path);check(snapshot(s.get())==before,"restart preserves offline queue");
        check(rc_set_connected(s.get(),1)==0,"reconnect");check(rc_set_connected(s.get(),0)==0,"disconnect return");
        act(s.get(),RC_ACKNOWLEDGE);act(s.get(),RC_CORRECTION,"Sample floor 2");act(s.get(),RC_REPLY,"Sample reply");
        const auto queued=snapshot(s.get());s.reset();s=open(path);check(snapshot(s.get())==queued,"both directional queues survive restart");
        check(rc_set_connected(s.get(),1)==0,"deliver returns");check(contains(s.get(),"\"originalDelivery\":2"),"acknowledgment arrived");
        act(s.get(),RC_ASSIGN,"Sample team");act(s.get(),RC_RESOLVE,"Sample completion");act(s.get(),RC_WITHDRAWAL,"Sample withdrawal");
        const auto late=snapshot(s.get());s.reset();s=open(path);check(snapshot(s.get())==late && contains(s.get(),"\"lateUpdate\":true"),"acceptance-order handling replay");
        act(s.get(),RC_DISPOSITION,"Sample decision");act(s.get(),RC_REOPEN,"Sample review");
        check(rc_reset(s.get())==0,"reset");s.reset();s=open(path);check(!contains(s.get(),"\"hasRequest\":true") && contains(s.get(),"\"pendingTransfers\":0"),"reset persists");
    } else if(scenario=="failure") {
        act(s.get(),RC_SOS,"Sample floor");const auto before=snapshot(s.get());
        {DB db(path);sql(db.value,"CREATE TRIGGER fail_save BEFORE INSERT ON events BEGIN SELECT RAISE(ABORT,'injected'); END; CREATE TRIGGER fail_meta BEFORE UPDATE ON session BEGIN SELECT RAISE(ABORT,'injected reset'); END;");}
        check(rc_perform(s.get(),RC_FOLLOWUP,"Rejected sample","")==7,"failed save returns store error");
        check(!contains(s.get(),"Rejected sample"),"no unsaved event published");
        check(rc_reset(s.get())==7 && contains(s.get(),"\"hasRequest\":true"),"failed reset retains request");
        check(rc_open(path.c_str())==nullptr,"unexpected trigger schema blocked on open");
        {DB db(path);sql(db.value,"DROP TRIGGER fail_save; DROP TRIGGER fail_meta");}
        s.reset();s=open(path);check(snapshot(s.get())==before,"failed schema write preserves disk state");
        act(s.get(),RC_FOLLOWUP,"Saved sample");check(contains(s.get(),"public-2") && !contains(s.get(),"public-3"),"failed writes do not consume sequence");
    } else if(scenario=="lock") {
        act(s.get(),RC_SOS,"Sample floor");
        {DB db(path);sql(db.value,"BEGIN IMMEDIATE");check(rc_perform(s.get(),RC_CORRECTION,"Blocked floor","")==7,"locked write rejects");check(!contains(s.get(),"Blocked floor"),"locked write invisible");sql(db.value,"ROLLBACK");}
        act(s.get(),RC_CORRECTION,"Saved floor");s.reset();s=open(path);check(contains(s.get(),"Saved floor"),"retry saves after lock release");
    } else if(scenario=="stale") {
        auto stale=open(path);act(s.get(),RC_SOS,"Newer sample");
        check(rc_perform(stale.get(),RC_SOS,"Stale sample","")==7,"stale generation rejects");
        stale.reset();s.reset();s=open(path);check(contains(s.get(),"Newer sample") && !contains(s.get(),"Stale sample"),"stale state cannot overwrite");
    } else if(scenario=="corrupt") {
        check(rc_open(nullptr)==nullptr && rc_open("relative.sqlite")==nullptr && rc_reset(nullptr)==-1,"invalid bridge arguments");
        const std::string oversized(4097,'x');check(rc_open(oversized.c_str())==nullptr,"path bound");
        s.reset();{DB db(path);sql(db.value,"PRAGMA user_version=99");}
        check(rc_open(path.c_str())==nullptr,"future schema blocked");
        {DB db(path);sql(db.value,"PRAGMA user_version=1");}
        s=open(path);check(rc_set_connected(s.get(),0)==0,"offline");act(s.get(),RC_SOS,"Queued sample");s.reset();
        {DB db(path);sql(db.value,"DELETE FROM events WHERE area=2");}
        check(rc_open(path.c_str())==nullptr,"missing durable outbox blocked");
        const auto invalid=(dir/"corrupt.sqlite").string();{std::ofstream file(invalid);file<<"Not a SQLite database";}
        check(rc_open(invalid.c_str())==nullptr,"damaged file blocked");
        std::ifstream file(invalid);std::string bytes((std::istreambuf_iterator<char>(file)),{});check(bytes=="Not a SQLite database","damaged file preserved");
    } else if(scenario=="interrupted") {
        act(s.get(),RC_SOS,"Committed sample");const auto before=snapshot(s.get());s.reset();const auto diskBefore=fileBytes(path);
        const auto child=fork();check(child>=0,"fork");
        if(child==0) {DB db(path);sql(db.value,"PRAGMA cache_size=1; BEGIN IMMEDIATE; DELETE FROM events; UPDATE session SET connected=0;");check(sqlite3_db_cacheflush(db.value)==SQLITE_OK,"flush uncommitted pages");check(std::filesystem::exists(path+"-journal"),"rollback journal present");_exit(0);}
        int status=0;check(waitpid(child,&status,0)==child && WIFEXITED(status) && WEXITSTATUS(status)==0,"child transaction interrupted");
        check(fileBytes(path)!=diskBefore && std::filesystem::exists(path+"-journal"),"dirty main pages and journal before recovery");
        s=open(path);check(snapshot(s.get())==before,"uncommitted process exit recovers prior state");
    } else if(scenario=="commit_lock") {
        act(s.get(),RC_SOS,"Committed sample");const auto before=snapshot(s.get());
        {DB reader(path);sql(reader.value,"BEGIN; SELECT * FROM session;");
         check(rc_perform(s.get(),RC_FOLLOWUP,"Blocked at commit","")==7,"commit lock fails");
         check(!contains(s.get(),"Blocked at commit"),"uncommitted action invisible");sql(reader.value,"ROLLBACK");}
        {auto disk=open(path);check(snapshot(disk.get())==before,"commit failure rolls back disk rows");}
        act(s.get(),RC_FOLLOWUP,"Retry after read lock");
        s.reset();s=open(path);check(contains(s.get(),"Retry after read lock"),"same handle recovers after failed commit");
    } else if(scenario=="initialization") {
        const auto empty=(dir/"empty.sqlite").string();{std::ofstream file(empty);}
        auto initialized=open(empty);act(initialized.get(),RC_SOS,"Recovered empty initialization");initialized.reset();
        const auto interrupted=(dir/"initializing.sqlite").string();const auto child=fork();check(child>=0,"initialization fork");
        if(child==0) {DB db(interrupted);sql(db.value,"PRAGMA cache_size=1; BEGIN IMMEDIATE; CREATE TABLE unfinished(x TEXT); INSERT INTO unfinished VALUES('sample');");check(sqlite3_db_cacheflush(db.value)==SQLITE_OK,"flush interrupted schema");_exit(0);}
        int status=0;check(waitpid(child,&status,0)==child && WIFEXITED(status) && WEXITSTATUS(status)==0,"schema process interrupted");
        check(std::filesystem::file_size(interrupted)>0 && std::filesystem::exists(interrupted+"-journal"),"dirty initializing file and journal before recovery");
        auto recovered=open(interrupted);check(!contains(recovered.get(),"\"hasRequest\":true"),"unfinished schema recovers to fresh valid session");act(recovered.get(),RC_SOS,"New saved sample");
    } else if(scenario=="wal") {
        act(s.get(),RC_SOS,"Preserved sample");s.reset();
        const auto child=fork();check(child>=0,"WAL fork");
        if(child==0) {DB db(path);sql(db.value,"PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; UPDATE session SET connected=0;");_exit(0);}
        int status=0;check(waitpid(child,&status,0)==child && WIFEXITED(status) && WEXITSTATUS(status)==0,"WAL child exited");
        check(std::filesystem::exists(path+"-wal") && std::filesystem::exists(path+"-shm"),"WAL sidecars exist");
        const auto main=fileBytes(path),wal=fileBytes(path+"-wal"),shm=fileBytes(path+"-shm");
        check(rc_open(path.c_str())==nullptr,"unsupported WAL rejected before open");
        check(fileBytes(path)==main && fileBytes(path+"-wal")==wal && fileBytes(path+"-shm")==shm,"rejected WAL files preserved byte for byte");
    } else if(scenario=="full") {
        act(s.get(),RC_SOS,"Sample floor");check(rc_set_connected(s.get(),0)==0,"disconnect full queue");
        for(int i=0;i<64;++i) act(s.get(),RC_FOLLOWUP,"Sample update");
        check(rc_set_connected(s.get(),1)==0,"partial delivery committed");
        check(contains(s.get(),"\"pendingTransfers\":2"),"two unconfirmed transfers");
        s.reset();s=open(path);check(contains(s.get(),"\"pendingTransfers\":2"),"receipt-only and original queues recover");
        check(rc_set_connected(s.get(),1)==0,"retry full store retains pending facts");
        check(contains(s.get(),"\"pendingTransfers\":2"),"no false receipt after retry");
        check(rc_reset(s.get())==0,"reset full session");s.reset();s=open(path);check(!contains(s.get(),"\"hasRequest\":true"),"full reset survives restart");
    } else check(false,"unknown scenario");
    s.reset();std::filesystem::remove_all(dir);
}
