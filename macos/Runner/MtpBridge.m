#import "MtpBridge.h"

#import <libmtp.h>
#import <unistd.h>
#import <fcntl.h>
#import <pthread.h>
#import <os/log.h>

/// Per-device session record. We hold one libmtp device pointer per opened
/// deviceId; closing the session releases the libmtp resources and removes
/// the entry.
@interface MtpSession : NSObject
@property (nonatomic, assign) LIBMTP_mtpdevice_t *device;
@property (nonatomic, strong) NSString *deviceId;
@end

@implementation MtpSession
- (void)dealloc {
    if (_device != NULL) {
        LIBMTP_Release_Device(_device);
        _device = NULL;
    }
}
@end

/// Active in-flight transfer. One per `putBegin`/`getBegin` call.
///
/// For put: `writeFd` is exposed to Dart-driven writes; the background
/// thread runs `LIBMTP_Send_File_From_File_Descriptor(readFd)`.
/// For get: `readFd` is what Dart reads from; the background thread runs
/// `LIBMTP_Get_File_To_File_Descriptor(writeFd)`.
@interface MtpStream : NSObject
@property (nonatomic, strong) NSString *streamId;
@property (nonatomic, strong) NSString *deviceId;
@property (nonatomic, assign) int readFd;
@property (nonatomic, assign) int writeFd;
@property (nonatomic, assign) BOOL isPut;
@property (nonatomic, strong, nullable) NSThread *workerThread;
@property (nonatomic, assign) int64_t resultObjectId;  // put-only
@property (nonatomic, assign) int workerErrno;
@property (nonatomic, strong) NSCondition *doneCond;
@property (nonatomic, assign) BOOL done;
@end

@implementation MtpStream
- (instancetype)init {
    if ((self = [super init])) {
        _readFd = -1;
        _writeFd = -1;
        _resultObjectId = -1;
        _workerErrno = 0;
        _doneCond = [[NSCondition alloc] init];
    }
    return self;
}
@end

@implementation MtpBridge {
}

// ── Global state ───────────────────────────────────────────────────────────
//
// All shared state is guarded by `gLock`. libmtp itself is not thread-safe
// at the device level — never let two threads touch the same device at once.

static os_log_t gLog;
static NSLock *gLock;
static BOOL gInitialised = NO;
static NSMutableDictionary<NSString *, MtpSession *> *gSessions;
static NSMutableDictionary<NSString *, MtpStream *> *gStreams;

+ (void)initialize {
    if (self == [MtpBridge class]) {
        gLog = os_log_create("com.dapper.mtp", "bridge");
        gLock = [[NSLock alloc] init];
        gSessions = [NSMutableDictionary new];
        gStreams = [NSMutableDictionary new];
    }
}

+ (void)ensureInit {
    [gLock lock];
    if (!gInitialised) {
        LIBMTP_Init();
        // Quiet libmtp's stderr chatter — every device probe logs PTP errors
        // for non-MTP devices on the same bus.
        LIBMTP_Set_Debug(LIBMTP_DEBUG_NONE);
        gInitialised = YES;
    }
    [gLock unlock];
}

+ (BOOL)isAvailable {
    return YES;  // dylib loaded → available
}

