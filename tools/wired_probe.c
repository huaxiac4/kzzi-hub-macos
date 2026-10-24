#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hid/IOHIDDevice.h>
#include <IOKit/hid/IOHIDKeys.h>
static int32_t pi(IOHIDDeviceRef d, CFStringRef k){CFTypeRef v=IOHIDDeviceGetProperty(d,k);int32_t r=-1;if(v&&CFGetTypeID(v)==CFNumberGetTypeID())CFNumberGetValue(v,kCFNumberSInt32Type,&r);return r;}
int main(int argc,char**argv){
    IOHIDManagerRef m=IOHIDManagerCreate(NULL,kIOHIDOptionsTypeNone);
    IOHIDManagerSetDeviceMatching(m,NULL); IOHIDManagerOpen(m,kIOHIDOptionsTypeNone); usleep(300000);
    CFSetRef s=IOHIDManagerCopyDevices(m); CFIndex n=s?CFSetGetCount(s):0;
    const void**v=calloc(n?n:1,sizeof(void*)); if(n)CFSetGetValues(s,v);
    IOHIDDeviceRef dev=NULL;
    for(CFIndex i=0;i<n;i++){IOHIDDeviceRef d=(IOHIDDeviceRef)v[i];
        if(pi(d,CFSTR(kIOHIDVendorIDKey))==0x258a && pi(d,CFSTR(kIOHIDProductIDKey))==0x195 && pi(d,CFSTR(kIOHIDPrimaryUsagePageKey))==1 && pi(d,CFSTR(kIOHIDPrimaryUsageKey))==0x80){dev=d;break;}}
    if(!dev){printf("wired vendor collection not found\n");return 1;}
    printf("open -> 0x%x\n", IOHIDDeviceOpen(dev,kIOHIDOptionsTypeNone));
    for(int rid=0; rid<9; rid++){
        uint8_t buf[600]; memset(buf,0,sizeof buf); CFIndex len=520;
        IOReturn r=IOHIDDeviceGetReport(dev,kIOHIDReportTypeFeature,rid,buf,&len);
        printf("GetFeature rid=%d -> 0x%x len=%ld:",rid,r,(long)len);
        for(int i=0;i<len&&i<24;i++) printf(" %02x",buf[i]);
        printf("\n");
    }
    return 0;
}
