// GPL-2.0-or-later. Exercise the actual monitor transport, without Core Audio/devices.
#include "../unified/src/capture/MonitorAudio.hpp"
#include <cassert>
#include <cstdio>
#include <vector>
int main(){
 auto r=new shuttle_monitor::StereoRing;float input[]={.5f,-.25f,.25f,-.5f},original[4];std::copy(input,input+4,original);float output[4];
 r->gain=.25;r->listening=true;r->push(input,nullptr,2,true);r->render(output,2);
 assert(output[0]==.125f&&output[1]==-.0625f&&output[2]==.0625f&&output[3]==-.125f);assert(r->left.exchange(0)==.5f&&r->right.exchange(0)==.5f);assert(std::equal(input,input+4,original));
 r->gain=0;r->push(input,nullptr,2,true);r->render(output,2);for(float f:output)assert(f==0);assert(r->left.exchange(0)==.5f&&r->right.exchange(0)==.5f);
 r->listening=false;r->push(input,nullptr,2,true);assert(r->left.exchange(0)==.5f&&r->right.exchange(0)==.5f);r->render(output,2);for(float f:output)assert(f==0);
 float a[]={.125f,.25f},b[]={-.75f,-.5f};r->gain=1;r->listening=true;r->push(a,b,2,false);r->render(output,2);assert(output[0]==a[0]&&output[1]==b[0]&&output[2]==a[1]&&output[3]==b[1]);
 std::vector<float> full(40000, .125);r->push(full.data(),nullptr,20000,true);assert(r->write.load()-r->read.load()<=r->Capacity);r->render(output,2);assert(r->write.load()-r->read.load()<=2400);r->listening=false;r->render(output,2);for(float f:output)assert(f==0);
 assert(std::abs(shuttle_monitor::db(.5f)+6.0206)<.001);assert(shuttle_monitor::db(0)==-60);
 delete r;puts("PASS: independent listening gain/mute, untouched input samples, pre-fader stereo meters, planar/interleaved input, bounded overflow/latency.");
}