+ (NSError *)errorWithCode:(NSInteger)code message:(NSString *)message {
    return [NSError errorWithDomain:@"com.dapper.mtp"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

// ── Enumeration ────────────────────────────────────────────────────────────

+ (NSArray<NSDictionary<NSString *, id> *> *)enumerate {
    [self ensureInit];
    LIBMTP_raw_device_t *rawDevices = NULL;
    int rawCount = 0;
    LIBMTP_error_number_t err =
        LIBMTP_Detect_Raw_Devices(&rawDevices, &rawCount);
    if (err != LIBMTP_ERROR_NONE) {
        if (rawDevices != NULL) free(rawDevices);
        return @[];
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *result =
        [NSMutableArray arrayWithCapacity:rawCount];
    for (int i = 0; i < rawCount; i++) {
        LIBMTP_mtpdevice_t *dev =
            LIBMTP_Open_Raw_Device_Uncached(&rawDevices[i]);
        if (dev == NULL) continue;

        NSString *serial = nil;
        char *serialC = LIBMTP_Get_Serialnumber(dev);
        if (serialC != NULL) {
            serial = [NSString stringWithUTF8String:serialC];
            free(serialC);
        }
        if (serial.length == 0) {
            // Fall back to bus/devnum so we always have a stable id within
            // a session — but it won't survive a replug.
            serial = [NSString stringWithFormat:@"bus%u_dev%u",
                      rawDevices[i].bus_location, rawDevices[i].devnum];
        }

        NSString *label = nil;
        char *nameC = LIBMTP_Get_Friendlyname(dev);
        if (nameC != NULL) {
            label = [NSString stringWithUTF8String:nameC];
            free(nameC);
        }
        if (label.length == 0) {
            char *model = LIBMTP_Get_Modelname(dev);
            if (model != NULL) {
                label = [NSString stringWithUTF8String:model];
                free(model);
            }
        }
        if (label.length == 0) label = @"MTP Device";

        int64_t total = 0;
        int64_t available = 0;
        if (LIBMTP_Get_Storage(dev, LIBMTP_STORAGE_SORTBY_NOTSORTED) == 0
            && dev->storage != NULL) {
            // Sum across all storages — most DAPs have one but Android
            // phones can expose internal + SD.
            for (LIBMTP_devicestorage_t *s = dev->storage; s != NULL; s = s->next) {
                total += s->MaxCapacity;
                available += s->FreeSpaceInBytes;
            }
        }

        [result addObject:@{
            @"deviceId": serial,
            @"label": label,
            @"totalBytes": @(total),
            @"availableBytes": @(available),
        }];
        LIBMTP_Release_Device(dev);
    }
    free(rawDevices);
    return result;
}

// ── Sessions ───────────────────────────────────────────────────────────────

/// Opens a libmtp handle for `deviceId` and stores it under [gSessions]. If
/// a session is already open, returns the cached entry.
+ (LIBMTP_mtpdevice_t *)deviceForId:(NSString *)deviceId
                              error:(NSError * _Nullable * _Nullable)error {
    [gLock lock];
    MtpSession *existing = gSessions[deviceId];
    [gLock unlock];
    if (existing != nil) return existing.device;

    [self ensureInit];
    LIBMTP_raw_device_t *rawDevices = NULL;
    int rawCount = 0;
    if (LIBMTP_Detect_Raw_Devices(&rawDevices, &rawCount) != LIBMTP_ERROR_NONE) {
        if (rawDevices != NULL) free(rawDevices);
        if (error) *error = [self errorWithCode:1 message:@"Detect failed"];
        return NULL;
    }

    LIBMTP_mtpdevice_t *match = NULL;
    for (int i = 0; i < rawCount; i++) {
        LIBMTP_mtpdevice_t *dev =
            LIBMTP_Open_Raw_Device_Uncached(&rawDevices[i]);
        if (dev == NULL) continue;
        char *serialC = LIBMTP_Get_Serialnumber(dev);
        NSString *serial = nil;
        if (serialC != NULL) {
            serial = [NSString stringWithUTF8String:serialC];
            free(serialC);
        }
        if (serial.length == 0) {
            serial = [NSString stringWithFormat:@"bus%u_dev%u",
                      rawDevices[i].bus_location, rawDevices[i].devnum];
        }
        if ([serial isEqualToString:deviceId]) {
            match = dev;
            break;
        }
        LIBMTP_Release_Device(dev);
    }
    free(rawDevices);

    if (match == NULL) {
        if (error) *error = [self errorWithCode:2 message:@"Device not connected"];
        return NULL;
    }
    // Storage handles are populated by Get_Storage; needed for any object op.
    LIBMTP_Get_Storage(match, LIBMTP_STORAGE_SORTBY_NOTSORTED);

    MtpSession *session = [[MtpSession alloc] init];
    session.device = match;
    session.deviceId = deviceId;
    [gLock lock];
    gSessions[deviceId] = session;
    [gLock unlock];
    return match;
}

+ (BOOL)openSession:(NSString *)deviceId
              error:(NSError * _Nullable * _Nullable)error {
    return [self deviceForId:deviceId error:error] != NULL;
}

+ (void)closeSession:(NSString *)deviceId {
    [gLock lock];
    MtpSession *session = gSessions[deviceId];
    [gSessions removeObjectForKey:deviceId];
    [gLock unlock];
    // Release in dealloc.
    (void)session;
}

+ (uint32_t)defaultStorageIdForDevice:(LIBMTP_mtpdevice_t *)dev {
    return (dev->storage != NULL) ? dev->storage->id : 0;
}

// ── Listing ────────────────────────────────────────────────────────────────

+ (nullable NSArray<NSDictionary<NSString *, id> *> *)
        listDevice:(NSString *)deviceId
    parentObjectId:(int64_t)parentObjectId
             error:(NSError * _Nullable * _Nullable)error {
    LIBMTP_mtpdevice_t *dev = [self deviceForId:deviceId error:error];
    if (dev == NULL) return @[];

    uint32_t storageId = [self defaultStorageIdForDevice:dev];
    // libmtp uses 0xFFFFFFFF for "the root of the storage". Our Dart side
    // passes 0 for root; translate.
    uint32_t parent = (parentObjectId == 0) ? 0xFFFFFFFF
                                            : (uint32_t)parentObjectId;

    LIBMTP_file_t *files =
        LIBMTP_Get_Files_And_Folders(dev, storageId, parent);
    NSMutableArray<NSDictionary<NSString *, id> *> *out = [NSMutableArray new];
    LIBMTP_file_t *cur = files;
    while (cur != NULL) {
        NSString *name = cur->filename != NULL
            ? [NSString stringWithUTF8String:cur->filename]
            : @"";
        BOOL isDir = (cur->filetype == LIBMTP_FILETYPE_FOLDER);
        int64_t size = (int64_t)cur->filesize;
        id modified = [NSNull null];
        if (cur->modificationdate > 0) {
            modified = @((int64_t)cur->modificationdate * 1000);
        }
        [out addObject:@{
            @"objectId": @((int64_t)cur->item_id),
            @"name": name,
            @"isDir": @(isDir),
            @"size": @(size),
            @"modifiedMillis": modified,
        }];
        LIBMTP_file_t *next = cur->next;
        LIBMTP_destroy_file_t(cur);
        cur = next;
    }
    return out;
}

// ── mkdir / delete ─────────────────────────────────────────────────────────

+ (nullable NSNumber *)mkdirDevice:(NSString *)deviceId
                    parentObjectId:(int64_t)parentObjectId
                              name:(NSString *)name
                             error:(NSError * _Nullable * _Nullable)error {
    LIBMTP_mtpdevice_t *dev = [self deviceForId:deviceId error:error];
    if (dev == NULL) return nil;
    uint32_t storageId = [self defaultStorageIdForDevice:dev];
    uint32_t parent = (parentObjectId == 0) ? 0xFFFFFFFF
                                            : (uint32_t)parentObjectId;
    // LIBMTP_Create_Folder mutates the passed name buffer; copy first.
    char *nameC = strdup(name.UTF8String);
    uint32_t id = LIBMTP_Create_Folder(dev, nameC, parent, storageId);
    free(nameC);
    if (id == 0) {
        if (error) {
            *error = [self errorWithCode:3
                                 message:@"LIBMTP_Create_Folder failed"];
        }
        return nil;
    }
    return @((int64_t)id);
}

+ (BOOL)deleteDevice:(NSString *)deviceId
            objectId:(int64_t)objectId
               error:(NSError * _Nullable * _Nullable)error {
    LIBMTP_mtpdevice_t *dev = [self deviceForId:deviceId error:error];
    if (dev == NULL) return NO;
    int rv = LIBMTP_Delete_Object(dev, (uint32_t)objectId);
    if (rv != 0) {
        if (error) *error = [self errorWithCode:4 message:@"Delete failed"];
        return NO;
    }
    return YES;
}

+ (int64_t)freeSpace:(NSString *)deviceId {
    LIBMTP_mtpdevice_t *dev = [self deviceForId:deviceId error:NULL];
    if (dev == NULL) return -1;
    LIBMTP_Get_Storage(dev, LIBMTP_STORAGE_SORTBY_NOTSORTED);
    if (dev->storage == NULL) return -1;
    return (int64_t)dev->storage->FreeSpaceInBytes;
}

// ── Put ────────────────────────────────────────────────────────────────────

+ (NSString *)nextStreamId {
    static int64_t counter = 0;
    int64_t v;
    [gLock lock];
    v = ++counter;
    [gLock unlock];
    return [NSString stringWithFormat:@"s%lld", v];
}

+ (void)runPutWorker:(MtpStream *)stream {
    LIBMTP_mtpdevice_t *dev = [self deviceForId:stream.deviceId error:NULL];
    if (dev == NULL) {
        stream.workerErrno = ENODEV;
        [stream.doneCond lock];
        stream.done = YES;
        [stream.doneCond broadcast];
        [stream.doneCond unlock];
        close(stream.readFd);
        return;
    }

    // Look up filedata stashed earlier in the stream's properties via NSThread
    // threadDictionary (set at putBegin).
    NSDictionary *meta = [[NSThread currentThread] threadDictionary][@"meta"];
    NSString *name = meta[@"name"];
    int64_t parentObjectId = [meta[@"parent"] longLongValue];
    int64_t totalBytes = [meta[@"total"] longLongValue];

    LIBMTP_file_t *fd = LIBMTP_new_file_t();
    fd->filename = strdup(name.UTF8String);
    fd->filesize = (uint64_t)totalBytes;
    fd->filetype = LIBMTP_FILETYPE_UNKNOWN;
    fd->parent_id = (parentObjectId == 0) ? 0xFFFFFFFF
                                          : (uint32_t)parentObjectId;
    fd->storage_id = [self defaultStorageIdForDevice:dev];

    int rv = LIBMTP_Send_File_From_File_Descriptor(
        dev, stream.readFd, fd, NULL, NULL);
    int64_t objectId = (rv == 0) ? (int64_t)fd->item_id : -1;
    LIBMTP_destroy_file_t(fd);

    close(stream.readFd);
    stream.readFd = -1;

    stream.resultObjectId = objectId;
    if (rv != 0) {
        stream.workerErrno = EIO;
        os_log_error(gLog, "LIBMTP_Send_File_From_File_Descriptor failed (rv=%d)",
                     rv);
        // Surface libmtp's own error stack to logs.
        LIBMTP_Dump_Errorstack(dev);
        LIBMTP_Clear_Errorstack(dev);
    }
    [stream.doneCond lock];
    stream.done = YES;
    [stream.doneCond broadcast];
    [stream.doneCond unlock];
}

+ (nullable NSString *)putBeginDevice:(NSString *)deviceId
                        parentObjectId:(int64_t)parentObjectId
                                  name:(NSString *)name
                            totalBytes:(int64_t)totalBytes
                                 error:(NSError * _Nullable * _Nullable)error {
    int fds[2];
    if (pipe(fds) != 0) {
        if (error) *error = [self errorWithCode:5 message:@"pipe() failed"];
        return nil;
    }
    MtpStream *stream = [[MtpStream alloc] init];
    stream.streamId = [self nextStreamId];
    stream.deviceId = deviceId;
    stream.readFd = fds[0];
    stream.writeFd = fds[1];
    stream.isPut = YES;

    NSThread *thread = [[NSThread alloc] initWithBlock:^{
        [[NSThread currentThread] threadDictionary][@"meta"] = @{
            @"name": name ?: @"file",
            @"parent": @(parentObjectId),
            @"total": @(totalBytes),
        };
        [self runPutWorker:stream];
    }];
    thread.name = [@"mtp-put-" stringByAppendingString:stream.streamId];
    stream.workerThread = thread;

    [gLock lock];
    gStreams[stream.streamId] = stream;
    [gLock unlock];

    [thread start];
    return stream.streamId;
}

+ (BOOL)putChunk:(NSString *)streamId
           bytes:(NSData *)bytes
           error:(NSError * _Nullable * _Nullable)error {
    [gLock lock];
    MtpStream *stream = gStreams[streamId];
    [gLock unlock];
    if (stream == nil || stream.writeFd < 0) {
        if (error) *error = [self errorWithCode:6 message:@"Unknown streamId"];
        return NO;
    }
    const uint8_t *buf = bytes.bytes;
    NSUInteger remaining = bytes.length;
    while (remaining > 0) {
        ssize_t n = write(stream.writeFd, buf, remaining);
        if (n < 0) {
            if (errno == EINTR) continue;
            if (error) {
                *error = [self errorWithCode:7
                                     message:[NSString stringWithFormat:
                                             @"write() failed: %s",
                                             strerror(errno)]];
            }
            return NO;
        }
        buf += n;
        remaining -= (NSUInteger)n;
    }
    return YES;
}

+ (nullable NSNumber *)putCommit:(NSString *)streamId
                           error:(NSError * _Nullable * _Nullable)error {
    [gLock lock];
    MtpStream *stream = gStreams[streamId];
    [gLock unlock];
    if (stream == nil) {
        if (error) *error = [self errorWithCode:6 message:@"Unknown streamId"];
        return nil;
    }
    // Closing the write end gives libmtp an EOF on the read end.
    if (stream.writeFd >= 0) {
        close(stream.writeFd);
        stream.writeFd = -1;
    }
    [stream.doneCond lock];
    while (!stream.done) {
        [stream.doneCond wait];
    }
    [stream.doneCond unlock];

    [gLock lock];
    [gStreams removeObjectForKey:streamId];
    [gLock unlock];

    if (stream.workerErrno != 0 || stream.resultObjectId < 0) {
        if (error) {
            *error = [self errorWithCode:8 message:@"Send failed"];
        }
        return nil;
    }
    return @(stream.resultObjectId);
}

+ (void)putAbort:(NSString *)streamId {
    [gLock lock];
    MtpStream *stream = gStreams[streamId];
    [gStreams removeObjectForKey:streamId];
    [gLock unlock];
    if (stream == nil) return;
    if (stream.writeFd >= 0) {
        close(stream.writeFd);
        stream.writeFd = -1;
    }
    // Worker thread will see EOF on its read fd and finish; we don't wait —
    // the in-flight upload becomes a stranded partial object on the device,
    // which the engine deletes via a follow-up `delete` if it cares.
}

// ── Get ────────────────────────────────────────────────────────────────────

+ (void)runGetWorker:(MtpStream *)stream objectId:(int64_t)objectId {
    LIBMTP_mtpdevice_t *dev = [self deviceForId:stream.deviceId error:NULL];
    if (dev == NULL) {
        close(stream.writeFd);
        stream.writeFd = -1;
        [stream.doneCond lock];
        stream.done = YES;
        [stream.doneCond broadcast];
        [stream.doneCond unlock];
        return;
    }
    int rv = LIBMTP_Get_File_To_File_Descriptor(
        dev, (uint32_t)objectId, stream.writeFd, NULL, NULL);
    if (rv != 0) {
        stream.workerErrno = EIO;
        LIBMTP_Dump_Errorstack(dev);
        LIBMTP_Clear_Errorstack(dev);
    }
    close(stream.writeFd);
    stream.writeFd = -1;
    [stream.doneCond lock];
    stream.done = YES;
    [stream.doneCond broadcast];
    [stream.doneCond unlock];
}

+ (nullable NSString *)getBeginDevice:(NSString *)deviceId
                              objectId:(int64_t)objectId
                                 error:(NSError * _Nullable * _Nullable)error {
    int fds[2];
    if (pipe(fds) != 0) {
        if (error) *error = [self errorWithCode:5 message:@"pipe() failed"];
        return nil;
    }
    MtpStream *stream = [[MtpStream alloc] init];
    stream.streamId = [self nextStreamId];
    stream.deviceId = deviceId;
    stream.readFd = fds[0];
    stream.writeFd = fds[1];
    stream.isPut = NO;

    NSThread *thread = [[NSThread alloc] initWithBlock:^{
        [self runGetWorker:stream objectId:objectId];
    }];
    thread.name = [@"mtp-get-" stringByAppendingString:stream.streamId];
    stream.workerThread = thread;

    [gLock lock];
    gStreams[stream.streamId] = stream;
    [gLock unlock];

    [thread start];
    return stream.streamId;
}

+ (nullable NSData *)getChunk:(NSString *)streamId
                     maxBytes:(NSUInteger)maxBytes
                        error:(NSError * _Nullable * _Nullable)error {
    [gLock lock];
    MtpStream *stream = gStreams[streamId];
    [gLock unlock];
    if (stream == nil || stream.readFd < 0) {
        if (error) *error = [self errorWithCode:6 message:@"Unknown streamId"];
        return nil;
    }
    NSMutableData *out = [NSMutableData dataWithLength:maxBytes];
    ssize_t n = read(stream.readFd, out.mutableBytes, maxBytes);
    if (n < 0) {
        if (errno == EINTR || errno == EAGAIN) {
            return [NSData data];
        }
        if (error) {
            *error = [self errorWithCode:7
                                 message:[NSString stringWithFormat:
                                         @"read() failed: %s", strerror(errno)]];
        }
        return nil;
    }
    if (n == 0) {
        return [NSData data];  // EOF
    }
    [out setLength:(NSUInteger)n];
    return out;
}

+ (void)getEnd:(NSString *)streamId {
    [gLock lock];
    MtpStream *stream = gStreams[streamId];
    [gStreams removeObjectForKey:streamId];
    [gLock unlock];
    if (stream == nil) return;
    if (stream.readFd >= 0) {
        close(stream.readFd);
        stream.readFd = -1;
    }
    [stream.doneCond lock];
    while (!stream.done) {
        [stream.doneCond wait];
    }
    [stream.doneCond unlock];
}

@end
