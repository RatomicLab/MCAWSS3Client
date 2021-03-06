// Copyright (c) 2014, Mirego
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// - Redistributions of source code must retain the above copyright notice,
//   this list of conditions and the following disclaimer.
// - Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
// - Neither the name of the Mirego nor the names of its contributors may
//   be used to endorse or promote products derived from this software without
//   specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

#import "MCAWSS3Client.h"
#import <CommonCrypto/CommonHMAC.h>

@interface MCAWSS3Client ()
@property (nonatomic) AFHTTPRequestOperationManager *requestOperationManager;
- (NSString*)canonicalizedResourceWithKey:(NSString*)key;
- (NSString*)stringToSignForRequestMethod:(NSString*)requestMethod contentMD5:(NSString*)contentMD5 mimeType:(NSString*)mimeType dateString:(NSString*)dateString headers:(NSString*)canonicalizedAmzHeaders resource:(NSString*)canonicalizedResource;
- (NSString*)dateString;
- (NSString*)base64EncodedStringFromData:(NSData*)data;
- (NSData*)HMACSHA1WithKey:(NSString*)key string:(NSString*)string;
- (NSData*)MD5FromData:(NSData*)data;
@end


@implementation MCAWSS3Client

- (instancetype)init {
    return [self initWithBaseURL:[NSURL URLWithString:@"http://s3.amazonaws.com"]];
}

- (instancetype)initWithBaseURL:(NSURL*)url
{
    if (self = [super init]) {
        _requestOperationManager = [[AFHTTPRequestOperationManager alloc] initWithBaseURL:url];
        _integrityCheck = YES;   //default
    }
    return self;
}

- (void)putObjectWithData:(NSData*)data key:(NSString*)key mimeType:(NSString*)mimeType success:(void (^)(AFHTTPRequestOperation* operation, id responseObject))success failure:(void (^)(AFHTTPRequestOperation* operation, NSError* error))failure
{
    [self putObjectWithData:data key:key mimeType:mimeType permission:MCAWSS3ObjectPermissionsPrivate progress:NULL success:success failure:failure];
}

- (void)putObjectWithData:(NSData*)data key:(NSString*)key mimeType:(NSString*)mimeType progress:(void (^)(NSUInteger bytesWritten, long long totalBytesWritten, long long totalBytesExpectedToWrite))progress success:(void (^)(AFHTTPRequestOperation* operation, id responseObject))success failure:(void (^)(AFHTTPRequestOperation* operation, NSError* error))failure
{
    [self putObjectWithData:data key:key mimeType:mimeType permission:MCAWSS3ObjectPermissionsPrivate progress:progress success:success failure:failure];
}

- (void)putObjectWithData:(NSData*)data key:(NSString*)key mimeType:(NSString*)mimeType permission:(MCAWSS3ObjectPermission)permission success:(void (^)(AFHTTPRequestOperation* operation, id responseObject))success failure:(void (^)(AFHTTPRequestOperation* operation, NSError* error))failure
{
    [self putObjectWithData:data key:key mimeType:mimeType permission:permission progress:NULL success:success failure:failure];
}

