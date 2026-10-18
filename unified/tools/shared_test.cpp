#include "../src/output/SharedOutput.hpp"
#include <sys/wait.h>
#include <cassert>
#include <thread>
#include <chrono>
#include <cstdio>
int main(){
    shuttle_sink::Mapping map;map.open(true);auto& ring=map.data();
    assert(!ring.producer.load()&&!ring.consumer.load());ring.written=0;ring.read=0;ring.mode=2;
    pid_t child=fork();assert(child>=0);
    if(!child){for(uint64_t n=0;n<80;++n){while(ring.written.load()-ring.read.load(std::memory_order_acquire)>=8)std::this_thread::yield();auto& slot=ring.slots[n%8];slot.sequence=n;slot.width=1920;slot.height=1080;memset(slot.image,int(n+1),shuttle_sink::MaxBytes);ring.written.store(n+1,std::memory_order_release);}_exit(0);}
    {shuttle_sink::Reader reader(2);unsigned count=0;std::vector<uint8_t> image;
    auto end=std::chrono::steady_clock::now()+std::chrono::seconds(10);
    while(count<80&&std::chrono::steady_clock::now()<end){reader.read(image,1920,1080);if(!reader.acknowledge){std::this_thread::yield();continue;}assert(reader.sequence==count);for(auto byte:image)assert(byte==count+1);reader.played(count,123+count);++count;}
    assert(count==80);assert(ring.ackSequence==79);}
    int status=0;assert(waitpid(child,&status,0)==child&&status==0);assert(!ring.consumer.load());
    puts("PASS: separate-process 80-frame HD ring, no overwritten/partial images, ordered playback acknowledgements and clean consumer shutdown");
}
