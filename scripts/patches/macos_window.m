#import <Cocoa/Cocoa.h>
#include "macos_window.h"

#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

static int g_video_w = 0;
static int g_video_h = 0;
static BOOL g_waiting = YES;
static BOOL g_observer_ready = NO;
static BOOL g_poll_waiting = NO;
static BOOL g_poll_fullscreen = NO;
static BOOL g_exiting = NO;
static CFAbsoluteTime g_allow_resize_until = 0;

@interface WaitingOverlayView : NSView
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *hintLabel;
@end

@implementation WaitingOverlayView
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.blackColor.CGColor;
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

        NSTextField *title = [[NSTextField alloc] initWithFrame:NSZeroRect];
        title.stringValue = @"等待投屏";
        title.bezeled = NO;
        title.editable = NO;
        title.selectable = NO;
        title.drawsBackground = NO;
        title.alignment = NSTextAlignmentCenter;
        title.font = [NSFont systemFontOfSize:28 weight:NSFontWeightSemibold];
        title.textColor = NSColor.whiteColor;
        title.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:title];
        self.titleLabel = title;

        NSTextField *hint = [[NSTextField alloc] initWithFrame:NSZeroRect];
        hint.stringValue = @"拉下控制中心，点「屏幕镜像」";
        hint.bezeled = NO;
        hint.editable = NO;
        hint.selectable = NO;
        hint.drawsBackground = NO;
        hint.alignment = NSTextAlignmentCenter;
        hint.font = [NSFont systemFontOfSize:14];
        hint.textColor = [NSColor colorWithWhite:1 alpha:0.62];
        hint.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:hint];
        self.hintLabel = hint;

        [NSLayoutConstraint activateConstraints:@[
            [title.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [title.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-12],
            [hint.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [hint.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10]
        ]];
    }
    return self;
}
@end

@interface MirrorWindowDelegate : NSObject <NSWindowDelegate>
@property (nonatomic, strong) id inner;
@end

static void macos_layout_video_views(NSWindow *window);
static void macos_apply_all(BOOL resize);
static void macos_request_clean_exit(void);
static BOOL macos_is_fullscreen(NSWindow *window);

@implementation MirrorWindowDelegate
- (BOOL)respondsToSelector:(SEL)aSelector {
    return [super respondsToSelector:aSelector] || [self.inner respondsToSelector:aSelector];
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
    if ([self.inner respondsToSelector:aSelector]) {
        return self.inner;
    }
    return [super forwardingTargetForSelector:aSelector];
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    macos_request_clean_exit();
    [sender orderOut:nil];
    return NO;
}

- (void)windowWillEnterFullScreen:(NSNotification *)notification {
    NSWindow *window = notification.object;
    [window setContentAspectRatio:NSZeroSize];
    if ([self.inner respondsToSelector:@selector(windowWillEnterFullScreen:)]) {
        [self.inner windowWillEnterFullScreen:notification];
    }
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification {
    macos_layout_video_views(notification.object);
    if ([self.inner respondsToSelector:@selector(windowDidEnterFullScreen:)]) {
        [self.inner windowDidEnterFullScreen:notification];
    }
}

- (void)windowDidExitFullScreen:(NSNotification *)notification {
    NSWindow *window = notification.object;
    if (g_video_w > 0 && g_video_h > 0) {
        [window setContentAspectRatio:NSMakeSize(g_video_w, g_video_h)];
    }
    macos_layout_video_views(window);
    if ([self.inner respondsToSelector:@selector(windowDidExitFullScreen:)]) {
        [self.inner windowDidExitFullScreen:notification];
    }
}

- (void)windowDidResize:(NSNotification *)notification {
    macos_layout_video_views(notification.object);
    if ([self.inner respondsToSelector:@selector(windowDidResize:)]) {
        [self.inner windowDidResize:notification];
    }
}
@end

static NSMutableArray<MirrorWindowDelegate *> *g_delegates = nil;
static NSHashTable<NSWindow *> *g_video_windows = nil;

static NSHashTable<NSWindow *> *macos_video_windows(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g_video_windows = [NSHashTable weakObjectsHashTable];
    });
    return g_video_windows;
}