- (void)putObjectWithData:(NSData*)data key:(NSString*)key mimeType:(NSString*)mimeType permission:(MCAWSS3ObjectPermission)permission progress:(void (^)(NSUInteger bytesWritten, long long totalBytesWritten, long long totalBytesExpectedToWrite))progress success:(void (^)(AFHTTPRequestOperation* operation, id responseObject))success failure:(void (^)(AFHTTPRequestOperation* operation, NSError* error))failure
{
    NSMutableDictionary *headers = [[NSMutableDictionary alloc] init];
    NSString* dateString = [self dateString];
    [headers setObject:dateString forKey:@"Date"];

    NSString* contentMD5 = @"";
    if (self.integrityCheck) {
        contentMD5 = [self base64EncodedStringFromData:[self MD5FromData:data]];
        [headers setObject:contentMD5 forKey:@"Content-MD5"];
    }

    NSMutableArray* xAmzHeaders = [[NSMutableArray alloc] init];

    switch (permission) {
        case MCAWSS3ObjectPermissionsPrivate:
            [headers setObject:@"private" forKey:@"x-amz-acl"];
            break;
        case MCAWSS3ObjectPermissionPublicRead:
            [headers setObject:@"public-read" forKey:@"x-amz-acl"];
            break;
        case MCAWSS3ObjectPermissionPublicReadWrite:
            [headers setObject:@"public-read-write" forKey:@"x-amz-acl"];
            break;
        case MCAWSS3ObjectPermissionAuthenticatedRead:
            [headers setObject:@"authenticated-read" forKey:@"x-amz-acl"];
            break;
        case MCAWSS3ObjectPermissionBucketOwnerRead:
            [headers setObject:@"bucket-owner-read" forKey:@"x-amz-acl"];
            break;
        case MCAWSS3ObjectPermissionBucketOwnerFullControl:
            [headers setObject:@"bucket-owner-full-control" forKey:@"x-amz-acl"];
            break;
    }
    [xAmzHeaders addObject:@"x-amz-acl"];

    if (self.sessionToken) {
        [headers setObject:self.sessionToken forKey:@"x-amz-security-token"];
        [xAmzHeaders addObject:@"x-amz-security-token"];
    }

    [xAmzHeaders sortUsingSelector:@selector(compare:)];
    NSString* canonicalizedAmzHeaders = @"";
    for (NSString* xAmzHeader in xAmzHeaders) {
        NSString* headerValue = [headers objectForKey:xAmzHeader];
        canonicalizedAmzHeaders = [canonicalizedAmzHeaders
                                   stringByAppendingFormat:@"%@:%@\n", 
                                   xAmzHeader, 
                                   headerValue];
    }

    NSString* requestMethod = @"PUT";
    NSString* canonicalizedResource = [self canonicalizedResourceWithKey:key];
    NSString* stringToSign = [self stringToSignForRequestMethod:requestMethod contentMD5:contentMD5 mimeType:mimeType dateString:dateString headers:canonicalizedAmzHeaders resource:canonicalizedResource];

    NSString* signature = [self base64EncodedStringFromData:[self HMACSHA1WithKey:self.secretKey string:stringToSign]];
    NSString* authorizationString = [NSString stringWithFormat:@"AWS %@:%@", self.accessKey, signature];
    [headers setObject:authorizationString forKey:@"Authorization"];
    
    [headers setObject:mimeType forKey:@"Content-Type"];
    
    NSMutableURLRequest *request = [[self.requestOperationManager requestSerializer] requestWithMethod:@"PUT" URLString:[[NSURL URLWithString:canonicalizedResource relativeToURL:_requestOperationManager.baseURL] absoluteString] parameters:nil error:nil];
    [request setAllHTTPHeaderFields:headers];
    [request addValue:[NSString stringWithFormat:@"%ld", (long)[data length]] forHTTPHeaderField:@"Content-Length"];
    [request setHTTPBody:data];
    AFHTTPRequestOperation *requestOperation = [self.requestOperationManager HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
        if (success) success(operation, responseObject);
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        if (failure) failure(operation, error);
    }];
    if (progress) {
        [requestOperation setUploadProgressBlock:progress];
    }

    [self.requestOperationManager.operationQueue addOperation:requestOperation];
}

- (void)getObjectToFileAtPath:(NSString*)path key:(NSString*)key success:(void (^)(AFHTTPRequestOperation* operation, id responseObject))success failure:(void (^)(AFHTTPRequestOperation* operation, NSError* error))failure
{
    NSMutableDictionary *headers = [[NSMutableDictionary alloc] init];
    
    NSString* dateString = [self dateString];
    [headers setObject:dateString forKey:@"Date"];

    NSString* canonicalizedAmzHeaders = @"";
    NSString* requestMethod = @"GET";
    NSString* canonicalizedResource = [self canonicalizedResourceWithKey:key];
    NSString* stringToSign = [self stringToSignForRequestMethod:requestMethod contentMD5:@"" mimeType:@"" dateString:dateString headers:canonicalizedAmzHeaders resource:canonicalizedResource];

    NSString* signature = [self base64EncodedStringFromData:[self HMACSHA1WithKey:self.secretKey string:stringToSign]];
    NSString* authorizationString = [NSString stringWithFormat:@"AWS %@:%@", self.accessKey, signature];
    [headers setObject:authorizationString forKey:@"Authorization"];

    NSMutableURLRequest *request = [[self.requestOperationManager requestSerializer] requestWithMethod:@"PUT" URLString:[[NSURL URLWithString:canonicalizedResource relativeToURL:_requestOperationManager.baseURL] absoluteString] parameters:nil error:nil];
    [request setAllHTTPHeaderFields:headers];
    
    AFHTTPRequestOperation *requestOperation = [self.requestOperationManager HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
        if (success) success(operation, responseObject);
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        if (failure) failure(operation, error);
    }];
    
    [requestOperation setOutputStream:[NSOutputStream outputStreamToFileAtPath:path append:NO]];
    [self.requestOperationManager.operationQueue addOperation:requestOperation];
}


