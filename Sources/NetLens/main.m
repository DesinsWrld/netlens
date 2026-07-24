#import <Cocoa/Cocoa.h>
#import <Network/Network.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <arpa/inet.h>
#import <mach/mach.h>

static NSString *PrimaryIPv4(void) {
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0) return @"Offline";
    NSString *result = @"Offline";
    for (struct ifaddrs *item = interfaces; item; item = item->ifa_next) {
        if (!item->ifa_addr || item->ifa_addr->sa_family != AF_INET || (item->ifa_flags & IFF_LOOPBACK) || !(item->ifa_flags & IFF_UP)) continue;
        char address[INET_ADDRSTRLEN];
        struct sockaddr_in *addr = (struct sockaddr_in *)item->ifa_addr;
        if (inet_ntop(AF_INET, &addr->sin_addr, address, sizeof(address))) {
            result = [NSString stringWithUTF8String:address];
            break;
        }
    }
    freeifaddrs(interfaces);
    return result;
}

static double MemoryUsage(void) {
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    vm_statistics64_data_t stats;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&stats, &count) != KERN_SUCCESS) return 0;
    double used = (double)(stats.active_count + stats.inactive_count + stats.wire_count + stats.compressor_page_count) * vm_kernel_page_size;
    return MIN(used / (double)[NSProcessInfo processInfo].physicalMemory, 1.0);
}

@interface DashboardView : NSView
@property NSMutableArray<NSNumber *> *history;
@property NSDictionary<NSString *, NSString *> *reading;
@property NSString *status;
@property BOOL statusGood;
@end

