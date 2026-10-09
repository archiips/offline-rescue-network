#include "RescueRelay.h"
#include <sqlite3.h>
#include <algorithm>
#include <algorithm>
#include <array>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <limits>
#include <memory>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>

// Opaque custody queue. Every operation reloads and revalidates the whole bounded store inside one
// SQLite transaction, so separate handles and restarts see only committed state.
namespace {
constexpr int version=16;
constexpr sqlite3_int64 applicationId=0x52524c59; // "RRLY"
constexpr std::size_t maxItems=64,minPayload=181,maxPayload=4276,maxBytes=maxItems*maxPayload;
constexpr int maxAttempts=8,urgentBurst=3,maxHops=2;
// Numeric columns are deliberately typeless: no affinity coerces altered text, so explicit
// SQLITE_INTEGER checks see exactly what is stored.
constexpr const char* metaSchema="CREATE TABLE relay_meta (id INTEGER PRIMARY KEY CHECK(id=1), urgent_burst NOT NULL, admissions NOT NULL)";
constexpr const char* itemsSchema="CREATE TABLE relay_items (id NOT NULL PRIMARY KEY, flow NOT NULL, urgency NOT NULL, expiry NOT NULL, hops NOT NULL, attempts NOT NULL, admitted NOT NULL UNIQUE, payload NOT NULL)";

void require(bool ok,const char* reason){if(!ok)throw std::runtime_error(reason);}
void sql(sqlite3* db,const char* query){require(sqlite3_exec(db,query,nullptr,nullptr,nullptr)==SQLITE_OK,"Relay storage operation failed.");}
bool hex64(const char* p){
    if(!p)return false;
    for(int i=0;i<64;++i)if(!((p[i]>='0' && p[i]<='9') || (p[i]>='a' && p[i]<='f')))return false;
    return p[64]=='\0';
}
struct Statement {
    sqlite3_stmt* value=nullptr;
    Statement(sqlite3* db,const char* query){require(sqlite3_prepare_v2(db,query,-1,&value,nullptr)==SQLITE_OK,"Relay schema unreadable.");}
    ~Statement(){sqlite3_finalize(value);}
    Statement(const Statement&)=delete;
    Statement& operator=(const Statement&)=delete;
    void integer(int column,sqlite3_int64 v){require(sqlite3_bind_int64(value,column,v)==SQLITE_OK,"Could not bind relay number.");}
    void text(int column,const std::string& v){require(sqlite3_bind_text(value,column,v.data(),static_cast<int>(v.size()),SQLITE_TRANSIENT)==SQLITE_OK,"Could not bind relay text.");}
    void blob(int column,const std::vector<unsigned char>& v){require(sqlite3_bind_blob(value,column,v.data(),static_cast<int>(v.size()),SQLITE_TRANSIENT)==SQLITE_OK,"Could not bind relay payload.");}
    bool row(){const int r=sqlite3_step(value);require(r==SQLITE_ROW || r==SQLITE_DONE,"Could not read relay store.");return r==SQLITE_ROW;}
    void change(sqlite3* db){require(sqlite3_step(value)==SQLITE_DONE && sqlite3_changes(db)==1,"Could not write relay store.");}
    sqlite3_int64 integer(int col,sqlite3_int64 min,sqlite3_int64 max) const {
        require(sqlite3_column_type(value,col)==SQLITE_INTEGER,"Invalid stored relay number type.");
        const auto n=sqlite3_column_int64(value,col);require(n>=min && n<=max,"Stored relay number out of bounds.");return n;
    }
    std::string hexText(int col) const {
        require(sqlite3_column_type(value,col)==SQLITE_TEXT && sqlite3_column_bytes(value,col)==64,"Invalid stored relay identifier.");
        std::string s(reinterpret_cast<const char*>(sqlite3_column_text(value,col)),64);require(hex64(s.c_str()),"Invalid stored relay identifier.");return s;
    }
    std::string optionalText(int col) const {
        if(sqlite3_column_type(value,col)==SQLITE_NULL)return "<null>";
        require(sqlite3_column_type(value,col)==SQLITE_TEXT,"Invalid relay schema text.");
        return {reinterpret_cast<const char*>(sqlite3_column_text(value,col)),static_cast<std::size_t>(sqlite3_column_bytes(value,col))};
    }
};
struct Transaction {
    sqlite3* db;bool committed=false;
    Transaction(sqlite3* handle,const char* begin):db(handle){require(sqlite3_get_autocommit(db)!=0,"Relay transaction still active.");sql(db,begin);}
    ~Transaction(){if(!committed)sqlite3_exec(db,"ROLLBACK",nullptr,nullptr,nullptr);}
    Transaction(const Transaction&)=delete;
    Transaction& operator=(const Transaction&)=delete;
    void commit(){sql(db,"COMMIT");committed=true;}
};
sqlite3_int64 scalar(sqlite3* db,const char* query){
    Statement s(db,query);require(s.row(),"Missing relay metadata.");
    const auto n=s.integer(0,std::numeric_limits<sqlite3_int64>::min(),std::numeric_limits<sqlite3_int64>::max());
    require(!s.row(),"Unexpected relay metadata.");return n;
}
struct Row {
    std::string id,flow;
    int urgency=0,hops=0,attempts=0;
    sqlite3_int64 expiry=0,admitted=0;
    std::vector<unsigned char> payload;
};
struct State {
    int burst=0;
    sqlite3_int64 admissions=0;
    std::vector<Row> rows; // admission order
};
void validateSchema(sqlite3* db){
    require(scalar(db,"PRAGMA application_id")==applicationId && scalar(db,"PRAGMA user_version")==version,"Not a compatible relay store.");
    const std::array<std::array<std::string,4>,4> expected{{
        {"table","relay_items","relay_items",itemsSchema},
        {"table","relay_meta","relay_meta",metaSchema},
        {"index","sqlite_autoindex_relay_items_1","relay_items","<null>"},
        {"index","sqlite_autoindex_relay_items_2","relay_items","<null>"},
    }};
    Statement rows(db,"SELECT type,name,tbl_name,sql FROM sqlite_schema ORDER BY name");
    for(const auto& entry:expected){
        require(rows.row(),"Relay schema incomplete.");
        for(int col=0;col<4;++col)require(rows.optionalText(col)==entry[col],"Unexpected relay schema.");
    }
    require(!rows.row(),"Unexpected relay schema object.");
}
State load(sqlite3* db){
    validateSchema(db);
    State state;
    Statement meta(db,"SELECT id,urgent_burst,admissions FROM relay_meta");
    require(meta.row() && meta.integer(0,1,1)==1,"Missing relay metadata.");
    state.burst=static_cast<int>(meta.integer(1,0,urgentBurst));
    state.admissions=meta.integer(2,0,std::numeric_limits<sqlite3_int64>::max());
    require(!meta.row(),"Unexpected relay metadata.");
    Statement rows(db,"SELECT id,flow,urgency,expiry,hops,attempts,admitted,payload FROM relay_items ORDER BY admitted");
    std::size_t bytes=0;sqlite3_int64 previous=0;
    while(rows.row()){
        require(state.rows.size()<maxItems,"Relay store exceeds item bound.");
        Row row;row.id=rows.hexText(0);row.flow=rows.hexText(1);
        row.urgency=static_cast<int>(rows.integer(2,0,1));
        row.expiry=rows.integer(3,1,std::numeric_limits<sqlite3_int64>::max());
        row.hops=static_cast<int>(rows.integer(4,1,maxHops));
        row.attempts=static_cast<int>(rows.integer(5,0,maxAttempts));
        row.admitted=rows.integer(6,1,state.admissions);
        require(row.admitted>previous,"Stored relay admission order invalid.");previous=row.admitted;
        require(sqlite3_column_type(rows.value,7)==SQLITE_BLOB,"Invalid stored relay payload type.");
        const auto size=static_cast<std::size_t>(sqlite3_column_bytes(rows.value,7));
        require(size>=minPayload && size<=maxPayload,"Stored relay payload out of bounds.");
        const auto* data=static_cast<const unsigned char*>(sqlite3_column_blob(rows.value,7));
        require(data!=nullptr,"Stored relay payload unreadable.");
        row.payload.assign(data,data+size);bytes+=size;
        state.rows.push_back(std::move(row));
    }
    require(bytes<=maxBytes,"Relay store exceeds byte bound.");
    return state;
}
void prune(sqlite3* db,State& state,int64_t now){
    Statement remove(db,"DELETE FROM relay_items WHERE id=?");
    std::erase_if(state.rows,[&](const Row& row){
        if(row.expiry>now)return false;
        remove.text(1,row.id);remove.change(db);
        require(sqlite3_reset(remove.value)==SQLITE_OK,"Could not reset relay statement.");return true;
    });
}
struct ItemFree {void operator()(rc_relay_item* item) const {rc_relay_item_free(item);}};
std::unique_ptr<rc_relay_item,ItemFree> copy(const Row& row){
    std::unique_ptr<rc_relay_item,ItemFree> item(static_cast<rc_relay_item*>(std::calloc(1,sizeof(rc_relay_item))));
    if(!item)throw std::bad_alloc();
    item->payload=static_cast<unsigned char*>(std::malloc(row.payload.size()));
    if(!item->payload)throw std::bad_alloc();
    std::memcpy(item->payload,row.payload.data(),row.payload.size());item->length=row.payload.size();
    std::memcpy(item->id,row.id.c_str(),65);std::memcpy(item->flow,row.flow.c_str(),65);
    item->urgency=row.urgency;item->expiry=row.expiry;item->remaining_hops=row.hops-1;item->attempts=row.attempts;
    return item;
}
struct Database {
    sqlite3* handle=nullptr;
    Database()=default;
    Database(const Database&)=delete;
    Database& operator=(const Database&)=delete;
    ~Database(){sqlite3_close_v2(handle);}
};
}

