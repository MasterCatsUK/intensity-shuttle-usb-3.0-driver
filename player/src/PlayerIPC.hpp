// GPL-2.0-or-later. Shuttle Player, 19 October 2026.
// Private per-launch preview file, advisory locks in both processes; no atomics/layout assumptions.
#pragma once
#include <sys/file.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <cstdint>
#include <stdexcept>
#include <cstring>
#include <cstddef>
#include "PreviewClock.hpp"
namespace player {
constexpr uint32_t Magic=0x53504c31, Width=640, Height=480;
struct Preview {
    uint32_t magic,version,width,height;
    uint64_t generation;
    double position,duration;
    uint32_t paused,ended;
    float left,right;
    uint8_t pixels[Width*Height*4]; // opaque RGBA, display aspect corrected
};
struct Channel {
    uint32_t magic,version,rateNom,rateDen;
    uint64_t published;
    Preview frames[PreviewFrames];
};
static_assert(offsetof(Channel,frames)==24,"Preview protocol layout");
class Mapping {
public:
    int fd=-1;Channel* data=nullptr;
    Mapping(const char* path,bool create){
        fd=open(path,(create?O_RDWR|O_CREAT|O_EXCL:O_RDWR)|O_NOFOLLOW|O_CLOEXEC,0600);
        if(fd<0)throw std::runtime_error("Cannot open the private preview channel");
        struct stat s{};
        if(fstat(fd,&s)||!S_ISREG(s.st_mode)||s.st_uid!=geteuid()||(s.st_mode&077)!=0 ||
           (create?ftruncate(fd,sizeof(Channel))!=0:s.st_size!=sizeof(Channel))){close(fd);fd=-1;throw std::runtime_error("Invalid preview channel");}
        data=(Channel*)mmap(nullptr,sizeof(Channel),PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
        if(data==MAP_FAILED){data=nullptr;close(fd);fd=-1;throw std::runtime_error("Cannot map the preview channel");}
        if(create){memset(data,0,sizeof(Channel));data->magic=Magic;data->version=2;}
        else if(data->magic!=Magic||data->version!=2){munmap(data,sizeof(Channel));close(fd);data=nullptr;fd=-1;throw std::runtime_error("Preview protocol mismatch");}
    }
    ~Mapping(){if(data)munmap(data,sizeof(Channel));if(fd>=0)close(fd);}
    bool lock(){return flock(fd,LOCK_EX|LOCK_NB)==0;}
    void unlock(){flock(fd,LOCK_UN);}
    Mapping(const Mapping&)=delete;Mapping& operator=(const Mapping&)=delete;
};
}