@implementation DashboardView
- (BOOL)isFlipped { return YES; }
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _history = [NSMutableArray array];
        for (int i = 0; i < 28; i++) [_history addObject:@0];
        _status = @"READY — SELECT A CHECK TO BEGIN";
    }
    return self;
}
- (void)label:(NSString *)value rect:(NSRect)rect size:(CGFloat)size color:(NSColor *)color weight:(NSFontWeight)weight {
    NSDictionary *attrs = @{NSFontAttributeName:[NSFont monospacedSystemFontOfSize:size weight:weight], NSForegroundColorAttributeName:color};
    [value drawInRect:rect withAttributes:attrs];
}
- (void)card:(NSRect)rect {
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:10 yRadius:10];
    [[NSColor colorWithCalibratedRed:.045 green:.09 blue:.15 alpha:1] setFill]; [path fill];
    [[NSColor colorWithCalibratedRed:.12 green:.29 blue:.43 alpha:.65] setStroke]; path.lineWidth=1; [path stroke];
}
- (void)drawRect:(NSRect)dirty {
    NSColor *bg=[NSColor colorWithCalibratedRed:.025 green:.055 blue:.10 alpha:1];
    NSColor *panel=[NSColor colorWithCalibratedRed:.025 green:.12 blue:.20 alpha:1];
    NSColor *cyan=[NSColor colorWithCalibratedRed:.20 green:.78 blue:1 alpha:1];
    NSColor *muted=[NSColor colorWithCalibratedRed:.48 green:.61 blue:.72 alpha:1];
    [bg setFill]; NSRectFill(self.bounds);
    [panel setFill]; NSRectFill(NSMakeRect(0,0,205,self.bounds.size.height));
    [self label:@"NL" rect:NSMakeRect(24,30,45,28) size:22 color:cyan weight:NSFontWeightBlack];
    [self label:@"NETLENS" rect:NSMakeRect(70,31,110,18) size:14 color:NSColor.whiteColor weight:NSFontWeightBold];
    [self label:@"LOCAL OPS CONSOLE" rect:NSMakeRect(70,51,120,14) size:8 color:muted weight:NSFontWeightRegular];
    NSArray *nav=@[@"●  OVERVIEW",@"◈  DIAGNOSTICS",@"⌁  NETWORK",@"◎  SYSTEM"];
    for(int i=0;i<nav.count;i++) [self label:nav[i] rect:NSMakeRect(25,120+i*48,160,20) size:11 color:i==0?cyan:muted weight:i==0?NSFontWeightBold:NSFontWeightRegular];
    [self label:@"●  LOCAL ONLY\nNO TELEMETRY" rect:NSMakeRect(25,self.bounds.size.height-70,150,38) size:9 color:NSColor.systemGreenColor weight:NSFontWeightBold];

    [self label:@"INTEGRATED SYSTEM MONITOR" rect:NSMakeRect(230,28,390,25) size:17 color:NSColor.whiteColor weight:NSFontWeightBold];
    [self label:@"REAL-TIME DEVICE INTELLIGENCE  /  MACOS ENDPOINT" rect:NSMakeRect(230,56,430,18) size:9 color:muted weight:NSFontWeightRegular];
    [self label:@"●  LIVE MONITORING" rect:NSMakeRect(1080,35,170,20) size:10 color:cyan weight:NSFontWeightBold];

    NSArray *titles=@[@"LOAD AVERAGE",@"MEMORY UTIL.",@"CPU CORES",@"UPTIME"];
    NSArray *keys=@[@"load",@"memory",@"cores",@"uptime"];
    for(int i=0;i<4;i++){
        NSRect rect=NSMakeRect(230+i*255,94,235,76); [self card:rect];
        [self label:titles[i] rect:NSMakeRect(rect.origin.x+15,rect.origin.y+13,180,14) size:8 color:muted weight:NSFontWeightBold];
        [self label:self.reading[keys[i]]?:@"—" rect:NSMakeRect(rect.origin.x+15,rect.origin.y+36,205,30) size:22 color:NSColor.whiteColor weight:NSFontWeightBold];
    }

    NSRect graph=NSMakeRect(230,190,680,310); [self card:graph];
    [self label:@"SYSTEM LOAD TELEMETRY" rect:NSMakeRect(250,208,300,18) size:11 color:cyan weight:NSFontWeightBold];
    [self label:@"LIVE 1-MINUTE LOAD / 3-SECOND INTERVAL" rect:NSMakeRect(250,230,320,15) size:8 color:muted weight:NSFontWeightRegular];
    NSRect plot=NSMakeRect(260,260,620,210);
    [[NSColor colorWithWhite:1 alpha:.07] setStroke];
    for(int i=0;i<5;i++){ NSBezierPath *g=[NSBezierPath bezierPath]; CGFloat y=plot.origin.y+i*plot.size.height/4; [g moveToPoint:NSMakePoint(plot.origin.x,y)]; [g lineToPoint:NSMakePoint(NSMaxX(plot),y)]; [g stroke]; }
    double max=1; for(NSNumber *n in self.history) max=MAX(max,n.doubleValue);
    NSBezierPath *line=[NSBezierPath bezierPath];
    for(int i=0;i<self.history.count;i++){ CGFloat x=plot.origin.x+i*plot.size.width/(self.history.count-1); CGFloat y=NSMaxY(plot)-self.history[i].doubleValue/max*plot.size.height*.78-plot.size.height*.08; if(i==0)[line moveToPoint:NSMakePoint(x,y)];else[line lineToPoint:NSMakePoint(x,y)]; }
    [[cyan colorWithAlphaComponent:.18] setStroke]; line.lineWidth=10; [line stroke];
    [cyan setStroke]; line.lineWidth=2; [line stroke];

    NSRect profile=NSMakeRect(930,190,310,310); [self card:profile];
    [self label:@"ENDPOINT PROFILE" rect:NSMakeRect(950,208,250,18) size:11 color:cyan weight:NSFontWeightBold];
    NSArray *rowTitles=@[@"HOST",@"PRIMARY IPV4",@"PROCESSOR",@"PLATFORM"], *rowKeys=@[@"host",@"ip",@"cpu",@"platform"];
    for(int i=0;i<4;i++){ CGFloat y=250+i*57; [self label:rowTitles[i] rect:NSMakeRect(950,y,260,14) size:8 color:muted weight:NSFontWeightBold]; [self label:self.reading[rowKeys[i]]?:@"—" rect:NSMakeRect(950,y+20,270,20) size:11 color:NSColor.whiteColor weight:NSFontWeightMedium]; }

    NSRect diag=NSMakeRect(230,520,1010,175); [self card:diag];
    [self label:@"ACTIVE DIAGNOSTICS" rect:NSMakeRect(250,538,250,18) size:11 color:cyan weight:NSFontWeightBold];
    NSColor *statusColor=self.statusGood?NSColor.systemGreenColor:(self.status.length&&![self.status hasPrefix:@"READY"]?NSColor.systemRedColor:muted);
    [self label:self.status rect:NSMakeRect(940,592,275,42) size:10 color:statusColor weight:NSFontWeightBold];
    [self label:@"Checks are initiated by you and remain on this device." rect:NSMakeRect(250,665,500,14) size:8 color:muted weight:NSFontWeightRegular];
}
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property NSWindow *window;
@property DashboardView *dashboard;
@property NSTextField *domainInput;
@property NSTextField *portInput;
@property NSTimer *timer;
@end

