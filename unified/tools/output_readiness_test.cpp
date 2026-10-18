// Offline transport test: no CMIO activation, USB access or audio routing.
#include "LoopbackTestPort.hpp"
#include "../src/output/SharedOutput.hpp"
#undef htons
#include <cassert>
#include <thread>

int main(){
    ChooseLoopbackTestPort();
    using namespace shuttle_sink;
    for(unsigned mode=0;mode<6;++mode){
        Mapping mapping;mapping.open(true);Reader reader(mode,false);
        // A listening server is not a ready physical output. Discovery must
        // remain false even after the TCP connect can enter the listen queue.
        auto before=std::chrono::steady_clock::now()+std::chrono::milliseconds(40);
        while(std::chrono::steady_clock::now()<before){mapping.pump(true);reader.pump(2,1);assert(!mapping.data().consumer);std::this_thread::sleep_for(std::chrono::milliseconds(1));}
        reader.markOutputReady();
        auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(2);
        while(!mapping.data().consumer&&std::chrono::steady_clock::now()<deadline){reader.pump(2,1);mapping.pump(true);std::this_thread::sleep_for(std::chrono::milliseconds(1));}
        assert(mapping.data().consumer&&mapping.data().mode==mode);
        auto& ring=mapping.data();auto& f=ring.slots[0];f.sequence=7;f.hostNS=9000;f.width=2;f.height=1;memset(f.image,42,4);ring.written=1;
        std::vector<uint8_t> image;deadline=std::chrono::steady_clock::now()+std::chrono::seconds(2);
        while(!reader.acknowledge&&std::chrono::steady_clock::now()<deadline){mapping.pump();reader.read(image,2,1);std::this_thread::sleep_for(std::chrono::milliseconds(1));}
        assert(reader.acknowledge&&reader.sequence==7);reader.played(7,12345,reader.generation);
        deadline=std::chrono::steady_clock::now()+std::chrono::seconds(2);
        while(!ring.ackCount&&std::chrono::steady_clock::now()<deadline){mapping.pump();std::this_thread::sleep_for(std::chrono::milliseconds(1));}
        assert(ring.ackCount==1&&ring.ackSequence==7&&ring.ackNS==12345);
    }
    // A stream that is already configured cannot silently adopt another mode.
    {Mapping mapping;mapping.open(true);Reader reader(5);auto deadline=std::chrono::steady_clock::now()+std::chrono::milliseconds(50);while(std::chrono::steady_clock::now()<deadline){mapping.pump();reader.pump(2,1);assert(!mapping.data().consumer);std::this_thread::sleep_for(std::chrono::milliseconds(1));}}
    puts("PASS: six physical-readiness hello gates, idle mode discovery, frame acknowledgements and strict active-mode rejection");
}
