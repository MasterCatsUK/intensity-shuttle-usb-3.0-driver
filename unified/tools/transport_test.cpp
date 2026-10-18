#include "LoopbackTestPort.hpp"
#include "../src/output/SharedOutput.hpp"
#undef htons
#include <sys/wait.h>
#include <cassert>
#include <thread>
#include <cstdio>
int main(){
    ChooseLoopbackTestPort();
    pid_t child=fork();assert(child>=0);
    if(!child){shuttle_sink::Mapping map;map.open(true);auto& r=map.data();r.mode=2;unsigned count=0,scheduled=0;auto end=std::chrono::steady_clock::now()+std::chrono::seconds(15);
        while(std::chrono::steady_clock::now()<end){map.pump();shuttle_sink::Ack event;while(map.popCompletion(event)){assert(event.sequence==scheduled&&event.hostNS==123+scheduled);++scheduled;}if(count<80&&r.written.load()-r.read.load()<8){auto& f=r.slots[count%8];f.sequence=count;f.width=1920;f.height=1080;memset(f.image,count+1,shuttle_sink::MaxBytes);r.written=++count;}if(scheduled==80&&r.ackSequence==79)_exit(0);std::this_thread::sleep_for(std::chrono::milliseconds(1));}_exit(3);}
    unsigned count=0;{shuttle_sink::Reader reader(2);std::vector<uint8_t> image;auto end=std::chrono::steady_clock::now()+std::chrono::seconds(15);
    while(count<80&&std::chrono::steady_clock::now()<end){reader.read(image,1920,1080);if(reader.acknowledge){assert(reader.sequence==count);for(auto b:image)assert(b==count+1);reader.played(count,123+count,reader.generation);++count;}std::this_thread::sleep_for(std::chrono::milliseconds(1));}assert(count==80);std::this_thread::sleep_for(std::chrono::milliseconds(100));}
    int status=0;waitpid(child,&status,0);assert(status==0);puts("PASS: loopback transport, 80 complete HD frames in sequence, byte checks and playback acknowledgements");
}
