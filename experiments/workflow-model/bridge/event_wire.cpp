#include "event_wire.hpp"
#include <stdexcept>
namespace rescue_wire {
namespace {
void require(bool b){if(!b)throw std::runtime_error("Invalid sample event packet.");}
void number(std::vector<unsigned char>& out,std::uint64_t n,int bytes){for(int i=bytes-1;i>=0;--i)out.push_back(static_cast<unsigned char>(n>>(i*8)));}
bool utf8(const std::string& s){
 std::size_t at=0;
 while(at<s.size()){
  const auto c=static_cast<unsigned char>(s[at++]);if(c<128)continue;
  int n=0;std::uint32_t value=0,minimum=0;
  if(c>=0xc2 && c<=0xdf){n=1;value=c&31;minimum=0x80;}
  else if(c>=0xe0 && c<=0xef){n=2;value=c&15;minimum=0x800;}
  else if(c>=0xf0 && c<=0xf4){n=3;value=c&7;minimum=0x10000;}else return false;
  if(s.size()-at<static_cast<std::size_t>(n))return false;
  while(n--){const auto b=static_cast<unsigned char>(s[at++]);if((b&0xc0)!=0x80)return false;value=(value<<6)|(b&63);}
  if(value<minimum || value>0x10ffff || (value>=0xd800 && value<=0xdfff))return false;
 }
 return true;
}
struct Reader {
 std::span<const unsigned char> data;std::size_t at=0;
 std::uint64_t number(int n){require(data.size()-at>=static_cast<std::size_t>(n));std::uint64_t value=0;while(n--)value=(value<<8)|data[at++];return value;}
 std::string text(std::size_t bound){const auto n=number(2);require(n<=bound && n<=data.size()-at);std::string s(reinterpret_cast<const char*>(data.data()+at),n);at+=n;require(s.find('\0')==std::string::npos && utf8(s));return s;}
};
}
std::vector<unsigned char> encode(const rescue::Event& e){
 std::vector<unsigned char> out{'O','R','X','1'};number(out,static_cast<unsigned>(e.kind),1);
 for(auto n:{e.sequence,e.revision,e.seenPublicSequence}) {require(n<=4096);number(out,n,8);}
 for(const auto* s:{&e.id,&e.exercise,&e.request,&e.author,&e.destination,&e.reference,&e.text,&e.reportedLocation}) {
  require(s->size()<=2048 && s->find('\0')==std::string::npos);number(out,s->size(),2);out.insert(out.end(),s->begin(),s->end());
 }
 require(out.size()<=4096);return out;
}
rescue::Event decode(std::span<const unsigned char> bytes){
 require(bytes.size()>=45 && bytes.size()<=4096);Reader r{bytes};require(r.number(4)==0x4f525831);rescue::Event e;
 const auto k=r.number(1);require(k<=10);e.kind=static_cast<rescue::Kind>(k);
 e.sequence=r.number(8);e.revision=r.number(8);e.seenPublicSequence=r.number(8);require(e.sequence<=4096 && e.revision<=4096 && e.seenPublicSequence<=4096);
 e.id=r.text(64);e.exercise=r.text(64);e.request=r.text(64);e.author=r.text(64);e.destination=r.text(64);e.reference=r.text(64);e.text=r.text(2048);e.reportedLocation=r.text(2048);
 require(r.at==bytes.size() && e.text.size()+e.reportedLocation.size()<=2048 && e.exercise=="training-demo" && e.request=="request-1");
 require(e.id==(e.kind==rescue::Kind::Receipt?"receipt-"+e.reference:e.author+"-"+std::to_string(e.sequence)));
 return e;
}
}