struct rc_relay {
    // Member RAII: closes SQLite even when this constructor throws after sqlite3_open_v2.
    Database db;
    explicit rc_relay(const std::string& path){
        namespace fs=std::filesystem;
        require(fs::path(path).is_absolute(),"Relay path must be absolute.");
        const bool exists=fs::exists(path);
        if(exists)require(fs::is_regular_file(path) && fs::file_size(path)<=4*1024*1024,"Relay file outside bounds.");
        require(!fs::exists(path+"-wal") && !fs::exists(path+"-shm"),"WAL relay stores are unsupported; file preserved.");
        if(fs::exists(path+"-journal"))require(fs::is_regular_file(path+"-journal") && fs::file_size(path+"-journal")<=8*1024*1024,"Relay journal outside bounds.");
        // Gate format before SQLite can recover a foreign file's hot rollback journal.
        const bool nonempty=exists && fs::file_size(path)>0;
        if(fs::exists(path+"-journal"))require(nonempty,"Orphan relay journal; file preserved.");
        if(nonempty){
            std::ifstream file(path,std::ios::binary);std::array<unsigned char,100> header{};
            file.read(reinterpret_cast<char*>(header.data()),header.size());
            require(file.gcount()==100 && std::string(reinterpret_cast<char*>(header.data()),16)==std::string("SQLite format 3\0",16),"Invalid relay header; file preserved.");
            const auto integer=[&](std::size_t offset){return (uint32_t(header[offset])<<24) | (uint32_t(header[offset+1])<<16) | (uint32_t(header[offset+2])<<8) | uint32_t(header[offset+3]);};
            require(header[18]==1 && header[19]==1 && integer(60)==version && integer(68)==applicationId,"Unsupported relay database format; file preserved.");
        }
        const int opened=sqlite3_open_v2(path.c_str(),&db.handle,SQLITE_OPEN_READWRITE|SQLITE_OPEN_CREATE,nullptr);
        require(opened==SQLITE_OK,"Could not open relay store.");
        auto* h=db.handle;
        sqlite3_limit(h,SQLITE_LIMIT_LENGTH,8192);
        require(sqlite3_busy_timeout(h,250)==SQLITE_OK,"Could not configure relay lock timeout.");
        const bool initialize=scalar(h,"PRAGMA page_count")==0 && scalar(h,"PRAGMA user_version")==0 && scalar(h,"PRAGMA application_id")==0;
        if(!initialize)require(scalar(h,"PRAGMA application_id")==applicationId && scalar(h,"PRAGMA user_version")==version,"Not a compatible relay store; file preserved.");
        {Statement journal(h,"PRAGMA journal_mode");require(journal.row() && journal.optionalText(0)=="delete" && !journal.row(),"Unsupported relay journal mode; file preserved.");}
        sql(h,"PRAGMA synchronous=EXTRA; PRAGMA fullfsync=ON; PRAGMA trusted_schema=OFF; PRAGMA max_page_count=1024;");
        require(scalar(h,"PRAGMA synchronous")==3,"Relay durability mode unavailable.");
        if(initialize){
            Transaction t(h,"BEGIN IMMEDIATE");
            require(scalar(h,"SELECT count(*) FROM sqlite_schema")==0 && scalar(h,"PRAGMA user_version")==0 && scalar(h,"PRAGMA application_id")==0,"Relay store changed before initialization; file preserved.");
            sql(h,metaSchema);sql(h,itemsSchema);sql(h,"INSERT INTO relay_meta VALUES(1,0,0)");
            sql(h,"PRAGMA application_id=1381125209; PRAGMA user_version=16;");
            load(h);t.commit();
        }
        Transaction t(h,"BEGIN");
        {Statement integrity(h,"PRAGMA quick_check(1)");require(integrity.row() && integrity.optionalText(0)=="ok" && !integrity.row(),"Relay integrity check failed.");}
        load(h);t.commit();
    }
    // Runs one validated read-modify-write transaction; any exception rolls back and reports storage.
    template<class Body> rc_relay_result write(Body&& body){
        try{Transaction t(db.handle,"BEGIN IMMEDIATE");auto state=load(db.handle);const auto result=body(state);t.commit();return result;}
        catch(...){return RC_RELAY_STORAGE;}
    }
};

