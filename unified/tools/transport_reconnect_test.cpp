#include "LoopbackTestPort.hpp"
#include "../src/output/SharedOutput.hpp"
#undef htons
#include <cassert>
#include <thread>
#include <cstdio>
int main(){ChooseLoopbackTestPort();using namespace shuttle_sink;Reader reader(2);Mapping writer;writer.open(true);auto connect=[&]{auto end=std::chrono::steady_clock::now()+std::chrono::seconds(3);while(!writer.data().consumer&&std::chrono::steady_clock::now()<end){writer.pump();reader.pump(2,1);std::this_thread::sleep_for(std::chrono::milliseconds(1));}assert(writer.data().consumer);};
    auto frame=[&](uint64_t seq){auto& ring=writer.data();auto w=ring.written.load();auto& f=ring.slots[w%Count];f.sequence=seq;f.hostNS=9000;f.width=2;f.height=1;memset(f.image,42,4);ring.written=w+1;std::vector<uint8_t> image;auto end=std::chrono::steady_clock::now()+std::chrono::seconds(3);do{writer.pump();reader.read(image,2,1);if(reader.acknowledge)break;std::this_thread::sleep_for(std::chrono::milliseconds(1));}while(std::chrono::steady_clock::now()<end);assert(reader.acknowledge&&reader.sequence==seq);};
    connect();assert(!reader.hasCurrentPicture());frame(100);assert(reader.hasCurrentPicture());uint64_t old=reader.generation;writer.reset();reader.pump(2,1);connect();assert(reader.hasPicture()&&!reader.hasCurrentPicture());frame(0);assert(reader.hasCurrentPicture());assert(reader.generation!=old);
    reader.played(100,1000,old);writer.pump();assert(writer.data().ackCount==0);
    reader.played(0,2000,reader.generation);for(unsigned n=0;n<20&&!writer.data().ackCount;++n){writer.pump();std::this_thread::sleep_for(std::chrono::milliseconds(1));}assert(writer.data().ackCount==1&&writer.data().ackSequence==0);
    Ack event;assert(writer.popCompletion(event)&&event.sequence==0&&event.hostNS==2000);assert(!writer.popCompletion(event));
    puts("PASS: output reconnection rejects stale USB completions, accepts current generation acknowledgements");}
