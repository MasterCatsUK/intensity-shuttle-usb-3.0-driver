// GPL-2.0-or-later. Actual movie decode and packet generation, no USB/driver I/O.
#define main UnusedPlaybackMain
#include "../unified/src/output/PlaybackTest.cpp"
#undef main
#include <cassert>
int shuttleCapturePreflight(){assert(false&&"No capture preflight/USB in this fixture");return 1;}
int main(int argc,char**argv){@autoreleasepool{
 for(unsigned n=0;n<6;++n){Playback output;output.mode=shuttle_output::Mode(n);auto profile=shuttle_output::profile(output.mode);output.startup=true;output.movie.reset(new MovieSource(argv[1],output.mode,shuttle_output::Sizing::Stretch));
  std::vector<uint8_t> picture,first,last;std::vector<int32_t> pcm;unsigned count=unsigned(std::ceil(output.movie->duration()*profile.rateNom/profile.rateDen));
  for(unsigned frame=0;frame<count+3;++frame){output.movie->read(frame,picture,pcm);if(!frame)first=picture;if(frame==count+1)last=picture;}
  assert(first!=last&&picture==last&&last.size()==size_t(profile.width)*profile.height*2);for(auto sample:pcm)assert(sample==0);
  output.movieIndex=count+3;
  shuttle_output_audio::monitorView=1;shuttle_output_audio::timecodeOverlayEnabled=true;shuttle_output_audio::titleSafeEnabled=true;shuttle_output_audio::actionSafeEnabled=true;shuttle_output_audio::audioMetersEnabled=true;
  for(unsigned repeat=0;repeat<4;++repeat){auto packet=output.nextWireFrame();std::vector<int32_t> silence(profile.audioFrames(repeat)*8);auto expected=shuttle_output::encode(output.mode,last.data(),last.size(),profile.width*2,silence.data(),silence.size(),repeat);assert(packet==expected);assert(output.startupHeld);}
 }
 puts("PASS: bundled movie decodes at all six wire formats with Stretch; playback reaches a distinct final logo, holds exact last pixels beyond EOF, emits silence afterward and ignores saved scopes/TC/meters/safe guides. No USB/audio-route writes.");
}}
