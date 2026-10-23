// GPL-2.0-or-later. Actual cross-process mmap fan-out, no USB/audio/window.
#include "../unified/src/output/MirrorFrame.hpp"
#include <cassert>
#include <sys/wait.h>
#include <chrono>
#include <thread>
int main(){
 char folder[]="/tmp/shuttle-mirror-test.XXXXXX";assert(mkdtemp(folder));std::string path=std::string(folder)+"/frames";
 {
  shuttle_mirror::Feed owner(path.c_str(),true,2);assert(!owner.ready());
  pid_t child=fork();assert(child>=0);
  if(!child){shuttle_mirror::Feed reader(path.c_str(),false,2);reader.setReady(true);shuttle_mirror::Frame f;unsigned count=0;auto end=std::chrono::steady_clock::now()+std::chrono::seconds(4);
   while(std::chrono::steady_clock::now()<end){if(reader.read(f)){assert(f.image.size()==1920*1080*2&&f.pcm.size()==8);uint8_t value=f.image.front();assert(f.image.back()==value&&f.image[1000000]==value&&f.pcm[0]==value&&f.timecode.frames==value);++count;if(value==99)break;}std::this_thread::sleep_for(std::chrono::microseconds(100));}
   assert(count>3);reader.setReady(false);_Exit(0);
  }
  auto end=std::chrono::steady_clock::now()+std::chrono::seconds(2);while(!owner.ready()){assert(std::chrono::steady_clock::now()<end);std::this_thread::sleep_for(std::chrono::milliseconds(1));}
  std::vector<uint8_t> pixels(1920*1080*2);std::vector<int32_t> pcm(8);shuttle_sink::Timecode tc{};unsigned sent=0;
  for(unsigned n=0;n<100;++n){std::fill(pixels.begin(),pixels.end(),n);pcm[0]=n;tc.frames=n;if(owner.write(pixels,pcm,tc,false,n*40000000ULL))++sent;std::this_thread::sleep_for(std::chrono::milliseconds(2));}
  int result=0;waitpid(child,&result,0);assert(WIFEXITED(result)&&WEXITSTATUS(result)==0&&sent>20&&!owner.ready());
  // A busy/stalled display cannot block a physical USB submission.
  int fd=open(path.c_str(),O_RDWR);auto s=(shuttle_mirror::Shared*)mmap(nullptr,sizeof(shuttle_mirror::Shared),PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);assert(s!=MAP_FAILED);s->busy=1;auto before=std::chrono::steady_clock::now();assert(!owner.write(pixels,pcm,tc,false,0));assert(std::chrono::steady_clock::now()-before<std::chrono::milliseconds(5));s->busy=0;munmap(s,sizeof(shuttle_mirror::Shared));close(fd);
  bool refused=false;try{shuttle_mirror::Feed wrong(path.c_str(),false,1);}catch(...){refused=true;}assert(refused);
 }
 unlink(path.c_str());rmdir(folder);puts("PASS: cross-process picture/PCM/timecode consistency, ready/stop handshake, bounded latest-frame storage, nonblocking busy reader and mode guard.");
}
