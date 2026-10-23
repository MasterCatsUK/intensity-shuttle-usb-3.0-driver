// GPL-2.0-or-later. Actual playback frame generation, no USB initialisation or route changes.
#define main UnusedPlaybackMain
#include "../unified/src/output/PlaybackTest.cpp"
#undef main
#include <cassert>
int shuttleCapturePreflight(){assert(false&&"No live preflight in frame fixture");return 1;}
int main(){@autoreleasepool{
 CFStringRef domain=CFSTR("local.shuttle.test.idle-output46");
 shuttle_output_audio::titleSafeEnabled=false;shuttle_output_audio::actionSafeEnabled=false;shuttle_output_audio::audioMetersEnabled=false;
 for(unsigned m=0;m<6;m++)for(int choice:{0,1,2}){
  CFPreferencesSetAppValue(CFSTR("HDMIIdleScreen"),(__bridge CFNumberRef)@(choice),domain);CFPreferencesAppSynchronize(domain);
  Playback playback;playback.mode=shuttle_output::Mode(m);playback.idleOnly=true;playback.idle.reset(new shuttle_idle::Screen(playback.mode,domain));auto p=shuttle_output::profile(playback.mode);
  std::vector<uint8_t> image;if(choice==2)shuttle_idle::bars(image,p.width,p.height);else shuttle_idle::black(image,p.width,p.height);
  for(unsigned n=0;n<2;n++){auto expected=shuttle_output::encode(playback.mode,image.data(),image.size(),p.width*2,nullptr,0,n);assert(playback.nextWireFrame()==expected);assert(playback.idleScreenActive);}
 }
 CFPreferencesSetAppValue(CFSTR("HDMIIdleScreen"),nullptr,domain);CFPreferencesAppSynchronize(domain);
 puts("PASS: dedicated idle output yields exact silent wire packets at all six modes, without fallback moving bars or waiting for the editor idle delay.");
}}
