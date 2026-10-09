// Cranny media helper.
//
// macOS only hands "Now Playing" information to Apple-signed processes, so this
// library is loaded into /usr/bin/perl (see media-helper.pl). It streams the
// current playback state to stdout as one JSON object per line and reads simple
// text commands ("toggle", "next", "seek 42.5", ...) from stdin.

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <unistd.h>

typedef void (*MRGetInfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*MRGetIsPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*MRGetClientFn)(dispatch_queue_t, void (^)(id));
typedef void (*MRGetPIDFn)(dispatch_queue_t, void (^)(int));
typedef void (*MRRegisterFn)(dispatch_queue_t);
typedef Boolean (*MRSendCommandFn)(int, NSDictionary *);
typedef void (*MRSetElapsedFn)(double);
typedef NSString *(*MRClientStringFn)(id);

static MRGetInfoFn MRGetInfo;
static MRGetIsPlayingFn MRGetIsPlaying;
static MRGetClientFn MRGetClient;
static MRGetPIDFn MRGetPID;
static MRRegisterFn MRRegister;
static MRSendCommandFn MRSendCommand;
static MRSetElapsedFn MRSetElapsed;
static MRClientStringFn MRClientBundleID;
static MRClientStringFn MRClientParentBundleID;

static NSDictionary *lastPayload;
static NSUInteger lastArtworkHash;
static BOOL refreshScheduled;
static BOOL refreshInFlight;
static CFAbsoluteTime refreshStarted;

static void emit(NSDictionary *payload) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!data) return;
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static double finiteDouble(id value) {
    if (![value isKindOfClass:[NSNumber class]]) return 0;
    double d = [value doubleValue];
    return isfinite(d) ? d : 0;
}

