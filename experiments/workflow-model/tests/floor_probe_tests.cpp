#include "RescueFloorProbe.h"
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <string>
#include <vector>
// Synthetic deterministic fixtures only; these prove estimator logic, not physical floor accuracy.
using Samples=std::vector<rc_floor_sample>;
constexpr double notNumber=std::numeric_limits<double>::quiet_NaN(),inf=std::numeric_limits<double>::infinity();
constexpr double maxDouble=std::numeric_limits<double>::max();
void check(bool ok,const char* why){if(!ok){std::cerr<<why<<'\n';std::exit(1);}}
// Level 2 at session altitude 1 m, 3 m floors, anchored at t=100; evaluated at t=200.
rc_floor_anchor anchor(int level=2,double altitude=1,double elapsed=100,double height=3){return {level,altitude,elapsed,height};}
Samples window(std::vector<double> altitudes,double last=199,double step=2){
    Samples s;const double first=last-step*static_cast<double>(altitudes.size()-1);
    for(std::size_t i=0;i<altitudes.size();++i)s.push_back({altitudes[i],first+step*static_cast<double>(i)});
    return s;
}
int run(const rc_floor_anchor* a,const Samples& s,double now=200,int* out=nullptr){
    int level=77;const int r=rc_floor_relative(a,s.data(),s.size(),now,&level);
    if(r!=RC_FLOOR_CANDIDATE)check(level==0,"level cleared unless candidate");
    if(out)*out=level;return r;
}
void expect(const rc_floor_anchor& a,const Samples& s,int reason,const char* why,double now=200){check(run(&a,s,now)==reason,why);}
void candidate(const rc_floor_anchor& a,const Samples& s,int level,const char* why,double now=200){
    int got=0;check(run(&a,s,now,&got)==RC_FLOOR_CANDIDATE && got==level,why);
}

