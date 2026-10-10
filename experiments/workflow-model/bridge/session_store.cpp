#include "session_store.hpp"
#include <sqlite3.h>
#include <array>
#include <filesystem>
#include <fstream>
#include <limits>
#include <stdexcept>

namespace {
constexpr const char* sessionSchema="CREATE TABLE session (id INTEGER PRIMARY KEY CHECK(id=1), generation INTEGER NOT NULL, connected INTEGER NOT NULL)";
constexpr const char* endpointSchema="CREATE TABLE session (id INTEGER PRIMARY KEY CHECK(id=1), generation INTEGER NOT NULL, connected INTEGER NOT NULL, actor TEXT NOT NULL)";
constexpr const char* boundEndpointSchema="CREATE TABLE session (id INTEGER PRIMARY KEY CHECK(id=1), generation INTEGER NOT NULL, connected INTEGER NOT NULL, actor TEXT NOT NULL, binding TEXT NOT NULL)";
constexpr const char* eventsSchema="CREATE TABLE events (area INTEGER NOT NULL, position INTEGER NOT NULL, id TEXT NOT NULL, exercise TEXT NOT NULL, request_id TEXT NOT NULL,author TEXT NOT NULL, destination TEXT NOT NULL, kind INTEGER NOT NULL, seq INTEGER NOT NULL, revision INTEGER NOT NULL, seen INTEGER NOT NULL,ref TEXT NOT NULL, text TEXT NOT NULL, location TEXT NOT NULL, PRIMARY KEY(area,position))";
void require(bool ok, const char* reason) { if (!ok) throw std::runtime_error(reason); }
void sql(sqlite3* db, const char* query) {
    require(sqlite3_exec(db, query, nullptr, nullptr, nullptr)==SQLITE_OK, "Saved session database operation failed.");
}
struct Statement {
    sqlite3_stmt* value=nullptr;
    Statement(sqlite3* db, const char* query) {
        require(sqlite3_prepare_v2(db,query,-1,&value,nullptr)==SQLITE_OK, "Saved session schema is unreadable.");
    }
    ~Statement() {sqlite3_finalize(value);}
    Statement(const Statement&)=delete;
    void integer(int column, sqlite3_int64 v) {
        require(sqlite3_bind_int64(value,column,v)==SQLITE_OK,"Could not bind session number.");
    }
    void text(int column, const std::string& v) {
        require(sqlite3_bind_text(value,column,v.data(),static_cast<int>(v.size()),SQLITE_TRANSIENT)==SQLITE_OK,"Could not bind session text.");
    }
    bool row() {
        const int result=sqlite3_step(value);
        require(result==SQLITE_ROW || result==SQLITE_DONE,"Could not read saved session.");
        return result==SQLITE_ROW;
    }
    void insert() {require(sqlite3_step(value)==SQLITE_DONE,"Could not write saved session.");}
    void reset() {
        require(sqlite3_reset(value)==SQLITE_OK && sqlite3_clear_bindings(value)==SQLITE_OK,"Could not reset session statement.");
    }
};
struct Transaction {
    sqlite3* db;
    bool committed=false;
    Transaction(sqlite3* handle, const char* begin):db(handle) {
        require(sqlite3_get_autocommit(db)!=0,"Previous storage recovery failed. Reopen the saved session.");
        sql(db,begin);
    }
    ~Transaction() {if(!committed) sqlite3_exec(db,"ROLLBACK",nullptr,nullptr,nullptr);}
    void commit() {sql(db,"COMMIT");committed=true;}
};
sqlite3_int64 integer(sqlite3_stmt* row,int col,sqlite3_int64 max) {
    require(sqlite3_column_type(row,col)==SQLITE_INTEGER,"Invalid saved numeric field.");
    const auto value=sqlite3_column_int64(row,col);
    require(value>=0 && value<=max,"Saved numeric field exceeds demo limits.");
    return value;
}
std::string text(sqlite3_stmt* row,int col,int max) {
    require(sqlite3_column_type(row,col)==SQLITE_TEXT,"Invalid saved text field.");
    const int count=sqlite3_column_bytes(row,col);
    require(count<=max,"Saved text exceeds demo limits.");
    const auto* bytes=sqlite3_column_text(row,col);
    require(bytes!=nullptr,"Saved text could not be read.");
    std::string result(reinterpret_cast<const char*>(bytes),static_cast<std::size_t>(count));
    require(result.find('\0')==std::string::npos,"Saved text contains a NUL byte.");
    return result;
}
sqlite3_int64 scalar(sqlite3* db,const char* query) {
    Statement s(db,query);require(s.row(),"Missing session metadata.");
    const auto n=integer(s.value,0,std::numeric_limits<sqlite3_int64>::max());
    require(!s.row(),"Unexpected session metadata rows.");return n;
}
void validateSchema(sqlite3* db,const std::string& actor,const std::string& binding) {
    Statement rows(db,"SELECT name,type,sql FROM sqlite_schema WHERE name NOT GLOB 'sqlite_*' ORDER BY name");
    require(rows.row() && text(rows.value,0,64)=="events" && text(rows.value,1,16)=="table" && text(rows.value,2,2048)==eventsSchema,"Unexpected saved event schema.");
    require(rows.row() && text(rows.value,0,64)=="session" && text(rows.value,1,16)=="table" && text(rows.value,2,2048)==(actor.empty()?sessionSchema:(binding.empty()?endpointSchema:boundEndpointSchema)) && !rows.row(),"Unexpected saved session schema.");
}
void validateOwner(sqlite3* db,const std::string& actor,const std::string& binding) {
    if(actor.empty()) return;
    Statement meta(db,binding.empty()?"SELECT actor FROM session WHERE id=1":"SELECT actor,binding FROM session WHERE id=1");
    require(meta.row() && text(meta.value,0,64)==actor,"Saved endpoint role mismatch.");
    if(!binding.empty()) require(text(meta.value,1,256)==binding,"Saved endpoint conversation mismatch.");
    require(!meta.row(),"Unexpected endpoint metadata.");
}
rescue::Event event(sqlite3_stmt* row) {
    rescue::Event e;
    e.id=text(row,2,64);e.exercise=text(row,3,64);e.request=text(row,4,64);
    e.author=text(row,5,64);e.destination=text(row,6,64);
    e.kind=static_cast<rescue::Kind>(integer(row,7,10));
    e.sequence=integer(row,8,4096);e.revision=integer(row,9,4096);e.seenPublicSequence=integer(row,10,4096);
    e.reference=text(row,11,64);e.text=text(row,12,2048);e.reportedLocation=text(row,13,2048);
    return e;
}
void insert(Statement& s,int area,std::size_t position,const rescue::Event& e) {
    s.integer(1,area);s.integer(2,static_cast<sqlite3_int64>(position));
    s.text(3,e.id);s.text(4,e.exercise);s.text(5,e.request);s.text(6,e.author);s.text(7,e.destination);
    s.integer(8,static_cast<int>(e.kind));
    for(auto n:{e.sequence,e.revision,e.seenPublicSequence}) require(n<=4096,"Session sequence exceeds demo limit.");
    s.integer(9,static_cast<sqlite3_int64>(e.sequence));s.integer(10,static_cast<sqlite3_int64>(e.revision));
    s.integer(11,static_cast<sqlite3_int64>(e.seenPublicSequence));
    s.text(12,e.reference);s.text(13,e.text);s.text(14,e.reportedLocation);s.insert();s.reset();
}
}
struct SessionStore::Impl {
    sqlite3* db=nullptr;
    sqlite3_int64 generation=0;
    std::string actor,binding;
    ~Impl() {sqlite3_close(db);}
};
SessionStore::~SessionStore()=default;
SessionStore::SessionStore(const std::string& path,std::string actor,std::string binding):impl_(std::make_unique<Impl>()) {
    require(actor.empty() || actor=="public" || actor=="command","Invalid endpoint actor.");
    require(binding.size()<=256 && binding.find('\0')==std::string::npos && (binding.empty() || !actor.empty()),"Invalid endpoint conversation binding.");
    impl_->actor=std::move(actor);impl_->binding=std::move(binding);
    require(std::filesystem::path(path).is_absolute(),"Saved session path must be absolute.");
    const bool exists=std::filesystem::exists(path);
    if(exists && !impl_->binding.empty()) require(std::filesystem::is_regular_file(path) && std::filesystem::file_size(path)>0,"Missing bound endpoint history; file preserved.");
    if(exists) require(std::filesystem::is_regular_file(path) && std::filesystem::file_size(path)<=4*1024*1024,"Saved session file exceeds demo bounds.");
    for(const auto* suffix:{"-journal","-wal","-shm"}) {
        const auto sidecar=path+suffix;
        if(std::filesystem::exists(sidecar)) require(std::filesystem::is_regular_file(sidecar) && std::filesystem::file_size(sidecar)<=8*1024*1024,"Saved recovery file exceeds demo bounds.");
    }
    // Inspect the header before SQLite can checkpoint or otherwise touch a rejected WAL file.
    if(exists && std::filesystem::file_size(path)>0) {
        std::ifstream file(path,std::ios::binary);
        std::array<char,20> header{};
        file.read(header.data(),header.size());
        const std::string magic("SQLite format 3\0",16);
        if(file.gcount()==20 && std::string(header.data(),16)==magic) {
            require(header[18]==1 && header[19]==1,"Unsupported saved database format; file preserved.");
        }
        // An interrupted first transaction may leave a zeroed header plus a hot rollback journal.
        // Let SQLite recover it; random damaged files still fail its version/schema validation.
    }
    require(sqlite3_open_v2(path.c_str(),&impl_->db,SQLITE_OPEN_READWRITE|SQLITE_OPEN_CREATE,nullptr)==SQLITE_OK,"Could not open saved session.");
    auto* db=impl_->db;
    sqlite3_limit(db,SQLITE_LIMIT_LENGTH,8192);
    sqlite3_limit(db,SQLITE_LIMIT_SQL_LENGTH,4096);
    require(sqlite3_busy_timeout(db,250)==SQLITE_OK,"Could not configure session lock timeout.");
    const auto version=scalar(db,"PRAGMA user_version");
    const bool initialize=version==0 && scalar(db,"PRAGMA page_count")==0;
    require((initialize && (impl_->binding.empty() || !exists)) || version==(impl_->actor.empty()?1:(impl_->binding.empty()?2:3)),"Unsupported saved session version; file preserved.");
    Statement journal(db,"PRAGMA journal_mode");
    require(journal.row() && text(journal.value,0,16)=="delete" && !journal.row(),"Unsupported saved journal mode; file preserved.");
    sql(db,"PRAGMA journal_mode=DELETE; PRAGMA synchronous=EXTRA; PRAGMA fullfsync=ON; PRAGMA trusted_schema=OFF; PRAGMA max_page_count=1024;");
    require(scalar(db,"PRAGMA page_size")==4096,"Unsupported session page size.");
    require(scalar(db,"PRAGMA synchronous")==3,"Session durability mode unavailable.");
    if(initialize) {
        Transaction transaction(db,"BEGIN IMMEDIATE");
        sql(db,impl_->actor.empty()?sessionSchema:(impl_->binding.empty()?endpointSchema:boundEndpointSchema));
        if(impl_->actor.empty()) {sql(db,"INSERT INTO session VALUES(1,0,1)");sql(db,"PRAGMA user_version=1");}
        else {Statement meta(db,impl_->binding.empty()?"INSERT INTO session VALUES(1,0,1,?)":"INSERT INTO session VALUES(1,0,1,?,?)");meta.text(1,impl_->actor);if(!impl_->binding.empty())meta.text(2,impl_->binding);meta.insert();sql(db,impl_->binding.empty()?"PRAGMA user_version=2":"PRAGMA user_version=3");}
        sql(db,eventsSchema);
        transaction.commit();
    }
}
SavedSession SessionStore::load() {
    auto* db=impl_->db;Transaction transaction(db,"BEGIN");
    validateSchema(db,impl_->actor,impl_->binding);
    validateOwner(db,impl_->actor,impl_->binding);
    Statement integrity(db,"PRAGMA quick_check(1)");
    require(integrity.row() && text(integrity.value,0,256)=="ok" && !integrity.row(),"Saved session integrity check failed.");
    Statement meta(db,"SELECT id,generation,connected FROM session");
    require(meta.row() && integer(meta.value,0,1)==1,"Missing session metadata.");
    impl_->generation=integer(meta.value,1,std::numeric_limits<sqlite3_int64>::max()-1);
    SavedSession state;state.connected=integer(meta.value,2,1)!=0;
    require(!meta.row(),"Unexpected session metadata.");
    Statement rows(db,"SELECT area,position,id,exercise,request_id,author,destination,kind,seq,revision,seen,ref,text,location FROM events ORDER BY area,position");
    std::array<std::size_t,3> counts{};
    while(rows.row()) {
        const int area=static_cast<int>(integer(rows.value,0,2));const auto bound=area==2?64:128;
        require(integer(rows.value,1,bound)==static_cast<sqlite3_int64>(counts[area]) && counts[area]<static_cast<std::size_t>(bound),"Saved event order or count invalid.");
        auto e=event(rows.value);++counts[area];
        if(area==0) state.publicEvents.push_back(std::move(e));
        else if(area==1) state.responderEvents.push_back(std::move(e));
        else state.pending.push_back(std::move(e));
    }
    transaction.commit();return state;
}
void SessionStore::save(const SavedSession& state) {
    require(state.publicEvents.size()<=128 && state.responderEvents.size()<=128 && state.pending.size()<=64,"Session exceeds demo bounds.");
    require(impl_->generation<std::numeric_limits<sqlite3_int64>::max()-1,"Saved session generation limit reached.");
    auto* db=impl_->db;Transaction transaction(db,"BEGIN IMMEDIATE");
    validateSchema(db,impl_->actor,impl_->binding);
    validateOwner(db,impl_->actor,impl_->binding);
    require(scalar(db,"SELECT generation FROM session WHERE id=1")==impl_->generation,"Saved session changed in another instance. Reopen it before retrying.");
    sql(db,"DELETE FROM events");
    Statement rows(db,"INSERT INTO events VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)");
    std::size_t position=0;for(const auto& e:state.publicEvents) insert(rows,0,position++,e);
    position=0;for(const auto& e:state.responderEvents) insert(rows,1,position++,e);
    position=0;for(const auto& e:state.pending) insert(rows,2,position++,e);
    Statement meta(db,"UPDATE session SET generation=?,connected=? WHERE id=1");
    meta.integer(1,impl_->generation+1);meta.integer(2,state.connected?1:0);meta.insert();
    transaction.commit();++impl_->generation;
}