static NSString *string(id value) {
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

static void publish(NSDictionary *info, BOOL playing, NSString *bundleID, NSString *parentID, int pid) {
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    BOOL empty = info.count == 0;
    p[@"empty"] = @(empty);
    p[@"playing"] = @(playing && !empty);
    if (!empty) {
        p[@"title"] = string(info[@"kMRMediaRemoteNowPlayingInfoTitle"]);
        p[@"artist"] = string(info[@"kMRMediaRemoteNowPlayingInfoArtist"]);
        p[@"album"] = string(info[@"kMRMediaRemoteNowPlayingInfoAlbum"]);
        p[@"duration"] = @(finiteDouble(info[@"kMRMediaRemoteNowPlayingInfoDuration"]));
        p[@"elapsed"] = @(finiteDouble(info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"]));
        p[@"rate"] = @(finiteDouble(info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"]));
        id ts = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
        if ([ts isKindOfClass:[NSDate class]]) p[@"timestamp"] = @([(NSDate *)ts timeIntervalSince1970]);
        p[@"bundleID"] = bundleID ?: @"";
        p[@"parentBundleID"] = parentID ?: @"";
        p[@"pid"] = @(pid);
    }

    NSData *art = empty ? nil : info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
    NSUInteger artHash = [art isKindOfClass:[NSData class]] && art.length > 0 ? (art.length * 31u) ^ art.hash : 0;
    p[@"artworkHash"] = @(artHash);

    if ([p isEqualToDictionary:lastPayload] && artHash == lastArtworkHash) return;
    lastPayload = [p copy];

    if (artHash != lastArtworkHash && artHash != 0) {
        NSMutableDictionary *withArt = [p mutableCopy];
        withArt[@"artwork"] = [art base64EncodedStringWithOptions:0];
        emit(withArt);
    } else {
        emit(p);
    }
    lastArtworkHash = artHash;
}

static void refresh(void) {
    if (refreshInFlight && CFAbsoluteTimeGetCurrent() - refreshStarted < 3) return;
    refreshInFlight = YES;
    refreshStarted = CFAbsoluteTimeGetCurrent();

    __block NSDictionary *info = nil;
    __block BOOL playing = NO;
    __block NSString *bundleID = nil;
    __block NSString *parentID = nil;
    __block int pid = 0;
    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t main = dispatch_get_main_queue();

    dispatch_group_enter(group);
    MRGetInfo(main, ^(NSDictionary *value) {
        info = value;
        dispatch_group_leave(group);
    });
    dispatch_group_enter(group);
    MRGetIsPlaying(main, ^(Boolean value) {
        playing = value;
        dispatch_group_leave(group);
    });
    if (MRGetClient) {
        dispatch_group_enter(group);
        MRGetClient(main, ^(id client) {
            if (client && MRClientBundleID) bundleID = MRClientBundleID(client);
            if (client && MRClientParentBundleID) parentID = MRClientParentBundleID(client);
            dispatch_group_leave(group);
        });
    }
    if (MRGetPID) {
        dispatch_group_enter(group);
        MRGetPID(main, ^(int value) {
            pid = value;
            dispatch_group_leave(group);
        });
    }
    dispatch_group_notify(group, main, ^{
        refreshInFlight = NO;
        publish(info, playing, bundleID, parentID, pid);
    });
}

static void scheduleRefresh(void) {
    if (refreshScheduled) return;
    refreshScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(80 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        refreshScheduled = NO;
        refresh();
    });
}

static void handleCommand(NSString *line) {
    NSArray<NSString *> *parts = [line componentsSeparatedByString:@" "];
    NSString *cmd = parts.firstObject;
    if ([cmd isEqualToString:@"play"]) MRSendCommand(0, nil);
    else if ([cmd isEqualToString:@"pause"]) MRSendCommand(1, nil);
    else if ([cmd isEqualToString:@"toggle"]) MRSendCommand(2, nil);
    else if ([cmd isEqualToString:@"next"]) MRSendCommand(4, nil);
    else if ([cmd isEqualToString:@"previous"]) MRSendCommand(5, nil);
    else if ([cmd isEqualToString:@"seek"] && parts.count > 1 && MRSetElapsed) MRSetElapsed(parts[1].doubleValue);
    else if ([cmd isEqualToString:@"refresh"]) {
        lastPayload = nil;
        lastArtworkHash = 0;
    }
    scheduleRefresh();
}

static void startReadingCommands(void) {
    fcntl(STDIN_FILENO, F_SETFL, fcntl(STDIN_FILENO, F_GETFL) | O_NONBLOCK);
    static NSMutableData *buffer;
    buffer = [NSMutableData data];
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(source, ^{
        char chunk[4096];
        ssize_t n = read(STDIN_FILENO, chunk, sizeof chunk);
        if (n == 0) exit(0); // The app went away.
        if (n < 0) return;
        [buffer appendBytes:chunk length:(NSUInteger)n];
        while (YES) {
            NSRange nl = [buffer rangeOfData:[NSData dataWithBytes:"\n" length:1] options:0 range:NSMakeRange(0, buffer.length)];
            if (nl.location == NSNotFound) break;
            NSData *lineData = [buffer subdataWithRange:NSMakeRange(0, nl.location)];
            [buffer replaceBytesInRange:NSMakeRange(0, nl.location + 1) withBytes:NULL length:0];
            NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
            line = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (line.length) handleCommand(line);
        }
    });
    dispatch_resume(source);
    static dispatch_source_t retained;
    retained = source;
}

__attribute__((visibility("default")))
void cranny_media_main(void *interpreter, void *cv) {
    (void)interpreter; (void)cv;
    @autoreleasepool {
        void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
        if (!mr) {
            fprintf(stderr, "MediaRemote unavailable\n");
            exit(2);
        }
        MRGetInfo = (MRGetInfoFn)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
        MRGetIsPlaying = (MRGetIsPlayingFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        MRGetClient = (MRGetClientFn)dlsym(mr, "MRMediaRemoteGetNowPlayingClient");
        MRGetPID = (MRGetPIDFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationPID");
        MRRegister = (MRRegisterFn)dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications");
        MRSendCommand = (MRSendCommandFn)dlsym(mr, "MRMediaRemoteSendCommand");
        MRSetElapsed = (MRSetElapsedFn)dlsym(mr, "MRMediaRemoteSetElapsedTime");
        MRClientBundleID = (MRClientStringFn)dlsym(mr, "MRNowPlayingClientGetBundleIdentifier");
        MRClientParentBundleID = (MRClientStringFn)dlsym(mr, "MRNowPlayingClientGetParentAppBundleIdentifier");
        if (!MRGetInfo || !MRGetIsPlaying || !MRSendCommand || !MRRegister) {
            fprintf(stderr, "MediaRemote symbols missing\n");
            exit(3);
        }

        MRRegister(dispatch_get_main_queue());
        [[NSNotificationCenter defaultCenter] addObserverForName:nil object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            if ([note.name hasPrefix:@"kMRMediaRemote"] || [note.name hasPrefix:@"_MRMediaRemote"]) scheduleRefresh();
        }];

        // Safety net for players that do not post change notifications reliably.
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), 3 * NSEC_PER_SEC, NSEC_PER_SEC / 2);
        dispatch_source_set_event_handler(timer, ^{ refresh(); });
        dispatch_resume(timer);
        static dispatch_source_t keepTimer;
        keepTimer = timer;

        startReadingCommands();
        refresh();
        CFRunLoopRun();
    }
    exit(0);
}
