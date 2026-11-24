//
//  SwordFSBridge.h
//  SwordFS
//
//  Objective-C bridge around the vendored DarkSword kernel exploit.
//  All kernel interaction for the app goes through this class.
//

#import <Foundation/Foundation.h>
#import <stdint.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SwordExploitState) {
    SwordExploitStateIdle = 0,
    SwordExploitStateRunning,
    SwordExploitStateReady,
    SwordExploitStateFailed,
};

typedef void (^SwordLogHandler)(NSString *line);

@interface SwordFSBridge : NSObject

@property (class, nonatomic, readonly) SwordFSBridge *shared;

@property (atomic, readonly) SwordExploitState state;
/// Set this to receive exploit log lines (called on a background thread).
@property (nonatomic, copy, nullable) SwordLogHandler logHandler;

@property (nonatomic, readonly) BOOL rootAchieved;
@property (nonatomic, readonly) BOOL sandboxEscaped;
@property (nonatomic, readonly) uint64_t kernelBase;
@property (nonatomic, readonly) uint64_t kernelSlide;

/// Runs the kernel exploit on a background queue. The completion fires on that
/// same queue. On a hard exploit failure the upstream code calls exit(), so the
/// completion is not guaranteed for failures.
- (void)runExploitWithCompletion:
    (void (^)(BOOL success, NSString *message))completion;

/// Escalates the current process to uid 0 and neuters the app sandbox.
/// Must be called after a successful exploit.
- (BOOL)applyRootAndSandbox;

/// Returns 0 when the sandbox permits both reading and writing `path`.
- (int)sandboxCheckReadWrite:(NSString *)path;

- (uint64_t)selfProc;
- (BOOL)readKernel:(uint64_t)address into:(void *)buffer length:(size_t)length;
- (BOOL)writeKernel:(uint64_t)address from:(const void *)buffer length:(size_t)length;

@end

NS_ASSUME_NONNULL_END