rc_relay* rc_relay_open(const char* path){
    if(!path)return nullptr;
    const std::size_t length=strnlen(path,4097);
    if(length==0 || length>4096)return nullptr;
    try{return new rc_relay(path);}catch(...){return nullptr;}
}
void rc_relay_destroy(rc_relay* relay){delete relay;}

rc_relay_result rc_relay_enqueue(rc_relay* relay,const char* id,const char* flow,int urgency,int64_t expiry,
                                 int hops,const unsigned char* payload,size_t length,int64_t now){
    if(!relay)return RC_RELAY_NULL_HANDLE;
    if(!hex64(id) || !hex64(flow) || (urgency!=0 && urgency!=1) || expiry<=0 || expiry<=now || hops<1 || hops>maxHops
       || !payload || length<minPayload || length>maxPayload)return RC_RELAY_INVALID;
    Row incoming;
    try{incoming.id=id;incoming.flow=flow;incoming.urgency=urgency;incoming.expiry=expiry;incoming.hops=hops;
        incoming.payload.assign(payload,payload+length);}catch(...){return RC_RELAY_STORAGE;}
    return relay->write([&](State& state){
        auto* db=relay->db.handle;prune(db,state,now);
        std::size_t bytes=0;
        for(const auto& row:state.rows){
            if(row.id==incoming.id){
                const bool same=row.flow==incoming.flow && row.urgency==incoming.urgency && row.expiry==incoming.expiry
                    && row.hops==incoming.hops && row.payload==incoming.payload;
                return same?RC_RELAY_DUPLICATE:RC_RELAY_CONFLICT;
            }
            bytes+=row.payload.size();
        }
        if(state.rows.size()>=maxItems || bytes+length>maxBytes || state.admissions==std::numeric_limits<sqlite3_int64>::max())return RC_RELAY_CAPACITY;
        Statement insert(db,"INSERT INTO relay_items VALUES(?,?,?,?,?,0,?,?)");
        insert.text(1,incoming.id);insert.text(2,incoming.flow);insert.integer(3,urgency);insert.integer(4,expiry);
        insert.integer(5,hops);insert.integer(6,state.admissions+1);insert.blob(7,incoming.payload);insert.change(db);
        Statement meta(db,"UPDATE relay_meta SET admissions=? WHERE id=1");meta.integer(1,state.admissions+1);meta.change(db);
        return RC_RELAY_OK;
    });
}