static BOOL macos_is_fullscreen(NSWindow *window) {
    return (window.styleMask & NSWindowStyleMaskFullScreen) == NSWindowStyleMaskFullScreen;
}

static BOOL macos_looks_like_video_window(NSWindow *window) {
    if (!window || [window isKindOfClass:[NSPanel class]]) {
        return NO;
    }
    if ([macos_video_windows() containsObject:window]) {
        return YES;
    }
    NSString *title = window.title ?: @"";
    NSString *className = NSStringFromClass([window class]);
    if ([title localizedCaseInsensitiveContainsString:@"GStreamer"] ||
        [title localizedCaseInsensitiveContainsString:@"Video Output"] ||
        [title localizedCaseInsensitiveContainsString:@"OpenGL"] ||
        [title containsString:@"镜投"] ||
        [className localizedCaseInsensitiveContainsString:@"Gst"] ||
        [className localizedCaseInsensitiveContainsString:@"OSXVideo"] ||
        [className localizedCaseInsensitiveContainsString:@"GLVideo"] ||
        [className localizedCaseInsensitiveContainsString:@"GLNS"]) {
        return YES;
    }
    if ((window.styleMask & NSWindowStyleMaskTitled) == 0) {
        return NO;
    }
    NSSize size = window.contentView.bounds.size;
    return size.width >= 64 && size.height >= 64;
}

static void macos_remember_window(NSWindow *window) {
    if (window) {
        [macos_video_windows() addObject:window];
    }
}

static void macos_request_clean_exit(void) {
    if (g_exiting) {
        return;
    }
    g_exiting = YES;
    g_waiting = YES;
    printf("video window closed by user\n");
    fflush(stdout);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        exit(0);
    });
}

static void macos_install_delegate(NSWindow *window) {
    if ([window.delegate isKindOfClass:[MirrorWindowDelegate class]]) {
        return;
    }
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g_delegates = [NSMutableArray array];
    });
    MirrorWindowDelegate *delegate = [MirrorWindowDelegate new];
    delegate.inner = window.delegate;
    [g_delegates addObject:delegate];
    window.delegate = delegate;
}

static WaitingOverlayView *macos_overlay_in(NSView *content) {
    for (NSView *view in content.subviews) {
        if ([view isKindOfClass:[WaitingOverlayView class]]) {
            return (WaitingOverlayView *)view;
        }
    }
    return nil;
}

static void macos_layout_video_views(NSWindow *window) {
    NSView *content = window.contentView;
    if (!content) {
        return;
    }

    WaitingOverlayView *overlay = macos_overlay_in(content);
    NSMutableArray<NSView *> *videos = [NSMutableArray array];
    for (NSView *view in content.subviews) {
        if ([view isKindOfClass:[WaitingOverlayView class]]) {
            continue;
        }
        [videos addObject:view];
    }

    NSRect bounds = content.bounds;
    if (overlay) {
        overlay.frame = bounds;
        overlay.hidden = !g_waiting;
    }

    NSRect frame = bounds;
    BOOL letterbox = !g_waiting && macos_is_fullscreen(window) && g_video_w > 0 && g_video_h > 0;
    if (letterbox) {
        CGFloat target = (CGFloat)g_video_w / (CGFloat)g_video_h;
        CGFloat current = bounds.size.width / MAX(bounds.size.height, 1.0);
        if (current > target) {
            frame.size.width = bounds.size.height * target;
            frame.origin.x = (bounds.size.width - frame.size.width) / 2.0;
            frame.origin.y = 0;
        } else {
            frame.size.height = bounds.size.width / target;
            frame.origin.x = 0;
            frame.origin.y = (bounds.size.height - frame.size.height) / 2.0;
        }
    }

    for (NSView *view in videos) {
        if (letterbox) {
            view.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin;
        } else {
            view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        }
        view.frame = frame;
    }
}

