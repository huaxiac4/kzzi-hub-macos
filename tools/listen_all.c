#include <stdio.h>
#include <unistd.h>
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hid/IOHIDDevice.h>
#include <IOKit/hid/IOHIDKeys.h>

static int32_t propInt(IOHIDDeviceRef d, CFStringRef k){CFTypeRef v=IOHIDDeviceGetProperty(d,k);int32_t r=-1;if(v&&CFGetTypeID(v)==CFNumberGetTypeID())CFNumberGetValue(v,kCFNumberSInt32Type,&r);return r;}
static void cb(void *ctx, IOReturn res, void *sender, IOHIDReportType type, uint32_t rid, uint8_t *rep, CFIndex len){
    printf("[%s] rid=0x%02x len=%ld:", (const char*)ctx, rid, (long)len);
    for(CFIndex i=0;i<len&&i<32;i++) printf(" %02x", rep[i]);
    printf("\n"); fflush(stdout);
}
int main(int argc,char**argv){
    int secs = argc>1?atoi(argv[1]):20;
    IOHIDManagerRef m=IOHIDManagerCreate(kCFAllocatorDefault,kIOHIDOptionsTypeNone);
    IOHIDManagerSetDeviceMatching(m,NULL);
    IOHIDManagerOpen(m,kIOHIDOptionsTypeNone);
    usleep(400000);
    CFSetRef set=IOHIDManagerCopyDevices(m);
    CFIndex n=set?CFSetGetCount(set):0;
    const void**vals=calloc(n?n:1,sizeof(void*));
    if(n)CFSetGetValues(set,vals);
    int opened=0;
    static uint8_t bufs[8][4096];
    static char names[8][32];
    for(CFIndex i=0;i<n && opened<8;i++){
        IOHIDDeviceRef d=(IOHIDDeviceRef)vals[i];
        if(propInt(d,CFSTR(kIOHIDVendorIDKey))!=0x3554) continue;
        if(propInt(d,CFSTR(kIOHIDProductIDKey))!=0xfa09) continue;
        int up=propInt(d,CFSTR(kIOHIDPrimaryUsagePageKey)), u=propInt(d,CFSTR(kIOHIDPrimaryUsageKey));
        snprintf(names[opened],32,"up=%x u=%x",up,u);
        IOReturn r=IOHIDDeviceOpen(d,kIOHIDOptionsTypeNone);
        printf("open %s -> 0x%x\n",names[opened],r);
        IOHIDDeviceRegisterInputReportCallback(d,bufs[opened],sizeof(bufs[0]),cb,names[opened]);
        IOHIDDeviceScheduleWithRunLoop(d,CFRunLoopGetCurrent(),kCFRunLoopDefaultMode);
        opened++;
    }
    printf("listening %d devices for %ds\n",opened,secs); fflush(stdout);
    for(int i=0;i<secs*100;i++) CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.01,false);
    return 0;
}
