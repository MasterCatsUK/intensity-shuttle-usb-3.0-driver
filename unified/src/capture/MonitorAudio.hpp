// GPL-2.0-or-later. Bounded stereo monitor transport. Recording/input samples are read-only.
#pragma once
#include <array>
#include <atomic>
#include <cmath>
#include <algorithm>
namespace shuttle_monitor {
struct StereoRing {
 static constexpr unsigned Capacity=16384;
 std::array<std::array<float,2>,Capacity> samples{};
 std::atomic<unsigned> write{0},read{0};
 std::atomic<float> left{0},right{0},gain{0};
 std::atomic<bool> listening{false};
 void push(const float* a,const float* b,unsigned count,bool interleaved){
  float peaks[2]={0,0};unsigned w=write.load(std::memory_order_relaxed),r=read.load(std::memory_order_acquire);
  bool audible=listening.load(std::memory_order_relaxed);
  for(unsigned i=0;i<count;++i){float l=a[interleaved?i*2:i],rr=interleaved?a[i*2+1]:b[i];if(!std::isfinite(l))l=0;if(!std::isfinite(rr))rr=0;
   peaks[0]=std::max(peaks[0],std::abs(l));peaks[1]=std::max(peaks[1],std::abs(rr));
   if(audible&&w-r<Capacity){samples[w%Capacity]={{l,rr}};++w;}
  }
  write.store(w,std::memory_order_release);
  float old=left.load();while(old<peaks[0]&&!left.compare_exchange_weak(old,peaks[0])){}
  old=right.load();while(old<peaks[1]&&!right.compare_exchange_weak(old,peaks[1])){}
 }
 void render(float* out,unsigned frames){
  unsigned r=read.load(std::memory_order_relaxed),w=write.load(std::memory_order_acquire);float g=gain.load(std::memory_order_relaxed);
  // A route start/stall must not play stale queued audio. Drop only on the consumer.
  if(w-r>4800)r=w-2400;
  bool audible=listening.load(std::memory_order_relaxed);
  for(unsigned i=0;i<frames;i++){bool available=r<w;auto s=available?samples[(r++)%Capacity]:std::array<float,2>{{0,0}};out[2*i]=audible?s[0]*g:0;out[2*i+1]=audible?s[1]*g:0;}
  read.store(r,std::memory_order_release);
 }
};
inline float db(float amplitude){return amplitude>0?std::max(-60.f,20.f*std::log10(amplitude)):-60.f;}
}