static void macos_style_window(NSWindow *window) {
    window.backgroundColor = NSColor.blackColor;
    window.opaque = YES;
    window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    if (window.title.length == 0 ||
        [window.title localizedCaseInsensitiveContainsString:@"GStreamer"] ||
        [window.title localizedCaseInsensitiveContainsString:@"Video Output"] ||
        [window.title localizedCaseInsensitiveContainsString:@"OpenGL"]) {
        window.title = @"镜投";
    }
    macos_install_delegate(window);

    NSView *content = window.contentView;
    if (content && !macos_overlay_in(content)) {
        WaitingOverlayView *overlay = [[WaitingOverlayView alloc] initWithFrame:content.bounds];
        [content addSubview:overlay positioned:NSWindowAbove relativeTo:nil];
    }
    macos_layout_video_views(window);
}

static void macos_apply_to_window(NSWindow *window, BOOL resize) {
    if (!window) {
        return;
    }
    macos_remember_window(window);
    macos_style_window(window);

    if (macos_is_fullscreen(window)) {
        [window setContentAspectRatio:NSZeroSize];
        macos_layout_video_views(window);
        return;
    }

    if (g_waiting || g_video_w <= 0 || g_video_h <= 0) {
        return;
    }

    CGFloat ratio = (CGFloat)g_video_h / (CGFloat)g_video_w;
    [window setContentAspectRatio:NSMakeSize(g_video_w, g_video_h)];
    [window setContentMinSize:NSMakeSize(240.0, MAX(160.0, 240.0 * ratio))];

    if (!resize) {
        macos_layout_video_views(window);
        return;
    }

    NSScreen *screen = window.screen ?: [NSScreen mainScreen];
    NSRect visible = screen.visibleFrame;
    CGFloat maxW = visible.size.width * 0.72;
    CGFloat maxH = visible.size.height * 0.78;
    CGFloat scale = MIN(maxW / (CGFloat)g_video_w, maxH / (CGFloat)g_video_h);
    if (scale <= 0) {
        scale = 1;
    }
    CGFloat contentW = MAX(240.0, g_video_w * scale);
    CGFloat contentH = contentW * ratio;
    [window setContentSize:NSMakeSize(contentW, contentH)];
    [window center];
    macos_layout_video_views(window);
}

static void macos_apply_all(BOOL resize) {
    for (NSWindow *window in [NSApp windows]) {
        if (!macos_looks_like_video_window(window)) {
            continue;
        }
        macos_apply_to_window(window, resize);
        if (g_waiting || g_exiting) {
            [window orderOut:nil];
        } else {
            [window makeKeyAndOrderFront:nil];
        }
    }
}

static void macos_poll_waiting_tick(void) {
    if (!g_waiting || g_exiting) {
        g_poll_waiting = NO;
        return;
    }
    macos_apply_all(NO);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        macos_poll_waiting_tick();
    });
}

static void macos_poll_fullscreen_tick(void) {
    BOOL anyFS = NO;
    for (NSWindow *window in [NSApp windows]) {
        if (!macos_looks_like_video_window(window)) {
            continue;
        }
        if (macos_is_fullscreen(window)) {
            anyFS = YES;
            macos_layout_video_views(window);
        }
    }
    if (!anyFS || g_waiting) {
        g_poll_fullscreen = NO;
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        macos_poll_fullscreen_tick();
    });
}

static void macos_ensure_fullscreen_poll(void) {
    if (g_poll_fullscreen || g_waiting) {
        return;
    }
    g_poll_fullscreen = YES;
    macos_poll_fullscreen_tick();
}

