// GPL-2.0-or-later. Bounded same-user fan-out; never blocks USB/FCP credits.
#pragma once
#include "OutputPacket.hpp"
#include "Timecode.hpp"
#include <atomic>
#include <vector>
#include <memory>
#include <stdexcept>
#include <cstring>
#include <new>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
namespace shuttle_mirror {
constexpr uint64_t Magic=0x53564d4952523031ULL;
constexpr size_t MaxBytes=1920*1080*2,MaxSamples=2048*8;
static_assert(ATOMIC_INT_LOCK_FREE==2,"Shared fan-out requires lock-free 32-bit atomics");
struct Shared {
 std::atomic<uint32_t> busy{0},ready{0},alive{1};uint32_t mode=0;
 uint64_t magic=Magic,sequence=0,hostNS=0;uint32_t bytes=0,samples=0,idle=0;
 shuttle_sink::Timecode timecode{};uint8_t image[MaxBytes];int32_t pcm[MaxSamples];
};
struct Frame {uint64_t sequence=0,hostNS=0;bool idle=false;shuttle_sink::Timecode timecode{};std::vector<uint8_t> image;std::vector<int32_t> pcm;};
class Feed {
 Shared* shared=nullptr;int fd=-1;bool owner=false;uint64_t readSequence=0;
public:
 Feed(const char* path,bool create,unsigned mode):owner(create){
  fd=open(path,O_RDWR|O_NOFOLLOW|(create?(O_CREAT|O_EXCL):0),0600);
  if(fd<0)throw std::runtime_error("Cannot open the simultaneous-output buffer");
  auto fail=[&]{close(fd);fd=-1;throw std::runtime_error("Unsafe or incompatible simultaneous-output buffer");};
  struct stat s{};if(fstat(fd,&s)||!S_ISREG(s.st_mode)||s.st_uid!=getuid()||(s.st_mode&077)||s.st_nlink!=1)fail();
  if(create){if(ftruncate(fd,sizeof(Shared)))fail();}else if(s.st_size!=sizeof(Shared))fail();
  void* address=mmap(nullptr,sizeof(Shared),PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);if(address==MAP_FAILED)fail();shared=static_cast<Shared*>(address);
  if(create){new(shared)Shared;shared->mode=mode;}
  else if(shared->magic!=Magic||shared->mode!=mode){munmap(shared,sizeof(Shared));shared=nullptr;fail();}
 }
 ~Feed(){if(shared){if(owner)shared->alive=0;munmap(shared,sizeof(Shared));}if(fd>=0)close(fd);}
 bool ready()const{return shared->ready.load(std::memory_order_acquire)!=0;}
 bool alive()const{return shared->alive.load(std::memory_order_acquire)!=0;}
 void setReady(bool value){shared->ready.store(value,std::memory_order_release);}
 bool write(const std::vector<uint8_t>& image,const std::vector<int32_t>& pcm,shuttle_sink::Timecode code,bool idle,uint64_t ns){
  auto p=shuttle_output::profile(shuttle_output::Mode(shared->mode));
  if(image.size()!=size_t(p.width)*p.height*2||pcm.size()>MaxSamples||pcm.size()%8)throw std::runtime_error("Invalid fan-out frame");
  uint32_t unlocked=0;if(!shared->busy.compare_exchange_strong(unlocked,1,std::memory_order_acquire))return false;
  memcpy(shared->image,image.data(),image.size());if(!pcm.empty())memcpy(shared->pcm,pcm.data(),pcm.size()*4);
  shared->bytes=uint32_t(image.size());shared->samples=uint32_t(pcm.size());shared->timecode=code;shared->idle=idle;shared->hostNS=ns;++shared->sequence;
  shared->busy.store(0,std::memory_order_release);return true;
 }
 bool read(Frame& frame){
  uint32_t unlocked=0;if(!shared->busy.compare_exchange_strong(unlocked,1,std::memory_order_acquire))return false;
  auto p=shuttle_output::profile(shuttle_output::Mode(shared->mode));bool fresh=shared->sequence!=readSequence;
  if(fresh&&(shared->bytes!=size_t(p.width)*p.height*2||shared->samples>MaxSamples||shared->samples%8)){shared->busy=0;throw std::runtime_error("Invalid simultaneous-output frame");}
  if(fresh){frame.sequence=readSequence=shared->sequence;frame.hostNS=shared->hostNS;frame.idle=shared->idle;frame.timecode=shared->timecode;frame.image.assign(shared->image,shared->image+shared->bytes);frame.pcm.assign(shared->pcm,shared->pcm+shared->samples);}
  shared->busy.store(0,std::memory_order_release);return fresh;
 }
};
}
