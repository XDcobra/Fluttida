#import "LegacyCFURLConnection.h"
#import <Foundation/Foundation.h>

@interface FluttidaConnDelegate : NSObject <NSURLConnectionDelegate, NSURLConnectionDataDelegate>
@end
@implementation FluttidaConnDelegate
@end

void FluttidaCreateCFURLConnection(NSURLRequest *request) {
    if (!request) return;

    static FluttidaConnDelegate *delegate;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        delegate = [FluttidaConnDelegate new];
    });

    // Triggert den NSURLConnection Stack (deprecated, aber vorhanden)
    NSURLConnection *conn = [[NSURLConnection alloc] initWithRequest:request
                                                            delegate:delegate
                                                    startImmediately:YES];
    (void)conn;
}
