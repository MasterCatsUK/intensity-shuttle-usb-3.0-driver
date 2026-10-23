// GPL-2.0-or-later. Actual frozen CMIO producer -> virtual receiver interoperability.
#define shuttle_sink cmio_sender
#include "../unified/src/output/SharedOutputCMIO.hpp"
#undef shuttle_sink
namespace shuttle_sink {using cmio_sender::Timecode;}
#include "../unified/src/output/SharedOutput.hpp"
#include "../unified/src/output/OutputCredits.hpp"
#include <cassert>
#include <thread>
using Clock=std::chrono::steady_clock;
template<class F> void until(F f){auto end=Clock::now()+std::chrono::seconds(4);while(!f()){assert(Clock::now()<end);std::this_thread::sleep_for(std::chrono::microseconds(200));}}
int main(){
 static_assert(sizeof(cmio_sender::Header)==sizeof(shuttle_sink::Header),"Wire format differs");
 for(unsigned mode=0;mode<6;++mode){
  // A separate fixture port must not collide with an installed output sender.
  uint16_t port=uint16_t(47600+mode);shuttle_sink::Reader reader(mode,false,port);cmio_sender::Mapping producer(port);producer.open(true);
  auto& ring=producer.data();producer.pump(true);reader.pump(720,576);producer.pump(true);assert(!ring.consumer);
  reader.markOutputReady();unsigned width=(mode==0||mode==3)?720:1920,height=mode==0?576:mode==3?486:1080;
  until([&]{producer.pump(true);reader.pump(width,height);return ring.consumer.load()!=0;});assert(ring.mode==mode);
  shuttle_sink::OutputCredits credits;
  auto send=[&](uint64_t sequence,uint8_t value){
   auto written=ring.written.load();auto& f=ring.slots[written%cmio_sender::Count];f.sequence=sequence;f.width=width;f.height=height;f.hostNS=1234000000;f.timecode.valid=1;f.timecode.frames=10;
   memset(f.image,value,size_t(width)*height*2);assert(credits.consumed(sequence));ring.written=written+1;
  };
  for(unsigned frame=0;frame<30;++frame){
   // All frames deliberately have the SAME PTS/timecode. A paused edit still
   // changes pixel bytes; receivers must never cache on timestamp equality.
   send(100+frame,uint8_t(40+frame));std::vector<uint8_t> image;
   until([&]{producer.pump();reader.read(image,width,height);return reader.acknowledge;});
   assert(reader.sequence==100+frame&&image.front()==40+frame&&image.back()==40+frame);assert(reader.hostNS==1234000000);
   auto generation=reader.generation;reader.played(reader.sequence,2000000000+frame*40000000ULL,generation);
   cmio_sender::Ack completion{};until([&]{reader.pump(width,height);producer.pump();return producer.popCompletion(completion);});assert(completion.sequence==100+frame&&credits.completed(completion.sequence));
   // Holding a paused image must not generate extra presentation callbacks.
   for(unsigned tick=0;tick<4;++tick){reader.read(image,width,height);assert(!reader.acknowledge);producer.pump();assert(!producer.popCompletion(completion));}
  }
  auto oldGeneration=reader.generation;producer.reset();reader.pump(width,height);assert(!reader.connected());reader.played(999,1,oldGeneration);
  until([&]{producer.pump(true);reader.pump(width,height);return producer.data().consumer.load()!=0;});
 }
 puts("PASS: six formats, rendered-frame pixel changes at identical paused PTS/timecode, exactly one presentation acknowledgement per frame, readiness gating and reconnect.");
}
