#import <Foundation/Foundation.h>
#import <CoreMediaIO/CoreMediaIO.h>
#include <vector>
#include <cstdio>
int main() { @autoreleasepool {
 CMIOObjectPropertyAddress a{kCMIOHardwarePropertyDevices,kCMIOObjectPropertyScopeGlobal,0};UInt32 size=0;
 CMIOObjectGetPropertyDataSize(kCMIOObjectSystemObject,&a,0,nullptr,&size);std::vector<CMIOObjectID> devices(size/4);
 CMIOObjectGetPropertyData(kCMIOObjectSystemObject,&a,0,nullptr,size,&size,devices.data());
 for(auto d:devices) {
  a={kCMIODevicePropertyDeviceUID,kCMIOObjectPropertyScopeGlobal,0};CFStringRef uid=nullptr;size=sizeof(uid);
  if(CMIOObjectGetPropertyData(d,&a,0,nullptr,size,&size,&uid)) continue;
  bool match=CFEqual(uid,CFSTR("local.shuttle.camera.pal"));CFRelease(uid);if(!match) continue;
  a={kCMIODevicePropertyStreams,kCMIODevicePropertyScopeInput,0};CMIOObjectGetPropertyDataSize(d,&a,0,nullptr,&size);std::vector<CMIOObjectID> streams(size/4);
  CMIOObjectGetPropertyData(d,&a,0,nullptr,size,&size,streams.data());
  for(auto stream:streams) {
    printf("Shuttle stream=%u\n",stream);
    for(UInt32 scope:{UInt32('glob'),UInt32('inpt'),UInt32('outp')}) for(UInt32 element:{0u,48u,0x30000000u,0x30303030u,0x20202030u,0x20202020u}) {
      a={'drpt',scope,element};Boolean has=CMIOObjectHasProperty(stream,&a);if(has) printf("Drop property exists: scope=%08x element=%08x\n",scope,element);
    }
  }
 }
} }