static void macos_ensure_waiting_poll(void) {
    if (g_poll_waiting) {
        return;
    }
    g_poll_waiting = YES;
    macos_poll_waiting_tick();
}

static void macos_setup_observer(void) {
    if (g_observer_ready) {
        return;
    }
    g_observer_ready = YES;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    void (^discover)(NSNotification *) = ^(NSNotification *notification) {
        NSWindow *window = notification.object;
        if (![window isKindOfClass:[NSWindow class]] || !macos_looks_like_video_window(window)) {
            macos_apply_all(NO);
            return;
        }
        macos_remember_window(window);
        BOOL resize = !g_waiting && CFAbsoluteTimeGetCurrent() < g_allow_resize_until;
        macos_apply_to_window(window, resize);
        if (g_waiting || g_exiting) {
            [window orderOut:nil];
        }
        if (macos_is_fullscreen(window)) {
            macos_ensure_fullscreen_poll();
        }
    };
    void (^layoutOnly)(NSNotification *) = ^(NSNotification *notification) {
        NSWindow *window = notification.object;
        if ([window isKindOfClass:[NSWindow class]] && macos_looks_like_video_window(window)) {
            macos_layout_video_views(window);
            if (macos_is_fullscreen(window)) {
                macos_ensure_fullscreen_poll();
            }
        }
    };
    [center addObserverForName:NSWindowDidBecomeMainNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:discover];
    [center addObserverForName:NSWindowDidBecomeKeyNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:discover];
    [center addObserverForName:NSWindowDidExposeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:discover];
    [center addObserverForName:NSWindowDidResizeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:layoutOnly];
    [center addObserverForName:NSWindowDidEnterFullScreenNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification) {
        discover(notification);
        macos_ensure_fullscreen_poll();
    }];
    [center addObserverForName:NSWindowWillCloseNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification) {
        NSWindow *window = notification.object;
        if ([window isKindOfClass:[NSWindow class]] && macos_looks_like_video_window(window) && !g_waiting) {
            macos_request_clean_exit();
        }
    }];
}

static void macos_run_on_main(void (^block)(void)) {
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

void macos_start_watching(void) {
    g_waiting = YES;
    macos_run_on_main(^{
        macos_setup_observer();
        macos_apply_all(NO);
        macos_ensure_waiting_poll();
    });
}

void macos_lock_video_window(int width, int height) {
    if (width <= 0 || height <= 0) {
        return;
    }
    g_video_w = width;
    g_video_h = height;
    g_waiting = NO;
    macos_run_on_main(^{
        g_allow_resize_until = CFAbsoluteTimeGetCurrent() + 0.8;
        macos_setup_observer();
        macos_apply_all(YES);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            macos_apply_all(YES);
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            macos_apply_all(YES);
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.60 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            macos_apply_all(YES);
        });
    });
}

void macos_reapply_video_window(void) {
    macos_run_on_main(^{
        macos_setup_observer();
        BOOL resize = !g_waiting && CFAbsoluteTimeGetCurrent() < g_allow_resize_until;
        macos_apply_all(resize);
    });
}

void macos_set_waiting(int waiting) {
    g_waiting = waiting ? YES : NO;
    macos_run_on_main(^{
        macos_setup_observer();
        macos_apply_all(NO);
        if (g_waiting) {
            macos_ensure_waiting_poll();
        }
    });
}

enum {
    AM_MSG_SIZE = 1,
    AM_MSG_PACKET = 2,
    AM_MSG_END = 3
};

typedef struct {
    uint32_t magic;
    uint32_t type;
    uint32_t codec;
    uint32_t width;
    uint32_t height;
    uint32_t size;
    uint32_t pts_lo;
    uint32_t pts_hi;
} am_header_t;

static const uint32_t kAMMagic = 0x31564d41u;
static int g_bridge_enabled = 0;
static int g_bridge_fd = -1;
static pthread_mutex_t g_bridge_lock = PTHREAD_MUTEX_INITIALIZER;