int main(int argc,char** argv){
    check(argc==2,"scenario required");const std::string scenario=argv[1];
    if(scenario=="candidate"){
        candidate(anchor(),window({7,7,7}),4,"two floors up");
        candidate(anchor(),window({-5,-5,-5}),0,"two floors down to ground");
        candidate(anchor(0,0),window({-3,-3,-3}),-1,"below logical ground");
        candidate(anchor(),window({1,1,1}),2,"stationary keeps anchor level");
        candidate(anchor(2,50),window({56,56,56}),4,"anchor altitude, not raw session baseline");
        candidate(anchor(),window({6.9,7.1,7}),4,"small stable noise");
        candidate(anchor(),window({7.3,7.3,7.3}),4,"latest displacement near floor centre");
        candidate(anchor(5,0,100,4),window({-8,-8,-8}),3,"other measured height");
    }else if(scenario=="boundaries"){
        candidate(anchor(2,1,100),window({7,7,7},699,2),4,"anchor age exactly 600",700);
        expect(anchor(2,1,100),window({7,7,7},699,2),RC_FLOOR_STALE_ANCHOR,"anchor age above 600",700.5);
        candidate(anchor(),window({7,7,7},194,2),4,"oldest sample age exactly 10",200);
        expect(anchor(),window({7,7,7},194.5,2.5),RC_FLOOR_STALE_SAMPLES,"oldest sample above 10 seconds",200);
        expect(anchor(),window({7,7,7},189,1),RC_FLOOR_STALE_SAMPLES,"latest sample above 10 seconds",200);
        candidate(anchor(),window({7,7,7},199,1),4,"span exactly 2");
        expect(anchor(),window({7,7,7},199,0.75),RC_FLOOR_SHORT_WINDOW,"span below 2");
        candidate(anchor(0,0,100,2.5),window({0,0.35,0}),0,"range exactly 0.35");
        expect(anchor(0,0,100,2.5),window({0,0.36,0}),RC_FLOOR_NOISY,"range above 0.35");
        candidate(anchor(0,0,100,2.5),window({3,3,3}),1,"displacement exactly 0.2 floors high");
        candidate(anchor(0,0,100,2.5),window({2,2,2}),1,"displacement exactly 0.2 floors low");
        candidate(anchor(0,0,100,2.5),window({-3,-3,-3}),-1,"downward tolerance");
        expect(anchor(0,0,100,2.5),window({3.01,3.01,3.01}),RC_FLOOR_TRANSITION,"just beyond 0.2 floors");
        expect(anchor(0,0,100,2.5),window({1.25,1.25,1.25}),RC_FLOOR_TRANSITION,"half floor");
        candidate(anchor(0,0,100,2),window({2,2,2}),1,"height exactly 2");
        candidate(anchor(0,0,100,8),window({8,8,8}),1,"height exactly 8");
        expect(anchor(0,0,100,1.999),window({2,2,2}),RC_FLOOR_INVALID_HEIGHT,"height below 2");
        expect(anchor(0,0,100,8.001),window({8,8,8}),RC_FLOOR_INVALID_HEIGHT,"height above 8");
        candidate(anchor(-20,1),window({1,1,1}),-20,"lowest anchor level");
        candidate(anchor(200,1),window({1,1,1}),200,"highest anchor level");
        expect(anchor(-21,1),window({1,1,1}),RC_FLOOR_INVALID_LEVEL,"anchor level below -20");
        expect(anchor(201,1),window({1,1,1}),RC_FLOOR_INVALID_LEVEL,"anchor level above 200");
        expect(anchor(200,1),window({4,4,4}),RC_FLOOR_OUT_OF_RANGE,"candidate above 200");
        expect(anchor(-20,1),window({-2,-2,-2}),RC_FLOOR_OUT_OF_RANGE,"candidate below -20");
        candidate(anchor(),window({7,7,7}),4,"three samples");
        expect(anchor(),window({7,7}),RC_FLOOR_TOO_FEW,"two samples");
        candidate(anchor(),window(std::vector<double>(64,7),199,0.125),4,"64 samples");
        expect(anchor(),window(std::vector<double>(65,7),199,0.125),RC_FLOOR_TOO_MANY,"65 samples");
        candidate(anchor(0,10000,100,2),window({10000,10000,10000}),0,"altitude magnitude exactly 10000");
        candidate(anchor(),window({7,7,7},200),4,"latest sample exactly now");
        candidate(anchor(2,1,195),window({7,7,7}),4,"anchor at first sample time");
        expect(anchor(2,1,200),window({7,7,7},200,0),RC_FLOOR_UNORDERED,"zero span equal times");
    }else if(scenario=="failures"){
        expect(anchor(2,1,200.5),window({7,7,7}),RC_FLOOR_FUTURE,"future anchor");
        expect(anchor(),window({7,7,7},200.5),RC_FLOOR_FUTURE,"future sample");
        expect(anchor(2,1,196),window({7,7,7}),RC_FLOOR_ANCHOR_AFTER_SAMPLE,"anchor after first sample");
        expect(anchor(),Samples{{7,195},{7,199},{7,197}},RC_FLOOR_UNORDERED,"reordered samples");
        expect(anchor(),Samples{{7,195},{7,197},{7,197}},RC_FLOOR_UNORDERED,"duplicate time");
        expect(anchor(),window({7,7.5,7}),RC_FLOOR_NOISY,"noisy window");
        expect(anchor(),window({5.5,6.2,7}),RC_FLOOR_NOISY,"moving between floors");
        expect(anchor(),window({5.5,5.5,5.5}),RC_FLOOR_TRANSITION,"stable on stairs between floors");
        expect(anchor(2,1,100,3),window({7,7,7},199,2),RC_FLOOR_STALE_ANCHOR,"stale anchor",800);
        for(double bad:{notNumber,inf,-inf,10000.5,-10001.0}){
            expect(anchor(0,bad),window({7,7,7}),RC_FLOOR_INVALID_INPUT,"bad anchor altitude");
            expect(anchor(),window({7,bad,7}),RC_FLOOR_INVALID_INPUT,"bad sample altitude");
        }
        for(double bad:{notNumber,inf,-inf,-1.0}){
            expect(anchor(2,1,bad),window({7,7,7}),RC_FLOOR_INVALID_INPUT,"bad anchor time");
            expect(anchor(),Samples{{7,195},{7,bad},{7,199}},RC_FLOOR_INVALID_INPUT,"bad sample time");
            expect(anchor(),window({7,7,7}),RC_FLOOR_INVALID_INPUT,"bad now",bad);
            expect(anchor(2,1,100,bad),window({7,7,7}),RC_FLOOR_INVALID_HEIGHT,"bad height");
        }
        expect(anchor(0,-10000,100,2),window({10000,10000,10000}),RC_FLOOR_OUT_OF_RANGE,"huge bounded displacement");
        expect(anchor(2,1,0),window({7,7,7}),RC_FLOOR_STALE_ANCHOR,"huge now without overflow",maxDouble);
        expect(anchor(2,1,maxDouble),window({7,7,7}),RC_FLOOR_FUTURE,"huge anchor time");
        candidate(anchor(2,1,1e15),Samples{{7,1e15+2},{7,1e15+4},{7,1e15+6}},4,"large finite session time",1e15+6);
    }else if(scenario=="abi"){
        const auto a=anchor();const auto s=window({7,7,7});int level=77;
        check(rc_floor_relative(&a,s.data(),s.size(),200,nullptr)==RC_FLOOR_NO_OUTPUT,"null output");
        check(rc_floor_relative(nullptr,s.data(),s.size(),200,&level)==RC_FLOOR_NO_ANCHOR && level==0,"null anchor");
        level=77;check(rc_floor_relative(nullptr,nullptr,SIZE_MAX,200,&level)==RC_FLOOR_NO_ANCHOR && level==0,"null anchor and samples");
        level=77;check(rc_floor_relative(&a,nullptr,0,200,&level)==RC_FLOOR_TOO_FEW && level==0,"null empty samples");
        level=77;check(rc_floor_relative(&a,nullptr,3,200,&level)==RC_FLOOR_INVALID_INPUT && level==0,"null samples with count");
        level=77;check(rc_floor_relative(&a,nullptr,65,200,&level)==RC_FLOOR_TOO_MANY && level==0,"too many never read");
        level=77;check(rc_floor_relative(&a,nullptr,SIZE_MAX,200,&level)==RC_FLOOR_TOO_MANY && level==0,"max count never read");
        level=77;check(rc_floor_relative(&a,s.data(),s.size(),200,&level)==RC_FLOOR_CANDIDATE && level==4,"candidate output");
    }else check(false,"unknown scenario");
    return 0;
}
