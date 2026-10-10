//go:build darwin && cgo

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <IOKit/ps/IOPowerSources.h>
#include <CoreGraphics/CoreGraphics.h>
#include <sys/sysctl.h>
#include <stdlib.h>

int sg_request_quit(int pid) {
    @autoreleasepool {
        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        if (!app || !app.bundleIdentifier) return 1;
        return [app terminate] ? 0 : 2;
    }
}

static id clean(id value) {
    if ([value isKindOfClass:[NSDate class]]) return @([(NSDate *)value timeIntervalSince1970]);
    if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]) return value;
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *a=[NSMutableArray array];for(id v in value)[a addObject:clean(v)];return a;
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *d=[NSMutableDictionary dictionary];for(id k in value)d[[k description]]=clean(value[k]);return d;
    }
    return [value description] ?: @"";
}

char *sg_snapshot(void) {
    @autoreleasepool {
        NSMutableDictionary *result=[NSMutableDictionary dictionary];
        CFDictionaryRef raw=NULL;
        IOReturn rc=IOPMCopyAssertionsByProcess(&raw);
        if(rc!=kIOReturnSuccess || !raw) {
            result[@"error"]=[NSString stringWithFormat:@"IOPMCopyAssertionsByProcess: %d",rc];
        } else {
            NSMutableArray *rows=[NSMutableArray array];
            for(id pid in (NSDictionary *)raw) {
                for(NSDictionary *props in [(NSDictionary *)raw objectForKey:pid]) {
                    [rows addObject:@{@"pid":@([pid intValue]),@"properties":clean(props)}];
                }
            }
            result[@"assertions"]=rows;
            CFRelease(raw);
        }
        result[@"idle_seconds"]=@(CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateHIDSystemState,kCGAnyInputEventType));
        CGDirectDisplayID displays[32];uint32_t count=0;
        CGError err=CGGetOnlineDisplayList(32,displays,&count);
        BOOL asleep=YES;
        if(err!=kCGErrorSuccess || count==0) result[@"error"]=@"无法确定显示器状态";
        for(uint32_t i=0;i<count;i++)if(!CGDisplayIsAsleep(displays[i]))asleep=NO;
        result[@"display_asleep"]=@(asleep);
        CFTypeRef power=IOPSCopyPowerSourcesInfo();
        if(power) {
            CFStringRef source=IOPSGetProvidingPowerSourceType(power);
            result[@"power_source"]=source ? (NSString *)source : @"Unknown";
            CFRelease(power);
        }
        char boot[128]={0};size_t n=sizeof(boot);
        if(sysctlbyname("kern.bootsessionuuid",boot,&n,NULL,0)!=0)result[@"error"]=@"无法读取 boot session";
        result[@"boot_id"]=[NSString stringWithUTF8String:boot];
        struct timeval wake={0};n=sizeof(wake);
        if(sysctlbyname("kern.waketime",&wake,&n,NULL,0)!=0)result[@"error"]=@"无法读取 wake time";
        result[@"wake_unix"]=@((double)wake.tv_sec+(double)wake.tv_usec/1000000.0);
        NSData *data=[NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
        if(!data)return NULL;
        char *out=malloc(data.length+1);if(!out)return NULL;
        memcpy(out,data.bytes,data.length);out[data.length]=0;return out;
    }
}

char *sg_bundle(const char *path) {
    @autoreleasepool {
        NSString *p=[NSString stringWithUTF8String:path];
        NSBundle *bundle=[NSBundle bundleWithPath:p];
        return strdup([[bundle bundleIdentifier] UTF8String] ?: "");
    }
}
