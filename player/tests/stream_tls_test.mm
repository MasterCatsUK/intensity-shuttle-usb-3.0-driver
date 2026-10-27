// GPL-2.0-or-later. Reject an untrusted local HTTPS input; no USB.
#import <Foundation/Foundation.h>
#include "../src/StreamingSource.hpp"
#include <thread>
#include <chrono>
int main(int argc,char**argv){@autoreleasepool{if(argc!=3)return 64;setenv("SHUTTLE_STREAM_TEST_BIN",argv[2],1);bool rejected=false;try{StreamingSource source(argv[1],shuttle_output::Mode::PAL576i50,shuttle_output::Sizing::Stretch);std::vector<uint8_t> picture;std::vector<int32_t> audio;for(int n=0;n<1000;++n){auto state=source.read(false,0,picture,audio);if(state.advanced)return 2;std::this_thread::sleep_for(std::chrono::milliseconds(5));}}catch(const std::exception&){rejected=true;}if(!rejected)return 3;puts("PASS: production streaming decoder rejects untrusted HTTPS certificate; no video accepted, no USB.");return 0;}}
