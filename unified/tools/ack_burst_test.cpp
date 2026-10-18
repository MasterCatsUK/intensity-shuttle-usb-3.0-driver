// GPL-2.0-or-later. Offline loopback completion regression; no USB or CMIO.
// TEST_LEGACY records output9's latest-only consumer to reproduce lost events.
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#include <cassert>
#include <cstdio>
#include <chrono>
#include <thread>
#include <vector>
static uint16_t testPort;
static uint16_t TestHTons(uint16_t value){return htons(value==47539?testPort:value);}
#undef htons
#define htons TestHTons
#ifdef TEST_LEGACY
#include "../backups/startup21/SharedOutput.hpp"
#else
#include "../src/output/SharedOutput.hpp"
#endif
#undef htons
static void ChoosePort(){
    int fd=socket(AF_INET,SOCK_STREAM,0);assert(fd>=0);
    sockaddr_in address{};address.sin_family=AF_INET;address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    assert(bind(fd,reinterpret_cast<sockaddr*>(&address),sizeof(address))==0);
    socklen_t bytes=sizeof(address);assert(getsockname(fd,reinterpret_cast<sockaddr*>(&address),&bytes)==0);
    testPort=ntohs(address.sin_port);close(fd);
}
int main(){
    using namespace shuttle_sink;ChoosePort();
    Reader reader(2);Mapping mapping;mapping.open(true);
    auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(2);
    while(!mapping.data().consumer&&std::chrono::steady_clock::now()<deadline){
        mapping.pump();reader.pump(2,1);std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    assert(mapping.data().consumer);
    // All three physical-completion messages reach the socket before the
    // extension pumps it again, as happens with batched USB completions.
    for(unsigned n=1;n<=3;++n)reader.played(n,100000+n,reader.generation);
    deadline=std::chrono::steady_clock::now()+std::chrono::seconds(2);
    while(mapping.data().ackCount<3&&std::chrono::steady_clock::now()<deadline){mapping.pump();std::this_thread::sleep_for(std::chrono::milliseconds(1));}
    assert(mapping.data().ackCount==3);
    std::vector<Ack> delivered;
#ifdef TEST_LEGACY
    // Output9's SinkStream.poll observes only the last sequence when its
    // completion counter changes, even when multiple events were received.
    delivered.push_back({Magic,mapping.data().ackSequence.load(),mapping.data().ackNS.load()});
#else
    Ack event;while(mapping.popCompletion(event))delivered.push_back(event);
#endif
    printf("Received %llu physical completions in one burst; delivered %zu notifications\n",(unsigned long long)mapping.data().ackCount.load(),delivered.size());
    for(auto event:delivered)printf("  sequence %llu, hostNS %llu\n",(unsigned long long)event.sequence,(unsigned long long)event.hostNS);
    if(delivered.size()!=3){puts("FAIL: completion notifications were coalesced");return 1;}
    for(unsigned n=0;n<3;++n)assert(delivered[n].sequence==n+1&&delivered[n].hostNS==100001+n);
#ifndef TEST_LEGACY
    // A reset must not deliver completions belonging to the previous client.
    reader.played(4,100004,reader.generation);
    deadline=std::chrono::steady_clock::now()+std::chrono::seconds(2);
    while(mapping.data().ackCount<4&&std::chrono::steady_clock::now()<deadline){mapping.pump();std::this_thread::sleep_for(std::chrono::milliseconds(1));}
    assert(mapping.data().ackCount==4);mapping.reset();assert(!mapping.popCompletion(event));
#endif
    puts("PASS: every completion retains its sequence and host time; reset discards stale events");
}
