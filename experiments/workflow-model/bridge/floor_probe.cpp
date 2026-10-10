#include "RescueFloorProbe.h"
#include <cmath>

// Pure anchor-relative floor estimator. Every input is range-checked before arithmetic, so differences
// stay finite (|altitude| <= 10000, times finite) and the rounded floor offset fits in int (|offset| <= 10000).
namespace {
constexpr double maxAltitude=10000,anchorAge=600,sampleAge=10,minSpan=2,maxRange=0.35,tolerance=0.2;
constexpr double minHeight=2,maxHeight=8;
constexpr int minLevel=-20,maxLevel=200;
constexpr size_t minSamples=3,maxSamples=64;

bool validTime(double t) noexcept {return std::isfinite(t) && t>=0;}
bool validAltitude(double a) noexcept {return std::isfinite(a) && std::fabs(a)<=maxAltitude;}

rc_floor_reason estimate(const rc_floor_anchor* anchor,const rc_floor_sample* samples,size_t count,double now,int* level) noexcept {
    if(!validTime(now))return RC_FLOOR_INVALID_INPUT;
    if(!anchor)return RC_FLOOR_NO_ANCHOR;
    const rc_floor_anchor a=*anchor;
    if(!validTime(a.elapsed) || !validAltitude(a.altitude))return RC_FLOOR_INVALID_INPUT;
    if(!(a.floor_height>=minHeight && a.floor_height<=maxHeight))return RC_FLOOR_INVALID_HEIGHT;
    if(a.level<minLevel || a.level>maxLevel)return RC_FLOOR_INVALID_LEVEL;
    if(a.elapsed>now)return RC_FLOOR_FUTURE;
    if(now-a.elapsed>anchorAge)return RC_FLOOR_STALE_ANCHOR;
    if(count>maxSamples)return RC_FLOOR_TOO_MANY;
    if(count<minSamples)return RC_FLOOR_TOO_FEW;
    if(!samples)return RC_FLOOR_INVALID_INPUT;
    for(size_t i=0;i<count;++i)if(!validTime(samples[i].elapsed) || !validAltitude(samples[i].altitude))return RC_FLOOR_INVALID_INPUT;
    for(size_t i=0;i<count;++i)if(samples[i].elapsed>now)return RC_FLOOR_FUTURE;
    for(size_t i=0;i<count;++i)if(samples[i].elapsed<a.elapsed)return RC_FLOOR_ANCHOR_AFTER_SAMPLE;
    for(size_t i=1;i<count;++i)if(!(samples[i].elapsed>samples[i-1].elapsed))return RC_FLOOR_UNORDERED;
    // Ordered, so the first sample is the oldest.
    if(now-samples[0].elapsed>sampleAge)return RC_FLOOR_STALE_SAMPLES;
    const rc_floor_sample latest=samples[count-1];
    if(latest.elapsed-samples[0].elapsed<minSpan)return RC_FLOOR_SHORT_WINDOW;
    double low=samples[0].altitude,high=low;
    for(size_t i=1;i<count;++i){low=std::fmin(low,samples[i].altitude);high=std::fmax(high,samples[i].altitude);}
    if(high-low>maxRange)return RC_FLOOR_NOISY;
    // Height above the anchor, not above the altimeter's session baseline.
    const double height=latest.altitude-a.altitude;
    const double floors=std::round(height/a.floor_height);
    if(std::fabs(height-floors*a.floor_height)>tolerance*a.floor_height)return RC_FLOOR_TRANSITION;
    const int candidate=a.level+static_cast<int>(floors);
    if(candidate<minLevel || candidate>maxLevel)return RC_FLOOR_OUT_OF_RANGE;
    *level=candidate;
    return RC_FLOOR_CANDIDATE;
}
}

extern "C" rc_floor_reason rc_floor_relative(const rc_floor_anchor* anchor,const rc_floor_sample* samples,size_t count,
                                             double now,int* level){
    if(!level)return RC_FLOOR_NO_OUTPUT;
    *level=0;
    return estimate(anchor,samples,count,now,level);
}
