// GPL-2.0-or-later. Read-only installation preflight; never starts or stops capture.
// Modified 19 October 2026: Player also works when the virtual camera is absent.
#import <Foundation/Foundation.h>
#import <CoreMediaIO/CoreMediaIO.h>
#include <vector>
#include <cstdio>
int shuttleCapturePreflight() { @autoreleasepool {
    CMIOObjectPropertyAddress a{kCMIOHardwarePropertyDevices,kCMIOObjectPropertyScopeGlobal,0};UInt32 size=0;
    if(CMIOObjectGetPropertyDataSize(kCMIOObjectSystemObject,&a,0,nullptr,&size)) return 11;
    std::vector<CMIOObjectID> devices(size/sizeof(CMIOObjectID));
    if(CMIOObjectGetPropertyData(kCMIOObjectSystemObject,&a,0,nullptr,size,&size,devices.data())) return 11;
    for(auto device:devices) {
        a={kCMIODevicePropertyDeviceUID,kCMIOObjectPropertyScopeGlobal,0};CFStringRef uid=nullptr;size=sizeof(uid);
        if(CMIOObjectGetPropertyData(device,&a,0,nullptr,size,&size,&uid)) continue;
        bool matches=uid && CFEqual(uid,CFSTR("local.shuttle.camera.pal"));if(uid) CFRelease(uid);if(!matches) continue;
        a={'conf',kCMIOObjectPropertyScopeGlobal,UInt32('0')};CFStringRef value=nullptr;size=sizeof(value);
        if(!CMIOObjectGetPropertyData(device,&a,0,nullptr,size,&size,&value) && value) {
            NSString *json=CFBridgingRelease(value);
            if([json isKindOfClass:NSString.class]) {
                id state=[NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
                if([state isKindOfClass:NSDictionary.class] && [state[@"capturing"] isKindOfClass:NSNumber.class]) {
                    bool active=[state[@"capturing"] boolValue];puts(active?"Shuttle capture is active":"Shuttle camera is idle");return active?10:0;
                }
            }
        }
        a={kCMIODevicePropertyDeviceIsRunningSomewhere,kCMIOObjectPropertyScopeGlobal,0};UInt32 running=0;size=sizeof(running);
        if(CMIOObjectGetPropertyData(device,&a,0,nullptr,size,&size,&running)) { fputs("Cannot determine Shuttle capture state\n",stderr);return 11; }
        puts(running?"Shuttle capture is active":"Shuttle camera is idle");return running?10:0;
    }
    puts("No Shuttle virtual camera is registered; USB must be exclusively available");return 0;
} }
