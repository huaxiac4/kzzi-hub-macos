// kzzictl - talk to the KZZI K98 2.4G receiver vendor HID collection
// build: clang -O2 -framework IOKit -framework CoreFoundation -o kzzictl kzzictl.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hid/IOHIDDevice.h>
#include <IOKit/hid/IOHIDKeys.h>

static int g_vid = 0x3554, g_pid = 0xfa09;
static int g_verbose = 0;

static int32_t propInt(IOHIDDeviceRef d, CFStringRef key) {
    CFTypeRef v = IOHIDDeviceGetProperty(d, key);
    int32_t r = -1;
    if (v && CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue(v, kCFNumberSInt32Type, &r);
    return r;
}

static IOHIDDeviceRef findDevice(void) {
    IOHIDManagerRef m = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    IOHIDManagerSetDeviceMatching(m, NULL);
    IOHIDManagerOpen(m, kIOHIDOptionsTypeNone);
    usleep(300000);
    IOHIDDeviceRef found = NULL;
    CFSetRef set = IOHIDManagerCopyDevices(m);
    if (set) {
        CFIndex n = CFSetGetCount(set);
        const void **vals = calloc(n ? n : 1, sizeof(void *));
        CFSetGetValues(set, vals);
        for (CFIndex i = 0; i < n; i++) {
            IOHIDDeviceRef d = (IOHIDDeviceRef)vals[i];
            if (propInt(d, CFSTR(kIOHIDVendorIDKey)) != g_vid) continue;
            if (propInt(d, CFSTR(kIOHIDProductIDKey)) != g_pid) continue;
            if (propInt(d, CFSTR(kIOHIDPrimaryUsagePageKey)) != 0xff02) continue;
            CFRetain(d);
            found = d;
            break;
        }
        free(vals);
        CFRelease(set);
    }
    IOHIDManagerClose(m, kIOHIDOptionsTypeNone);
    CFRelease(m);
    return found;
}

static int parseHexBytes(const char *s, uint8_t *out, int max) {
    int n = 0;
    while (*s && n < max) {
        while (*s == ' ' || *s == ':' || *s == ',' || *s == '-') s++;
        if (!*s) break;
        char *end;
        long v = strtol(s, &end, 16);
        if (end == s) break;
        out[n++] = (uint8_t)v;
        s = end;
    }
    return n;
}

static void hexline(const char *tag, const uint8_t *p, int n) {
    printf("%s", tag);
    for (int i = 0; i < n; i++) printf("%02x ", p[i]);
    printf("\n");
    fflush(stdout);
}

static volatile int g_got = 0;

static void inputCb(void *ctx, IOReturn res, void *sender, IOHIDReportType type, uint32_t rid,
                    uint8_t *report, CFIndex len) {
    (void)ctx; (void)res; (void)sender; (void)type;
    char tag[32];
    snprintf(tag, sizeof(tag), "RX id=%02x: ", rid);
    hexline(tag, report, (int)len);
    g_got++;
}

static void pump(CFRunLoopRef rl, int ms, int stopAfter) {
    int waited = 0;
    while (waited < ms) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
        waited += 10;
        if (stopAfter > 0 && g_got >= stopAfter) break;
    }
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr,
                "usage:\n"
                "  %s send  <hex bytes incl report id> [pause_ms]\n"
                "  %s xfer  <hex bytes incl report id> [wait_ms] [count]\n"
                "  %s recv  [wait_ms]\n"
                "  %s featget <rid> <len>\n"
                "  %s featset <rid> <hex payload>\n"
                "  %s info\n", argv[0], argv[0], argv[0], argv[0], argv[0], argv[0]);
        return 1;
    }
    IOHIDDeviceRef d = findDevice();
    if (!d) { fprintf(stderr, "KZZI vendor interface not found\n"); return 2; }
    IOHIDOptionsType opts = getenv("KZZI_SEIZE") ? kIOHIDOptionsTypeSeizeDevice : kIOHIDOptionsTypeNone;
    IOReturn r = IOHIDDeviceOpen(d, opts);
    if (r != kIOReturnSuccess) { fprintf(stderr, "open failed 0x%x\n", r); return 3; }

    const char *c = argv[1];
    uint8_t buf[4096];
    if (!strcmp(c, "info")) {
        printf("max input=%d output=%d feature=%d\n",
               propInt(d, CFSTR(kIOHIDMaxInputReportSizeKey)),
               propInt(d, CFSTR(kIOHIDMaxOutputReportSizeKey)),
               propInt(d, CFSTR(kIOHIDMaxFeatureReportSizeKey)));
    } else if (!strcmp(c, "send") || !strcmp(c, "xfer")) {
        int n = parseHexBytes(argv[2], buf, sizeof(buf));
        if (n < 1) { fprintf(stderr, "bad hex\n"); return 4; }
        int rid = buf[0];
        int pause = argc > 3 ? atoi(argv[3]) : 300;
        int count = argc > 4 ? atoi(argv[4]) : 0;

        uint8_t inbuf[4096] = {0};
        IOHIDDeviceRegisterInputReportCallback(d, inbuf, sizeof(inbuf), inputCb, NULL);
        IOHIDDeviceScheduleWithRunLoop(d, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        pump(CFRunLoopGetCurrent(), 50, 0);

        hexline("TX: ", buf, n);
        IOReturn sr = IOHIDDeviceSetReport(d, kIOHIDReportTypeOutput, rid, buf + 1, n - 1);
        printf("SetReport -> 0x%x %s\n", sr, sr == kIOReturnSuccess ? "ok" : "FAIL");
        if (pause > 0) pump(CFRunLoopGetCurrent(), pause, count);
        IOHIDDeviceUnscheduleFromRunLoop(d, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    } else if (!strcmp(c, "recv")) {
        int wait = argc > 2 ? atoi(argv[2]) : 1000;
        uint8_t inbuf[4096] = {0};
        IOHIDDeviceRegisterInputReportCallback(d, inbuf, sizeof(inbuf), inputCb, NULL);
        IOHIDDeviceScheduleWithRunLoop(d, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        pump(CFRunLoopGetCurrent(), wait, 0);
        IOHIDDeviceUnscheduleFromRunLoop(d, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    } else if (!strcmp(c, "seq")) {
        int gap = argc > 2 ? atoi(argv[2]) : 300;
        uint8_t inbuf[4096] = {0};
        IOHIDDeviceRegisterInputReportCallback(d, inbuf, sizeof(inbuf), inputCb, NULL);
        IOHIDDeviceScheduleWithRunLoop(d, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        pump(CFRunLoopGetCurrent(), 50, 0);
        for (int a = 3; a < argc; a++) {
            int n = parseHexBytes(argv[a], buf, sizeof(buf));
            if (n < 1) continue;
            int rid = buf[0];
            g_got = 0;
            hexline("TX: ", buf, n);
            IOHIDDeviceSetReport(d, kIOHIDReportTypeOutput, rid, buf, n);
            pump(CFRunLoopGetCurrent(), gap, 0);
        }
        IOHIDDeviceUnscheduleFromRunLoop(d, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    } else if (!strcmp(c, "props")) {
        CFStringRef keys[] = {CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage"), CFSTR("USB Interface Number"),
                              CFSTR("USB Device Number"), CFSTR("LocationID"), CFSTR("Product"), CFSTR("SerialNumber"),
                              CFSTR("Transport"), CFSTR("MaxInputReportSize"), CFSTR("MaxOutputReportSize"),
                              CFSTR("MaxFeatureReportSize"), CFSTR("ReportDescriptor")};
        for (int i = 0; i < 10; i++) {
            CFTypeRef v = IOHIDDeviceGetProperty(d, keys[i]);
            char kb[64]; CFStringGetCString(keys[i], kb, sizeof(kb), kCFStringEncodingUTF8);
            if (!v) { printf("%s = (null)\n", kb); continue; }
            if (CFGetTypeID(v) == CFNumberGetTypeID()) { int32_t x; CFNumberGetValue(v, kCFNumberSInt32Type, &x); printf("%s = %d\n", kb, x); }
            else if (CFGetTypeID(v) == CFStringGetTypeID()) { char vb[256]; CFStringGetCString(v, vb, sizeof(vb), kCFStringEncodingUTF8); printf("%s = %s\n", kb, vb); }
            else printf("%s = <other>\n", kb);
        }
    } else if (!strcmp(c, "raw")) {
        int rid = (int)strtol(argv[2], NULL, 0);
        int n = parseHexBytes(argv[3], buf, sizeof(buf));
        int wait = argc > 4 ? atoi(argv[4]) : 800;
        uint8_t inbuf[4096] = {0};
        IOHIDDeviceRegisterInputReportCallback(d, inbuf, sizeof(inbuf), inputCb, NULL);
        IOHIDDeviceScheduleWithRunLoop(d, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        pump(CFRunLoopGetCurrent(), 50, 0);
        hexline("TXraw: ", buf, n);
        IOReturn sr = IOHIDDeviceSetReport(d, kIOHIDReportTypeOutput, rid, buf, n);
        printf("SetReport(rid=%d,len=%d) -> 0x%x %s\n", rid, n, sr, sr == kIOReturnSuccess ? "ok" : "FAIL");
        if (wait > 0) pump(CFRunLoopGetCurrent(), wait, 0);
        IOHIDDeviceUnscheduleFromRunLoop(d, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    } else if (!strcmp(c, "featget")) {
        int rid = (int)strtol(argv[2], NULL, 0);
        int len = argc > 3 ? atoi(argv[3]) : 7;
        memset(buf, 0, sizeof(buf));
        CFIndex n = len;
        IOReturn gr = IOHIDDeviceGetReport(d, kIOHIDReportTypeFeature, rid, buf, &n);
        printf("GetFeature rid=%d -> 0x%x len=%ld\n", rid, gr, (long)n);
        hexline("  ", buf, (int)n);
    } else if (!strcmp(c, "featset")) {
        int rid = (int)strtol(argv[2], NULL, 0);
        int n = parseHexBytes(argv[3], buf, sizeof(buf));
        IOReturn sr = IOHIDDeviceSetReport(d, kIOHIDReportTypeFeature, rid, buf, n);
        printf("SetFeature rid=%d len=%d -> 0x%x %s\n", rid, n, sr, sr == kIOReturnSuccess ? "ok" : "FAIL");
    } else {
        fprintf(stderr, "unknown command\n");
    }
    IOHIDDeviceClose(d, opts);
    CFRelease(d);
    return 0;
}
