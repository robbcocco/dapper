#ifndef MtpBridge_h
#define MtpBridge_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Objective-C bridge for libmtp.
///
/// Bridges the chunked Dart RPC surface (`putBegin`/`putChunk`/`putCommit`)
/// to libmtp's blocking `LIBMTP_Send_File_From_File_Descriptor` API via
/// `pipe(2)`. The plugin keeps a background thread per in-flight transfer:
/// the thread runs libmtp blocking on the pipe's read end while Dart's
/// `putChunk` calls write into the pipe's write end. `putCommit` closes the
/// write end and joins the thread, returning the new object id.
///
/// All methods that take `deviceId` accept the serial number returned by
/// `enumerate`. A session must be opened with `openSession` first.
///
/// Every method that takes `(NSError **)error` becomes a `throws` function
/// in Swift; the `error` parameter is dropped. NS_SWIFT_NAME pins the
/// resulting Swift selectors so the call sites are readable.
@interface MtpBridge : NSObject

/// True when libmtp is linked + initialised. False on the very rare case the
/// dylib failed to load (kept for symmetry with `MtpClient.isSupported()`).
+ (BOOL)isAvailable NS_SWIFT_NAME(isAvailable());

/// Enumerates connected MTP devices.
/// Each entry: `@{ "deviceId": NSString, "label": NSString,
///                 "totalBytes": NSNumber, "availableBytes": NSNumber }`.
+ (NSArray<NSDictionary<NSString *, id> *> *)enumerate
    NS_SWIFT_NAME(enumerate());

+ (BOOL)openSession:(NSString *)deviceId
              error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(openSession(deviceId:));

+ (void)closeSession:(NSString *)deviceId
    NS_SWIFT_NAME(closeSession(deviceId:));

/// Lists children of `parentObjectId` (use 0 for the storage root).
/// Each entry: `@{ "objectId": NSNumber(int64), "name": NSString,
///                 "isDir": NSNumber(bool), "size": NSNumber(int64),
///                 "modifiedMillis": NSNumber(int64) | NSNull }`.
+ (nullable NSArray<NSDictionary<NSString *, id> *> *)
        listDevice:(NSString *)deviceId
    parentObjectId:(int64_t)parentObjectId
             error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(list(deviceId:parentObjectId:));

/// Creates a folder. Returns the new object id, or `-1` on failure.
/// Returns nil on failure (Swift: throws). NSNumber wraps the int64 object id.
+ (nullable NSNumber *)mkdirDevice:(NSString *)deviceId
                    parentObjectId:(int64_t)parentObjectId
                              name:(NSString *)name
                             error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(mkdir(deviceId:parentObjectId:name:));

+ (BOOL)deleteDevice:(NSString *)deviceId
            objectId:(int64_t)objectId
               error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(delete(deviceId:objectId:));

/// Free storage bytes on the device's first storage, or -1 if unknown.
+ (int64_t)freeSpace:(NSString *)deviceId
    NS_SWIFT_NAME(freeSpace(deviceId:));

// ── Put (send a file in chunks) ───────────────────────────────────────────

/// Begins a streamed send. Returns the streamId (opaque). On error returns
/// nil and populates `error`.
+ (nullable NSString *)putBeginDevice:(NSString *)deviceId
                        parentObjectId:(int64_t)parentObjectId
                                  name:(NSString *)name
                            totalBytes:(int64_t)totalBytes
                                 error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(putBegin(deviceId:parentObjectId:name:totalBytes:));

+ (BOOL)putChunk:(NSString *)streamId
           bytes:(NSData *)bytes
           error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(putChunk(streamId:bytes:));

/// Closes the write fd, joins the background send thread, returns the new
/// object id. On failure returns -1.
/// Returns nil on failure (Swift: throws). NSNumber wraps the int64 object id.
+ (nullable NSNumber *)putCommit:(NSString *)streamId
                           error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(putCommit(streamId:));

+ (void)putAbort:(NSString *)streamId
    NS_SWIFT_NAME(putAbort(streamId:));

// ── Get (read a file in chunks) ───────────────────────────────────────────

+ (nullable NSString *)getBeginDevice:(NSString *)deviceId
                              objectId:(int64_t)objectId
                                 error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(getBegin(deviceId:objectId:));

/// Reads up to maxBytes from the in-flight get. Returns the bytes available
/// (possibly fewer than maxBytes). Empty data signals end-of-file.
+ (nullable NSData *)getChunk:(NSString *)streamId
                     maxBytes:(NSUInteger)maxBytes
                        error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(getChunk(streamId:maxBytes:));

+ (void)getEnd:(NSString *)streamId
    NS_SWIFT_NAME(getEnd(streamId:));

@end

NS_ASSUME_NONNULL_END

#endif /* MtpBridge_h */
