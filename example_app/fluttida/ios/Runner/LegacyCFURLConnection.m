#import "LegacyCFURLConnection.h"
#import <CFNetwork/CFNetwork.h>

void FluttidaCreateCFURLConnection(NSURLRequest *request) {
    // NSURLRequest <-> CFURLRequest is toll-free bridged
    CFURLRequestRef cfReq = (__bridge CFURLRequestRef)request;

    CFURLConnectionRef conn =
        CFURLConnectionCreateWithRequest(kCFAllocatorDefault, cfReq, NULL);

    if (conn) {
        CFRelease(conn);
    }
}
