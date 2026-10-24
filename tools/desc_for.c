#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hid/IOHIDDevice.h>
#include <IOKit/hid/IOHIDKeys.h>
static int32_t pi(IOHIDDeviceRef d, CFStringRef k){CFTypeRef v=IOHIDDeviceGetProperty(d,k);int32_t r=-1;if(v&&CFGetTypeID(v)==CFNumberGetTypeID())CFNumberGetValue(v,kCFNumberSInt32Type,&r);return r;}
int main(int argc,char**argv){
    if(argc<4){fprintf(stderr,"usage: %s vid pid usagePage [usage]\n",argv[0]);return 1;}
    int vid=strtol(argv[1],0,0), pid=strtol(argv[2],0,0), up=strtol(argv[3],0,0);
    int u = argc>4?strtol(argv[4],0,0):-1;
    IOHIDManagerRef m=IOHIDManagerCreate(NULL,kIOHIDOptionsTypeNone);
    IOHIDManagerSetDeviceMatching(m,NULL); IOHIDManagerOpen(m,kIOHIDOptionsTypeNone); usleep(300000);
    CFSetRef s=IOHIDManagerCopyDevices(m); CFIndex n=s?CFSetGetCount(s):0;
    const void**v=calloc(n?n:1,sizeof(void*)); if(n)CFSetGetValues(s,v);
    for(CFIndex i=0;i<n;i++){IOHIDDeviceRef d=(IOHIDDeviceRef)v[i];
        if(pi(d,CFSTR(kIOHIDVendorIDKey))!=vid||pi(d,CFSTR(kIOHIDProductIDKey))!=pid) continue;
        if(pi(d,CFSTR(kIOHIDPrimaryUsagePageKey))!=up) continue;
        if(u>=0 && pi(d,CFSTR(kIOHIDPrimaryUsageKey))!=u) continue;
        CFTypeRef rd=IOHIDDeviceGetProperty(d,CFSTR(kIOHIDReportDescriptorKey));
        if(!rd) continue;
        CFDataRef dd=(CFDataRef)rd; const uint8_t*p=CFDataGetBytePtr(dd); CFIndex len=CFDataGetLength(dd);
        printf("descriptor len=%ld  maxIn=%d maxOut=%d maxFeat=%d\n",(long)len,
            pi(d,CFSTR(kIOHIDMaxInputReportSizeKey)),pi(d,CFSTR(kIOHIDMaxOutputReportSizeKey)),pi(d,CFSTR(kIOHIDMaxFeatureReportSizeKey)));
        for(CFIndex j=0;j<len;j++){ if(j%16==0)printf("\n%04lx: ",(long)j); printf("%02x ",p[j]); }
        printf("\n");
        return 0;
    }
    printf("not found\n"); return 2;
}
