// GPL-2.0-or-later. A launch-only movie; user actions wait for USB release.
#import <Cocoa/Cocoa.h>
@interface ShuttleStartupOutput:NSObject
@property NSTask* task;
@property NSMutableArray* pendingActions;
@property BOOL stopping;
@property(copy) void (^message)(NSString*);
- (void)startMovie:(NSURL*)movie helper:(NSURL*)helper mode:(NSString*)mode;
- (void)stopThen:(void (^)(void))action;
@end
@implementation ShuttleStartupOutput
- (void)startMovie:(NSURL*)movie helper:(NSURL*)helper mode:(NSString*)mode {
    if(self.task||!movie||![NSFileManager.defaultManager fileExistsAtPath:movie.path]||![NSFileManager.defaultManager isExecutableFileAtPath:helper.path])return;
    self.pendingActions=[NSMutableArray array];self.stopping=NO;
    NSTask* task=[NSTask new];self.task=task;task.executableURL=helper;task.arguments=@[@"--startup",mode,movie.path];
    NSPipe* messages=NSPipe.pipe;task.standardOutput=messages;task.standardError=messages;
    __weak ShuttleStartupOutput* owner=self;
    messages.fileHandleForReading.readabilityHandler=^(NSFileHandle* handle){NSData* data=handle.availableData;if(!data.length){handle.readabilityHandler=nil;return;}NSString* text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];if(text)dispatch_async(dispatch_get_main_queue(),^{ShuttleStartupOutput* output=owner;if(output.message)output.message(text);});};
    task.terminationHandler=^(NSTask* finished){dispatch_async(dispatch_get_main_queue(),^{ShuttleStartupOutput* output=owner;if(!output||output.task!=finished)return;output.task=nil;output.stopping=NO;NSArray* pending=[output.pendingActions copy];[output.pendingActions removeAllObjects];if(output.message)output.message(@"Startup output released.\n");for(void (^action)(void) in pending)action();});};
    NSError* error=nil;if(![task launchAndReturnError:&error]){self.task=nil;if(self.message)self.message([NSString stringWithFormat:@"Startup video skipped: %@\n",error.localizedDescription]);}
}
- (void)stopThen:(void (^)(void))action {
    if(!self.task){if(action)action();return;}
    if(action)[self.pendingActions addObject:[action copy]];
    if(!self.stopping){self.stopping=YES;if(self.task.running)[self.task terminate];}
}
@end

// Every app control/menu action first releases the launch-only USB sender.
// No blocking wait on the main thread, and the original action runs exactly once.
@interface ShuttleApplication:NSApplication
@property ShuttleStartupOutput* startupOutput;
@end
@implementation ShuttleApplication
- (BOOL)sendAction:(SEL)action to:(id)target from:(id)sender {
    if(self.startupOutput.task){__weak ShuttleApplication* app=self;[self.startupOutput stopThen:^{[app sendAction:action to:target from:sender];}];return YES;}
    return [super sendAction:action to:target from:sender];
}
@end