rc_relay_result rc_relay_select(rc_relay* relay,int64_t now,rc_relay_item** item){
    if(item)*item=nullptr;
    if(!relay)return RC_RELAY_NULL_HANDLE;
    if(!item)return RC_RELAY_INVALID;
    std::unique_ptr<rc_relay_item,ItemFree> selected;
    const auto result=relay->write([&](State& state){
        auto* db=relay->db.handle;prune(db,state,now);
        const Row* urgent=nullptr;const Row* ordinary=nullptr;std::set<std::string> flows;
        for(const auto& row:state.rows){
            if(!flows.insert(row.flow).second || row.attempts>=maxAttempts)continue; // later items wait on their flow head
            auto& oldest=row.urgency?urgent:ordinary;if(!oldest)oldest=&row;
        }
        const Row* chosen=urgent && (state.burst<urgentBurst || !ordinary)?urgent:ordinary;
        if(!chosen)return RC_RELAY_EMPTY;
        const int burst=chosen->urgency?std::min(state.burst+1,urgentBurst):0;
        Row next=*chosen;++next.attempts;
        Statement attempts(db,"UPDATE relay_items SET attempts=? WHERE id=?");attempts.integer(1,next.attempts);attempts.text(2,next.id);attempts.change(db);
        Statement meta(db,"UPDATE relay_meta SET urgent_burst=? WHERE id=1");meta.integer(1,burst);meta.change(db);
        selected=copy(next);
        return RC_RELAY_OK;
    });
    // write() commits before returning; selected bytes are published only after that commit.
    if(result==RC_RELAY_OK)*item=selected.release();
    return result;
}

rc_relay_result rc_relay_remove(rc_relay* relay,const char* id){
    if(!relay)return RC_RELAY_NULL_HANDLE;
    if(!hex64(id))return RC_RELAY_INVALID;
    return relay->write([&](State& state){
        bool present=false;for(const auto& row:state.rows)present=present || row.id==id;
        if(!present)return RC_RELAY_EMPTY;
        Statement remove(relay->db.handle,"DELETE FROM relay_items WHERE id=?");remove.text(1,id);remove.change(relay->db.handle);
        return RC_RELAY_OK;
    });
}

rc_relay_result rc_relay_count(rc_relay* relay,size_t* count){
    if(!relay)return RC_RELAY_NULL_HANDLE;
    if(!count)return RC_RELAY_INVALID;
    try{
        Transaction t(relay->db.handle,"BEGIN");const auto state=load(relay->db.handle);t.commit();
        *count=state.rows.size();return RC_RELAY_OK;
    }catch(...){return RC_RELAY_STORAGE;}
}

void rc_relay_item_free(rc_relay_item* item){if(item){std::free(item->payload);std::free(item);}}
