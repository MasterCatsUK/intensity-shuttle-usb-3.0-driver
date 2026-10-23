// GPL-2.0-or-later. Independent output choices in an isolated preference domain.
#include "../unified/src/output/AudioSyncPreference.hpp"
#include <cassert>
int main(){@autoreleasepool{
 auto d=CFSTR("local.shuttle.test.output49");auto set=[&](CFStringRef k,int v){auto n=CFNumberCreate(nullptr,kCFNumberIntType,&v);CFPreferencesSetAppValue(k,n,d);CFRelease(n);};
 set(CFSTR("HDMIOutputView"),0);set(CFSTR("VirtualOutputView"),1);set(CFSTR("HDMITimecodePosition"),1);set(CFSTR("VirtualTimecodePosition"),6);set(CFSTR("HDMIAudioOffsetMS"),-20);
 CFPreferencesSetAppValue(CFSTR("ShowHDMITimecode"),kCFBooleanTrue,d);CFPreferencesSetAppValue(CFSTR("ShowVirtualTimecode"),kCFBooleanFalse,d);CFPreferencesSetAppValue(CFSTR("ShowHDMITitleSafe"),kCFBooleanTrue,d);CFPreferencesSetAppValue(CFSTR("ShowVirtualTitleSafe"),kCFBooleanFalse,d);CFPreferencesAppSynchronize(d);
 using namespace shuttle_output_audio;assert(readOutputPreferences(d)==-20&&monitorView==0&&timecodeOverlayEnabled&&titleSafeEnabled&&timecodeOverlayPosition==0);
 readVirtualMonitorPreferences(d);assert(monitorView==1&&!timecodeOverlayEnabled&&!titleSafeEnabled&&timecodeOverlayPosition==5);
 assert(readOutputPreferences(d)==-20&&monitorView==0&&timecodeOverlayEnabled&&titleSafeEnabled);
 for(auto key:{CFSTR("HDMIOutputView"),CFSTR("VirtualOutputView"),CFSTR("HDMITimecodePosition"),CFSTR("VirtualTimecodePosition"),CFSTR("HDMIAudioOffsetMS"),CFSTR("ShowHDMITimecode"),CFSTR("ShowVirtualTimecode"),CFSTR("ShowHDMITitleSafe"),CFSTR("ShowVirtualTitleSafe")})CFPreferencesSetAppValue(key,nullptr,d);CFPreferencesAppSynchronize(d);
 puts("PASS: independent Video/Scopes, timecode/guides/positions, physical sync retained and no production preference changes.");
}}
