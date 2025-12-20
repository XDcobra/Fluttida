#import <Foundation/Foundation.h>

@interface NativeHttp : NSObject

+ (NSDictionary *)performRequest:(NSString *)method
                             url:(NSString *)url
                         headers:(NSDictionary<NSString *, NSString *> *)headers
                            body:(NSString *)body
                       timeoutMs:(NSNumber *)timeoutMs;

@end
