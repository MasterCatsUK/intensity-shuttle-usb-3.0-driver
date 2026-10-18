// GPL-2.0-or-later. Pure USB-to-host clock arithmetic; no hardware or I/O.
#include "../src/output/WireClock.hpp"
#include <cassert>
#include <cstdio>
#include <limits>
int main(){
    using namespace shuttle_output_audio;
    const unsigned lengths[]={100,200,100};uint64_t ns=7;WireClock clock;
    assert(!clock.at(0,lengths,3,0,ns)&&ns==7);
    clock.completed(256,1000000000000ULL);
    assert(clock.at(1024,lengths,3,0,ns)&&ns==1000096000000ULL);
    assert(clock.at(1024,lengths,3,200,ns)&&ns==1000096187500ULL);
    assert(clock.at(1024,lengths,3,400,ns)&&ns==1000096375000ULL);
    assert(!clock.at(1024,lengths,3,401,ns));
    // A late/out-of-order callback cannot move the anchor backwards.
    clock.completed(255,0);assert(clock.at(1024,lengths,3,0,ns)&&ns==1000096000000ULL);
    // Normal callback jitter is filtered; late callbacks do not reset phase.
    clock.completed(512,1000032800000ULL);
    assert(clock.at(512,lengths,3,0,ns)&&ns==1000032100000ULL);
    clock.completed(768,1000080000000ULL);
    assert(clock.at(768,lengths,3,0,ns)&&ns==1000064100000ULL);
    // Batched callbacks after a blocking control read must not reverse the
    // timestamps of increasing frame-start positions across transfer chunks.
    WireClock batched;batched.completed(1024,2000000000000ULL);
    batched.completed(1280,2000001000000ULL);uint64_t firstAck=0,secondAck=0;
    assert(batched.atTick(960,0,firstAck));
    batched.completed(1536,2000002000000ULL);batched.completed(1792,2000003000000ULL);
    assert(batched.atTick(1280,0,secondAck)&&secondAck>firstAck);
    WireClock lower;lower.completed(100,1);assert(!lower.at(0,lengths,3,0,ns));
    WireClock upper;upper.completed(0,std::numeric_limits<uint64_t>::max());assert(!upper.at(1,lengths,3,0,ns));
    const unsigned zeros[]={0,100,0};assert(clock.at(768,zeros,3,50,ns));
    assert(classifyPTS(1000000000100ULL,1000000000000ULL)==VideoClockDomain::Host);
    assert(classifyPTS(0,1000000000000ULL)==VideoClockDomain::Wire);
    assert(classifyPTS(std::numeric_limits<uint64_t>::max(),1)==VideoClockDomain::Wire);
    puts("PASS: USB queue deadlines, byte offsets, jitter, discontinuities, bounds and media/host PTS classification");
}
