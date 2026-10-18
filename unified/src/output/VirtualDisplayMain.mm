// GPL-2.0-or-later. Original wrapper around undocumented CoreGraphics selectors.
// Interface facts: Chromium ui/display/mac/test/virtual_display_util_mac.mm.
// Runtime-probed: no private framework link, kext or firmware modification.
#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#include <algorithm>
@interface NSObject (ShuttleVirtualDisplayInterface)
- (id)initWithDescriptor:(id)descriptor;
- (BOOL)applySettings:(id)settings;
- (uint32_t)displayID;
- (id)initWithWidth:(unsigned)width height:(unsigned)height refreshRate:(double)rate;
- (void)setName:(NSString*)name;
- (void)setMaxPixelsWide:(unsigned)value;
- (void)setMaxPixelsHigh:(unsigned)value;
- (void)setVendorID:(unsigned)value;
- (void)setProductID:(unsigned)value;
- (void)setSerialNum:(unsigned)value;
- (void)setSerialNumber:(unsigned)value;
- (void)setSizeInMillimeters:(CGSize)value;
- (void)setRedPrimary:(CGPoint)value;
- (void)setGreenPrimary:(CGPoint)value;
- (void)setBluePrimary:(CGPoint)value;
- (void)setWhitePoint:(CGPoint)value;
- (void)setQueue:(id)queue;
- (void)setModes:(NSArray*)modes;
- (void)setHiDPI:(unsigned)value;
@end
@interface ShuttleVirtualDisplayDevice : NSObject
@property NSObject* display;
@property uint32_t displayID;
+ (BOOL)available;
- (BOOL)startWidth:(unsigned)width height:(unsigned)height error:(NSString**)error;
- (void)stop;
@end
@implementation ShuttleVirtualDisplayDevice
+ (BOOL)available {
    Class display=NSClassFromString(@"CGVirtualDisplay"),descriptor=NSClassFromString(@"CGVirtualDisplayDescriptor"),mode=NSClassFromString(@"CGVirtualDisplayMode"),settings=NSClassFromString(@"CGVirtualDisplaySettings");
    return display&&descriptor&&mode&&settings&&[display instancesRespondToSelector:@selector(initWithDescriptor:)]&&[display instancesRespondToSelector:@selector(applySettings:)];
}
- (BOOL)startWidth:(unsigned)width height:(unsigned)height error:(NSString**)error {
    if(self.display){if(error)*error=@"An extended display is already active.";return NO;}
    if(!self.class.available||width<320||height<240||width>1920||height>1080){if(error)*error=@"Extended display is unavailable on this macOS version.";return NO;}
    @autoreleasepool { @try{
        NSObject* description=[NSClassFromString(@"CGVirtualDisplayDescriptor") new];
        [description setName:@"Shuttle Extended Display"];[description setMaxPixelsWide:width];[description setMaxPixelsHigh:height];
        // macOS remembers modes by display identity. Keep SD and HD desktops distinct.
        unsigned serial=(width<<16)|height;
        [description setVendorID:0xf0f0];[description setProductID:0x5348];[description setSerialNum:serial];if([description respondsToSelector:@selector(setSerialNumber:)])[description setSerialNumber:serial];
        [description setSizeInMillimeters:CGSizeMake(width*25.4/110,height*25.4/110)];
        [description setRedPrimary:CGPointMake(.64,.33)];[description setGreenPrimary:CGPointMake(.30,.60)];[description setBluePrimary:CGPointMake(.15,.06)];[description setWhitePoint:CGPointMake(.3127,.3290)];
        [description setQueue:dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0)];
        NSObject* virtualMode=[[NSClassFromString(@"CGVirtualDisplayMode") alloc] initWithWidth:width height:height refreshRate:60.0];
        NSObject* settings=[NSClassFromString(@"CGVirtualDisplaySettings") new];[settings setHiDPI:0];[settings setModes:@[virtualMode]];
        self.display=[[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:description];
        if(!self.display||![self.display applySettings:settings]){[self stop];if(error)*error=@"macOS could not create the extended display.";return NO;}
        self.displayID=[self.display displayID];if(!self.displayID){[self stop];if(error)*error=@"The extended display has no usable display ID.";return NO;}
        // Arrange only the new display. Never change the main display or move existing monitors.
        CGDirectDisplayID screens[32];uint32_t count=0;CGGetActiveDisplayList(32,screens,&count);double right=0;
        for(uint32_t n=0;n<count;++n)if(screens[n]!=self.displayID)right=std::max(right,CGRectGetMaxX(CGDisplayBounds(screens[n])));
        CGDisplayConfigRef configuration=nullptr;
        if(CGBeginDisplayConfiguration(&configuration)==kCGErrorSuccess){
            CGError a=CGConfigureDisplayMirrorOfDisplay(configuration,self.displayID,kCGNullDirectDisplay);
            CGError b=CGConfigureDisplayOrigin(configuration,self.displayID,int32_t(right),int32_t(CGDisplayBounds(CGMainDisplayID()).origin.y));
            if(a==kCGErrorSuccess&&b==kCGErrorSuccess)CGCompleteDisplayConfiguration(configuration,kCGConfigureForSession);else CGCancelDisplayConfiguration(configuration);
        }
        return YES;
    }@catch(NSException *exception){[self stop];if(error)*error=@"The macOS virtual-display interface is incompatible with this build.";return NO;} }
}
- (void)stop{self.display=nil;self.displayID=0;}
@end

#include <signal.h>
#include <unistd.h>
static volatile sig_atomic_t stopping=0;
static void stopDisplay(int){stopping=1;}
int main(int argc,char**argv){@autoreleasepool{
    if(argc!=4)return 64;
    [NSApplication sharedApplication].activationPolicy=NSApplicationActivationPolicyAccessory;
    signal(SIGTERM,stopDisplay);signal(SIGINT,stopDisplay);
    pid_t parent=pid_t(strtol(argv[3],nullptr,10));
    ShuttleVirtualDisplayDevice *display=[ShuttleVirtualDisplayDevice new];NSString *error=nil;
    if(parent<=1||![display startWidth:unsigned(strtoul(argv[1],nullptr,10)) height:unsigned(strtoul(argv[2],nullptr,10)) error:&error]){fprintf(stderr,"%s\n",error.UTF8String?:"Invalid display owner");return 1;}
    printf("DISPLAY %u\n",display.displayID);fflush(stdout);
    while(!stopping&&getppid()==parent&&kill(parent,0)==0){@autoreleasepool{[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];}}
    // Close this isolated WindowServer client on every stop, including parent death.
    // Releasing CGVirtualDisplay alone does not reliably remove it on modern macOS.
    _Exit(0);
}}
