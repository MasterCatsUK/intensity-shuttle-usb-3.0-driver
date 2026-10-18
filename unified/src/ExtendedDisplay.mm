// GPL-2.0-or-later. Own the experimental display in an isolated helper process.
#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#include <unistd.h>
#include <poll.h>
#include <fcntl.h>
@interface ShuttleExtendedDisplay : NSObject
@property NSTask* process;
@property uint32_t displayID;
+ (BOOL)available;
- (BOOL)startWidth:(unsigned)width height:(unsigned)height error:(NSString**)error;
- (void)stop;
@end
@implementation ShuttleExtendedDisplay
+ (BOOL)available {return NSClassFromString(@"CGVirtualDisplay")&&NSClassFromString(@"CGVirtualDisplayDescriptor")&&NSClassFromString(@"CGVirtualDisplayMode")&&NSClassFromString(@"CGVirtualDisplaySettings");}
- (BOOL)startWidth:(unsigned)width height:(unsigned)height error:(NSString**)error {
    if(self.process){if(error)*error=@"An extended display is already active.";return NO;}
    if(!self.class.available||width<320||height<240||width>1920||height>1080){if(error)*error=@"Extended display is unavailable on this macOS version.";return NO;}
    NSString *helper=[NSBundle.mainBundle.executablePath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"ShuttleDisplay"];
    NSTask *task=[NSTask new];NSPipe *pipe=[NSPipe pipe];task.executableURL=[NSURL fileURLWithPath:helper];task.arguments=@[@(width).stringValue,@(height).stringValue,@(getpid()).stringValue];task.standardOutput=pipe;
    NSError *launchError=nil;
    if(![task launchAndReturnError:&launchError]){if(error)*error=launchError.localizedDescription?:@"Could not start the extended display.";return NO;}
    self.process=task;
    int fd=pipe.fileHandleForReading.fileDescriptor;fcntl(fd,F_SETFL,fcntl(fd,F_GETFL)|O_NONBLOCK);
    char buffer[128]={0};size_t count=0;
    for(unsigned attempt=0;attempt<100&&task.running;++attempt){
        struct pollfd ready={fd,POLLIN,0};if(poll(&ready,1,50)>0){ssize_t got=read(fd,buffer+count,sizeof(buffer)-count-1);if(got>0)count+=size_t(got);if(strchr(buffer,'\n')||count==sizeof(buffer)-1)break;}
    }
    unsigned identifier=0;if(sscanf(buffer,"DISPLAY %u",&identifier)==1&&identifier&&CGDisplayIsActive(identifier)){self.displayID=identifier;return YES;}
    [self stop];if(error)*error=@"macOS could not create the extended display. Try again or use Desktop mirror.";return NO;
}
- (void)stop {NSTask *task=self.process;self.process=nil;self.displayID=0;if(task.running)[task terminate];}
- (void)dealloc {[self stop];}
@end
