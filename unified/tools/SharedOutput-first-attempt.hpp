// GPL-2.0-or-later. SPSC app-group transport from a CMIO sink to the USB sender.
#pragma once
#include <atomic>
#include <cstdint>
#include <cstring>
#include <string>
#include <stdexcept>
#include <new>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <cerrno>
#include <vector>
namespace shuttle_sink {
constexpr size_t MaxBytes=1920*1080*2,Count=8;
constexpr uint64_t Magic=0x53484f5554303031ULL;
struct Frame {uint64_t sequence,hostNS;uint32_t width,height;uint8_t image[MaxBytes];};
struct Ring {
    std::atomic<uint64_t> magic{0},written{0},read{0},ackCount{0},ackSequence{0},ackNS{0};
    std::atomic<uint32_t> producer{0},consumer{0},mode{2};
    Frame slots[Count];
};
static_assert(ATOMIC_LLONG_LOCK_FREE==2,"Shared counters must be lock free");
class Mapping {
    int fd=-1;Ring* ring=nullptr;
public:
    Mapping()=default;Mapping(const Mapping&)=delete;Mapping& operator=(const Mapping&)=delete;
    ~Mapping(){if(ring)munmap(ring,sizeof(Ring));if(fd>=0)close(fd);}
    void open(bool create) {
        if(ring)return;
        const char* name="/group.local.shuttle.camera.out";bool fresh=false;
        if(create){fd=shm_open(name,O_RDWR|O_CREAT|O_EXCL,0600);fresh=fd>=0;}
        if(fd<0)fd=shm_open(name,O_RDWR,0600);
        if(fd<0)throw std::runtime_error(std::string("Cannot open A/V output transport: ")+strerror(errno));
        if(fresh&&ftruncate(fd,sizeof(Ring)))throw std::runtime_error("Cannot size output transport");
        struct stat status{};
        size_t page=size_t(getpagesize()),rounded=(sizeof(Ring)+page-1)/page*page;
        if(fstat(fd,&status)||status.st_uid!=geteuid()||(status.st_size!=sizeof(Ring)&&size_t(status.st_size)!=rounded))throw std::runtime_error("Invalid output transport owner or size");
        void* p=mmap(nullptr,sizeof(Ring),PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);if(p==MAP_FAILED)throw std::runtime_error("Cannot map output transport");
        ring=static_cast<Ring*>(p);
        if(fresh){new(ring)Ring{};ring->magic.store(Magic,std::memory_order_release);}
        if(ring->magic.load(std::memory_order_acquire)!=Magic)throw std::runtime_error("Output transport version mismatch");
    }
    Ring& data(){if(!ring)throw std::runtime_error("Output transport is not open");return *ring;}
};
class Reader {
    Mapping map;std::vector<uint8_t> last;unsigned mode;bool started=false;
public:
    uint64_t sequence=0;bool acknowledge=false;
    Reader(unsigned selected):mode(selected){map.open(false);}
    ~Reader(){if(started)map.data().consumer.store(0,std::memory_order_release);}
    void read(std::vector<uint8_t>& image,unsigned width,unsigned height) {
        auto& ring=map.data();
        if(!started){ring.consumer=1;started=true;}
        if(ring.mode.load()!=mode)throw std::runtime_error("Final Cut format changed. Restart output with the matching format selected.");
        acknowledge=false;
        uint64_t r=ring.read.load(std::memory_order_relaxed),w=ring.written.load(std::memory_order_acquire);
        if(r<w){auto& slot=ring.slots[r%Count];
            if(slot.width!=width||slot.height!=height)throw std::runtime_error("Unexpected Final Cut video size");
            last.assign(slot.image,slot.image+size_t(width)*height*2);sequence=slot.sequence;acknowledge=true;
            ring.read.store(r+1,std::memory_order_release);
        }
        if(last.empty()){last.resize(size_t(width)*height*2);for(size_t n=0;n<last.size();n+=4){last[n]=last[n+2]=128;last[n+1]=last[n+3]=16;}}
        image=last;
    }
    void played(uint64_t seq,uint64_t ns){auto& ring=map.data();ring.ackSequence.store(seq);ring.ackNS.store(ns);ring.ackCount.fetch_add(1,std::memory_order_release);}
};
}
