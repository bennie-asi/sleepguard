#import <Foundation/Foundation.h>
#include "../../internal/platform/native_darwin.m"

int main(void) {
    @autoreleasepool {
        NSMutableDictionary *empty=[NSMutableDictionary dictionary];
        sg_add_assertions(empty,kIOReturnSuccess,NULL);
        NSCAssert(empty[@"error"]==nil,@"empty assertions are not a collection error");
        NSCAssert([empty[@"assertions"] count]==0,@"empty assertions must be a valid empty array");

        NSMutableDictionary *failed=[NSMutableDictionary dictionary];
        sg_add_assertions(failed,kIOReturnError,NULL);
        NSCAssert([failed[@"error"] hasPrefix:@"IOPMCopyAssertionsByProcess:"],@"real IOKit errors must remain visible");
        NSCAssert(failed[@"assertions"]==nil,@"an IOKit error must not be reported as an empty sample");
    }
    return 0;
}
