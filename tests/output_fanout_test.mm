// GPL-2.0-or-later. Actual USB packet generator + pre-overlay Mac fan-out; no USB I/O.
#define main UnusedPlaybackMain
#include "../unified/src/output/PlaybackTest.cpp"
#undef main
#include <cassert>
int shuttleCapturePreflight(){assert(false);return 1;}
int main(){@autoreleasepool{
 shuttle_output_audio::timecodeOverlayEnabled=false;shuttle_output_audio::titleSafeEnabled=false;shuttle_output_audio::actionSafeEnabled=false;shuttle_output_audio::audioMetersEnabled=false;
 for(unsigned mode=0;mode<6;++mode)for(unsigned view:{0u,1u}){
  auto profile=shuttle_output::profile(shuttle_output::Mode(mode));Playback p;p.mode=shuttle_output::Mode(mode);p.sink.reset(new shuttle_sink::Reader(mode,true,uint16_t(47700+mode)));
  shuttle_sink::Mapping producer(uint16_t(47700+mode));producer.open(true);auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(3);
  while(!producer.data().consumer){producer.pump(true);p.sink->pump(profile.width,profile.height);assert(std::chrono::steady_clock::now()<deadline);usleep(100);}
  auto& ring=producer.data();auto& slot=ring.slots[0];slot.sequence=20;slot.hostNS=0;slot.width=profile.width;slot.height=profile.height;slot.timecode={1,1,2,3,4,0,25,0};
  std::vector<uint8_t> original(size_t(profile.width)*profile.height*2);for(size_t n=0;n<original.size();n+=4){original[n]=90;original[n+1]=81;original[n+2]=240;original[n+3]=81;}memcpy(slot.image,original.data(),original.size());ring.written=1;
  while(!p.sink->hasPicture()){producer.pump();std::vector<uint8_t> image;p.sink->read(image,profile.width,profile.height);assert(std::chrono::steady_clock::now()<deadline);usleep(100);}
  char folder[]="/tmp/shuttle-fanout.XXXXXX";assert(mkdtemp(folder));std::string path=std::string(folder)+"/frames";
  p.mirror.reset(new shuttle_mirror::Feed(path.c_str(),true,mode));shuttle_mirror::Feed screen(path.c_str(),false,mode);screen.setReady(true);
  shuttle_output_audio::monitorView=view;
  if(view){auto probe=original;auto warm=std::chrono::steady_clock::now()+std::chrono::seconds(3);while(!p.scopes.replace(probe,profile.width,profile.height,shuttle_scopes::View(view))){assert(std::chrono::steady_clock::now()<warm);usleep(1000);probe=original;}}
  shuttle_output_audio::timecodeOverlayEnabled=view!=0;shuttle_output_audio::titleSafeEnabled=view!=0;shuttle_output_audio::actionSafeEnabled=view!=0;shuttle_output_audio::audioMetersEnabled=view!=0;
  auto packet=p.nextWireFrame(10000000000ULL);shuttle_mirror::Frame got;assert(screen.read(got)&&got.image==original&&got.timecode.frames==4);
  auto shown=original;shuttle_scopes::Renderer renderer;renderer.replace(shown,profile.width,profile.height,shuttle_scopes::View(view));auto expected=shuttle_output::encode(p.mode,shown.data(),shown.size(),profile.width*2,nullptr,0,0);
  assert(packet==expected);assert((shown==original)==(view==0));p.mirror.reset();unlink(path.c_str());rmdir(folder);
 }
 puts("PASS: all six modes preserve exact existing Video USB packets; scopes affect only hardware presentation while Mac fan-out keeps the clean rendered video/timecode.");
}}
