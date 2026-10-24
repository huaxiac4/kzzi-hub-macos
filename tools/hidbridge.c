// hidbridge: stdin/stdout hex bridge to the KZZI dongle vendor HID collection
// commands:  TX <hex 20 bytes incl report id>   -> sends output report
//            RX <ms>                            -> listens for reports for ms
//            OPEN / QUIT
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hid/IOHIDDevice.h>
#include <IOKit/hid/IOHIDKeys.h>

static int32_t pi(IOHIDDeviceRef d, CFStringRef k){CFTypeRef v=IOHIDDeviceGetProperty(d,k);int32_t r=-1;if(v&&CFGetTypeID(v)==CFNumberGetTypeID())CFNumberGetValue(v,kCFNumberSInt32Type,&r);return r;}
static void cb(void*ctx,IOReturn res,void*sender,IOHIDReportType t,uint32_t rid,uint8_t*rep,CFIndex len){
    (void)ctx;(void)res;(void)sender;(void)t;
    printf("RX %02x", rid);
    for(CFIndex i=0;i<len;i++) printf(" %02x", rep[i]);
    printf("\n"); fflush(stdout);
}
static int hexval(char c){ if(c>='0'&&c<='9')return c-'0'; if(c>='a'&&c<='f')return c-'a'+10; if(c>='A'&&c<='F')return c-'A'+10; return -1; }
int main(void){
    IOHIDManagerRef m=IOHIDManagerCreate(NULL,kIOHIDOptionsTypeNone);
    IOHIDManagerSetDeviceMatching(m,NULL);
    IOHIDManagerOpen(m,kIOHIDOptionsTypeNone);
    usleep(400000);
    CFSetRef s=IOHIDManagerCopyDevices(m); CFIndex n=s?CFSetGetCount(s):0;
    const void**v=calloc(n?n:1,sizeof(void*)); if(n)CFSetGetValues(s,v);
    IOHIDDeviceRef dev=NULL;
    for(CFIndex i=0;i<n;i++){IOHIDDeviceRef d=(IOHIDDeviceRef)v[i];
        if(pi(d,CFSTR(kIOHIDVendorIDKey))==0x3554&&pi(d,CFSTR(kIOHIDProductIDKey))==0xfa09&&pi(d,CFSTR(kIOHIDPrimaryUsagePageKey))==0xff02){dev=d;break;}}
    if(!dev){fprintf(stderr,"ERR device not found\n");return 1;}
    if(IOHIDDeviceOpen(dev,kIOHIDOptionsTypeNone)!=kIOReturnSuccess){fprintf(stderr,"ERR open\n");return 1;}
    static uint8_t inbuf[4096];
    IOHIDDeviceRegisterInputReportCallback(dev,inbuf,sizeof inbuf,cb,NULL);
    IOHIDDeviceScheduleWithRunLoop(dev,CFRunLoopGetCurrent(),kCFRunLoopDefaultMode);
    printf("OK\n"); fflush(stdout);
    char line[4096];
    while(fgets(line,sizeof line,stdin)){
        if(!strncmp(line,"TX ",3)){
            uint8_t b[256]; int n=0; char*p=line+3;
            while(*p&&n<256){ while(*p==' '||*p=='\n'||*p=='\r')p++; if(!*p)break;
                int h=hexval(p[0]); if(h<0)break; int l=p[1]?hexval(p[1]):-1; if(l<0)break;
                b[n++]=(uint8_t)(h*16+l); p+=2; }
            if(n>=1){ IOReturn r=IOHIDDeviceSetReport(dev,kIOHIDReportTypeOutput,b[0],b,n);
                printf(r==kIOReturnSuccess?"TXOK\n":"TXERR %x\n", r); fflush(stdout); }
        } else if(!strncmp(line,"RX ",3)){
            int ms=atoi(line+3);
            for(int i=0;i<ms/5;i++) CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.005,false);
            printf("END\n"); fflush(stdout);
        } else if(!strncmp(line,"QUIT",4)) break;
    }
    return 0;
}
