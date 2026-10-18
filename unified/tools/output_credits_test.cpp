// Offline full-transport backpressure regression; isolated ephemeral port.
#include "LoopbackTestPort.hpp"
#include "../src/output/SharedOutput.hpp"
#undef htons
#include "../src/output/OutputCredits.hpp"
#include <thread>
int main(){
    using namespace shuttle_sink;
    ChooseLoopbackTestPort();Mapping map;map.open(true);Reader reader(2);
    OutputCredits credits;std::vector<uint8_t> image;
    unsigned sent=0,received=0,completed=0,peak=0;std::deque<uint64_t> physical;
    auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(8);
    unsigned tick=0;bool stalled=false;
    while(completed<180&&std::chrono::steady_clock::now()<deadline){
        map.pump();reader.pump(32,16);
        Ack event;while(map.popCompletion(event)){
            assert(event.sequence==completed&&event.hostNS==1000+completed);
            assert(credits.completed(event.sequence));++completed;
        }
        if(map.data().consumer&&sent<180&&credits.available()){
            auto& ring=map.data();auto w=ring.written.load();
            assert(w-ring.read.load()<Count);auto& f=ring.slots[w%Count];
            f.sequence=sent;f.width=32;f.height=16;memset(f.image,int(sent),1024);
            assert(credits.consumed(sent++));ring.written=w+1;
            peak=std::max(peak,credits.count());
        }
        reader.read(image,32,16);if(reader.acknowledge){
            assert(reader.sequence==received++);for(auto b:image)assert(b==uint8_t(reader.sequence));
            physical.push_back(reader.sequence);
        }
        // Move every frame out of both software queues, but withhold physical
        // completions. Software-queue space alone must not grant any credit.
        if(tick==100){assert(sent==OutputCredits::Limit&&received==sent&&completed==0);stalled=true;}
        if(tick>100&&tick%4==0){
            // Batched completions like USB callbacks; the full event queue
            // must release exactly those credits, once and in order.
            for(unsigned n=0;n<3&&!physical.empty();++n){auto seq=physical.front();physical.pop_front();reader.played(seq,1000+seq,reader.generation);}
        }
        assert(credits.count()<=OutputCredits::Limit);
        assert(!credits.completed(UINT64_MAX));
        ++tick;std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    assert(stalled&&sent==180&&received==180&&completed==180&&credits.count()==0&&peak==OutputCredits::Limit);
    assert(credits.consumed(42));credits.clear();assert(!credits.completed(42));
    assert(credits.consumed(43));assert(!credits.completed(42));assert(credits.count()==1);assert(credits.completed(43));assert(!credits.completed(43));
    printf("PASS: 180 saturated frames; six-frame maximum across transport, reader and delayed physical completion; batched events, stalled USB, stale/duplicate acknowledgements and reset isolation\n");
}