@implementation AppDelegate
- (NSTextField *)input:(NSString *)value frame:(NSRect)frame {
    NSTextField *field=[[NSTextField alloc] initWithFrame:frame]; field.stringValue=value;
    field.font=[NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular]; field.textColor=NSColor.whiteColor;
    field.backgroundColor=[NSColor colorWithCalibratedRed:.025 green:.06 blue:.1 alpha:1]; return field;
}
- (NSButton *)button:(NSString *)title frame:(NSRect)frame action:(SEL)action {
    NSButton *button=[NSButton buttonWithTitle:title target:self action:action]; button.frame=frame;
    button.font=[NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightBold]; button.contentTintColor=[NSColor colorWithCalibratedRed:.2 green:.78 blue:1 alpha:1]; return button;
}
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.dashboard=[[DashboardView alloc] initWithFrame:NSMakeRect(0,0,1280,760)];
    self.window=[[NSWindow alloc] initWithContentRect:self.dashboard.bounds styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title=@"NetLens — Integrated System Monitor"; self.window.contentView=self.dashboard; self.window.minSize=NSMakeSize(1100,700);
    self.domainInput=[self input:@"example.com" frame:NSMakeRect(250,580,220,30)]; [self.dashboard addSubview:self.domainInput];
    [self.dashboard addSubview:[self button:@"RUN DNS + HTTPS" frame:NSMakeRect(480,580,160,30) action:@selector(checkDomain)]];
    self.portInput=[self input:@"443" frame:NSMakeRect(670,580,110,30)]; [self.dashboard addSubview:self.portInput];
    [self.dashboard addSubview:[self button:@"CHECK LOCAL PORT" frame:NSMakeRect(790,580,145,30) action:@selector(checkPort)]];
    [self refresh]; self.timer=[NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
    [self.window center]; [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
}
- (void)refresh {
    double loads[3]={0}; getloadavg(loads,3); NSProcessInfo *p=NSProcessInfo.processInfo;
    NSInteger hours=(NSInteger)p.systemUptime/3600;
    self.dashboard.reading=@{@"load":[NSString stringWithFormat:@"%.2f",loads[0]],@"memory":[NSString stringWithFormat:@"%d%%",(int)(MemoryUsage()*100)],@"cores":[NSString stringWithFormat:@"%ld",(long)p.processorCount],@"uptime":hours>24?[NSString stringWithFormat:@"%ldD %ldH",(long)hours/24,(long)hours%24]:[NSString stringWithFormat:@"%ldH",(long)hours],@"host":p.hostName,@"ip":PrimaryIPv4(),@"cpu":@"Apple Silicon",@"platform":[NSString stringWithFormat:@"macOS %@",p.operatingSystemVersionString]};
    [self.dashboard.history addObject:@(loads[0])]; if(self.dashboard.history.count>28)[self.dashboard.history removeObjectAtIndex:0]; [self.dashboard setNeedsDisplay:YES];
}
- (void)setStatus:(NSString *)status good:(BOOL)good { dispatch_async(dispatch_get_main_queue(),^{ self.dashboard.status=status; self.dashboard.statusGood=good; [self.dashboard setNeedsDisplay:YES]; }); }
- (void)probeHost:(NSString *)host port:(NSString *)port label:(NSString *)label {
    nw_connection_t connection=nw_connection_create(nw_endpoint_create_host(host.UTF8String,port.UTF8String),nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,NW_PARAMETERS_DEFAULT_CONFIGURATION));
    NSDate *start=NSDate.date; __block BOOL finished=NO;
    nw_connection_set_state_changed_handler(connection, ^(nw_connection_state_t state, nw_error_t error) {
        if(finished)return;
        if(state==nw_connection_state_ready){finished=YES;int ms=(int)(-[start timeIntervalSinceNow]*1000);[self setStatus:[NSString stringWithFormat:@"ONLINE — %@ / %d MS",label,ms] good:YES];nw_connection_cancel(connection);}
        else if(state==nw_connection_state_failed){finished=YES;[self setStatus:[NSString stringWithFormat:@"UNREACHABLE — %@",label] good:NO];nw_connection_cancel(connection);}
    });
    nw_connection_set_queue(connection,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0)); nw_connection_start(connection);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        if(!finished){finished=YES;nw_connection_cancel(connection);[self setStatus:[NSString stringWithFormat:@"TIMEOUT — %@",label] good:NO];}
    });
}
- (void)checkDomain {
    NSString *domain=[self.domainInput.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSPredicate *valid=[NSPredicate predicateWithFormat:@"SELF MATCHES %@",@"(?i)^(?=.{1,253}$)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\\\.)+[a-z]{2,63}$"];
    if(![valid evaluateWithObject:domain]){[self setStatus:@"INVALID DOMAIN — TRY EXAMPLE.COM" good:NO];return;}
    [self setStatus:@"RUNNING DNS + HTTPS CHECK…" good:YES]; [self probeHost:domain port:@"443" label:[domain.uppercaseString stringByAppendingString:@" :443"]];
}
- (void)checkPort {
    NSInteger port=self.portInput.integerValue; if(port<1||port>65535){[self setStatus:@"INVALID PORT — USE 1–65535" good:NO];return;}
    [self setStatus:[NSString stringWithFormat:@"CHECKING 127.0.0.1:%ld…",(long)port] good:YES]; [self probeHost:@"127.0.0.1" port:[NSString stringWithFormat:@"%ld",(long)port] label:[NSString stringWithFormat:@"LOCALHOST :%ld",(long)port]];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender{return YES;}
@end

int main(int argc,const char *argv[]){
    @autoreleasepool {
        if(argc>1&&strcmp(argv[1],"--self-test")==0){NSProcessInfo *p=NSProcessInfo.processInfo;if(p.processorCount<1||p.hostName.length==0)return 1;printf("NetLens self-test passed\nHost: %s | CPU cores: %ld | IPv4: %s\n",p.hostName.UTF8String,(long)p.processorCount,PrimaryIPv4().UTF8String);return 0;}
        NSApplication *app=NSApplication.sharedApplication; AppDelegate *delegate=[AppDelegate new]; app.delegate=delegate; [app setActivationPolicy:NSApplicationActivationPolicyRegular]; [app run];
    } return 0;
}
