// Local diagnostic only; invokes the installed editor's device classifier in a separate process.
#import <Cocoa/Cocoa.h>
#import <CoreMediaIO/CoreMediaIO.h>
#import <objc/message.h>
#include <vector>
int main(){@autoreleasepool{
    [NSApplication sharedApplication];CMIOObjectPropertyAddress a{kCMIOHardwarePropertyDevices,kCMIOObjectPropertyScopeGlobal,0};UInt32 size=0;CMIOObjectGetPropertyDataSize(1,&a,0,nullptr,&size);std::vector<CMIOObjectID> ids(size/4);CMIOObjectGetPropertyData(1,&a,0,nullptr,size,&size,ids.data());CMIOObjectID device=0;
    for(auto d:ids){CFStringRef uid=nullptr;UInt32 n=sizeof(uid);a={kCMIODevicePropertyDeviceUID,kCMIOObjectPropertyScopeGlobal,0};if(!CMIOObjectGetPropertyData(d,&a,0,nullptr,n,&n,&uid)&&uid){if(CFEqual(uid,CFSTR("local.shuttle.output.cmio")))device=d;CFRelease(uid);}}
    if(!device)return 2;
    Class c=NSClassFromString(@"MIODeviceConnection");if(!c){puts("Editor device classifier not loaded");return 3;}
    id obj=((id(*)(id,SEL,UInt32))objc_msgSend)([c alloc],sel_registerName("initWithCMIOObjectID:"),device);
    if(!obj){puts("Editor classifier rejected this device");return 4;}
    ((void(*)(id,SEL))objc_msgSend)(obj,sel_registerName("connectionDidBecomeAvailable"));
    for(const char* name:{"canDoOutput","canDoInput","available"}){BOOL value=((BOOL(*)(id,SEL))objc_msgSend)(obj,sel_registerName(name));printf("%s: %d\n",name,int(value));}
    return 0;
}}