static BOOL am_write_full(int fd, const void *buffer, size_t length) {
    const uint8_t *bytes = (const uint8_t *)buffer;
    while (length > 0) {
        ssize_t written = write(fd, bytes, length);
        if (written < 0) {
            if (errno == EINTR) {
                continue;
            }
            return NO;
        }
        if (written == 0) {
            return NO;
        }
        bytes += written;
        length -= (size_t)written;
    }
    return YES;
}

static void macos_hide_uxplay_app(void) {
    macos_run_on_main(^{
        if (NSApp) {
            [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        }
    });
}

static void macos_video_bridge_connect_locked(void) {
    if (g_bridge_fd >= 0) {
        return;
    }
    const char *path = getenv("AIRMIRROR_VIDEO_SOCK");
    if (!path || !path[0]) {
        return;
    }
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        return;
    }
    struct sockaddr_un address;
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    strncpy(address.sun_path, path, sizeof(address.sun_path) - 1);
    for (int attempt = 0; attempt < 40; attempt++) {
        if (connect(fd, (struct sockaddr *)&address, sizeof(address)) == 0) {
            g_bridge_fd = fd;
            printf("video bridge connected\n");
            fflush(stdout);
            return;
        }
        usleep(25000);
    }
    close(fd);
}

static void macos_video_bridge_send(uint32_t type, uint32_t codec, uint32_t width, uint32_t height,
                                   unsigned long long pts, const unsigned char *data, uint32_t size) {
    if (!g_bridge_enabled) {
        return;
    }
    pthread_mutex_lock(&g_bridge_lock);
    if (g_bridge_fd < 0) {
        macos_video_bridge_connect_locked();
    }
    if (g_bridge_fd < 0) {
        pthread_mutex_unlock(&g_bridge_lock);
        return;
    }
    am_header_t header;
    memset(&header, 0, sizeof(header));
    header.magic = kAMMagic;
    header.type = type;
    header.codec = codec;
    header.width = width;
    header.height = height;
    header.size = size;
    header.pts_lo = (uint32_t)(pts & 0xffffffffull);
    header.pts_hi = (uint32_t)(pts >> 32);
    BOOL ok = am_write_full(g_bridge_fd, &header, sizeof(header));
    if (ok && data && size > 0) {
        ok = am_write_full(g_bridge_fd, data, size);
    }
    if (!ok) {
        close(g_bridge_fd);
        g_bridge_fd = -1;
    }
    pthread_mutex_unlock(&g_bridge_lock);
}

int macos_video_bridge_enabled(void) {
    return g_bridge_enabled;
}

void macos_video_bridge_start(void) {
    const char *path = getenv("AIRMIRROR_VIDEO_SOCK");
    if (!path || !path[0]) {
        g_bridge_enabled = 0;
        return;
    }
    g_bridge_enabled = 1;
    macos_hide_uxplay_app();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        macos_hide_uxplay_app();
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.80 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        macos_hide_uxplay_app();
    });
    pthread_mutex_lock(&g_bridge_lock);
    macos_video_bridge_connect_locked();
    pthread_mutex_unlock(&g_bridge_lock);
}

void macos_video_bridge_send_size(int width, int height) {
    if (width <= 0 || height <= 0) {
        return;
    }
    macos_video_bridge_send(AM_MSG_SIZE, 0, (uint32_t)width, (uint32_t)height, 0, NULL, 0);
}

void macos_video_bridge_send_packet(const unsigned char *data, int length, unsigned long long pts, int codec) {
    if (!data || length <= 0) {
        return;
    }
    macos_video_bridge_send(AM_MSG_PACKET, (uint32_t)codec, 0, 0, pts, data, (uint32_t)length);
}

void macos_video_bridge_send_end(void) {
    macos_video_bridge_send(AM_MSG_END, 0, 0, 0, 0, NULL, 0);
}