//------------------------------------------------------------------------------
#pragma mark - Private Implementation
//------------------------------------------------------------------------------

- (NSString*)canonicalizedResourceWithKey:(NSString*)key
{
    return [NSString stringWithFormat:@"/%@/%@", self.bucket, [self URLEncodedStringFromString:key encoding:NSUTF8StringEncoding]];
}

- (NSString*)stringToSignForRequestMethod:(NSString*)requestMethod contentMD5:(NSString*)contentMD5 mimeType:(NSString*)mimeType dateString:(NSString*)dateString headers:(NSString*)canonicalizedAmzHeaders resource:(NSString*)canonicalizedResource
{
    return [NSString stringWithFormat:@"%@\n%@\n%@\n%@\n%@%@", requestMethod, contentMD5, mimeType, dateString, canonicalizedAmzHeaders, canonicalizedResource];
}

- (NSString*)base64EncodedStringFromData:(NSData*)data
{
    NSUInteger length = [data length];
    NSMutableData* mutableData = [NSMutableData dataWithLength:((length + 2) / 3)*  4];

    uint8_t* input = (uint8_t*)[data bytes];
    uint8_t* output = (uint8_t*)[mutableData mutableBytes];

    for (NSUInteger i = 0; i < length; i += 3) {
        NSUInteger value = 0;
        for (NSUInteger j = i; j < (i + 3); j++) {
            value <<= 8;
            if (j < length) {
                value |= (0xFF & input[j]);
            }
        }

        static uint8_t const kAFBase64EncodingTable[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

        NSUInteger idx = (i / 3)*  4;
        output[idx + 0] = kAFBase64EncodingTable[(value >> 18) & 0x3F];
        output[idx + 1] = kAFBase64EncodingTable[(value >> 12) & 0x3F];
        output[idx + 2] = (i + 1) < length ? kAFBase64EncodingTable[(value >> 6)  & 0x3F] : '=';
        output[idx + 3] = (i + 2) < length ? kAFBase64EncodingTable[(value >> 0)  & 0x3F] : '=';
    }

    NSString* encodedString = [[NSString alloc] initWithData:mutableData encoding:NSASCIIStringEncoding];
    return encodedString;
}

- (NSData*)HMACSHA1WithKey:(NSString*)key string:(NSString*)string
{
	NSData* stringData = [string dataUsingEncoding:NSUTF8StringEncoding];
	NSData* keyData = [key dataUsingEncoding:NSUTF8StringEncoding];

	uint8_t digest[CC_SHA1_DIGEST_LENGTH] = {0};

	CCHmacContext hmacContext;
	CCHmacInit(&hmacContext, kCCHmacAlgSHA1, [keyData bytes], [keyData length]);
	CCHmacUpdate(&hmacContext, [stringData bytes], [stringData length]);
	CCHmacFinal(&hmacContext, digest);

	return [NSData dataWithBytes:digest length:CC_SHA1_DIGEST_LENGTH];
}

- (NSData*)MD5FromData:(NSData*)data
{
    uint8_t digest[CC_MD5_DIGEST_LENGTH] = {0};

    CC_MD5([data bytes], [data length], digest);

    return [NSData dataWithBytes:digest length:CC_MD5_DIGEST_LENGTH];
}

- (NSString*)URLEncodedStringFromString:(NSString*)string encoding:(NSStringEncoding)encoding
{
    static NSString* const kAFLegalCharactersToBeEscaped = @"?!@#$^&%*+,:;='\"`<>()[]{}/\\|~ ";

    // Following the suggestion in documentation for `CFURLCreateStringByAddingPercentEscapes` to "pre-process" URL strings (using stringByReplacingPercentEscapesUsingEncoding) with unpredictable sequences that may already contain percent escapes.
	NSString* encodedURL = (__bridge_transfer NSString*)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (__bridge CFStringRef)[string stringByReplacingPercentEscapesUsingEncoding:encoding], NULL, (__bridge CFStringRef)kAFLegalCharactersToBeEscaped, CFStringConvertNSStringEncodingToEncoding(encoding));
    return encodedURL;
}

- (NSString*)dateString
{
    NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
    [dateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    [dateFormatter setDateFormat:@"EEE, d MMM yyyy HH:mm:ss Z"];

    return [dateFormatter stringFromDate:[NSDate date]];
}

@end