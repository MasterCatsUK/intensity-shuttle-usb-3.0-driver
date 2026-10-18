// No real waiting, devices or preferences. Deterministic monotonic clock fixtures.
#include "IdleTimer.hpp"
#include <cassert>
#include <cstdio>
int main(){using namespace shuttle_idle;auto start=Timer::Clock::time_point{};using std::chrono::seconds;Timer timer(120,start);
    assert(!timer.idle(false,start+seconds(119)));assert(timer.idle(false,start+seconds(120)));
    assert(!timer.idle(true,start+seconds(121)));assert(!timer.idle(false,start+seconds(240)));assert(timer.idle(false,start+seconds(241)));
    // A static image playing continuously is still active: every received frame resets inactivity.
    for(int s=242;s<1000;++s)assert(!timer.idle(true,start+seconds(s)));
    Timer immediate(0,start);assert(immediate.idle(false,start));assert(!immediate.idle(true,start));
    Timer never(-1,start);assert(!never.idle(false,start+seconds(86400*30)));
    Timer bad(-99,start);assert(!bad.idle(false,start+seconds(119)));assert(bad.idle(false,start+seconds(120)));
    for(int delay:{30,60,120,300,600}){Timer t(delay,start);assert(!t.idle(false,start+seconds(delay-1)));assert(t.idle(false,start+seconds(delay)));}
    puts("PASS: exact idle boundary, resume/scrub reset, continuous static video, immediate/never and delay choices");
}
