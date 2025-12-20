#import "NativeHttp.h"
#include <curl/curl.h>
#include <string>
#include <vector>
#include <map>

// Helper callback for writing response data
static size_t WriteCallback(void *contents, size_t size, size_t nmemb, void *userp) {
    size_t realsize = size * nmemb;
    std::string *mem = (std::string *)userp;
    mem->append((char *)contents, realsize);
    return realsize;
}

@implementation NativeHttp

+ (NSDictionary *)performRequest:(NSString *)method
                             url:(NSString *)url
                         headers:(NSDictionary<NSString *, NSString *> *)headers
                            body:(NSString *)body
                       timeoutMs:(NSNumber *)timeoutMs {
    
    CURL *curl;
    CURLcode res;
    std::string readBuffer;
    long response_code = 0;
    std::string error_msg;
    double total_time = 0;

    curl = curl_easy_init();
    if (!curl) {
        return @{
            @"status": [NSNull null],
            @"body": @"",
            @"durationMs": @0,
            @"error": @"Failed to init curl"
        };
    }

    struct curl_slist *chunk = NULL;

    // Set URL
    curl_easy_setopt(curl, CURLOPT_URL, [url UTF8String]);

    // Set Method
    if ([method isEqualToString:@"POST"]) {
        curl_easy_setopt(curl, CURLOPT_POST, 1L);
    } else if ([method isEqualToString:@"PUT"]) {
        curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "PUT");
    } else if ([method isEqualToString:@"HEAD"]) {
        curl_easy_setopt(curl, CURLOPT_NOBODY, 1L);
    } else if (![method isEqualToString:@"GET"]) {
        curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, [method UTF8String]);
    }

    // Set Headers
    if (headers) {
        for (NSString *key in headers) {
            NSString *value = headers[key];
            NSString *headerString = [NSString stringWithFormat:@"%@: %@", key, value];
            chunk = curl_slist_append(chunk, [headerString UTF8String]);
        }
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, chunk);
    }

    // Set Body
    if (body && body.length > 0) {
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, [body UTF8String]);
        curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, (long)[body lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
    }

    // Set Timeout
    if (timeoutMs) {
        curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, [timeoutMs longValue]);
    }

    // Response Callback
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, WriteCallback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &readBuffer);

    // TLS Verification with bundled CA (cacert.pem in Runner/Resources)
    NSString *caPath = [[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"];
    if (caPath) {
        curl_easy_setopt(curl, CURLOPT_CAINFO, [caPath UTF8String]);
    }
    // Keep verification ON
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 2L);

    // Perform request
    res = curl_easy_perform(curl);

    // Get Info
    if (res == CURLE_OK) {
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &response_code);
        curl_easy_getinfo(curl, CURLINFO_TOTAL_TIME, &total_time);
    } else {
        error_msg = curl_easy_strerror(res);
    }

    // Cleanup
    curl_easy_cleanup(curl);
    if (chunk) {
        curl_slist_free_all(chunk);
    }

    // Prepare Result
    if (res != CURLE_OK) {
        return @{
            @"status": [NSNull null],
            @"body": @"",
            @"durationMs": @((int)(total_time * 1000)),
            @"error": [NSString stringWithUTF8String:error_msg.c_str()]
        };
    }

    return @{
        @"status": @(response_code),
        @"body": [NSString stringWithUTF8String:readBuffer.c_str()] ?: @"",
        @"durationMs": @((int)(total_time * 1000)),
        @"error": [NSNull null]
    };
}

@end
