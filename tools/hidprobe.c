// hidprobe - minimal IOHID probe/poke tool for the KZZI K98 2.4G receiver
// build: clang -O2 -framework IOKit -framework CoreFoundation -o hidprobe hidprobe.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hid/IOHIDDevice.h>
#include <IOKit/hid/IOHIDKeys.h>

static int g_vid = 0x3554, g_pid = 0xfa09;

static void hexdump(const uint8_t *p, size_t n) {
    for (size_t i = 0; i < n; i++) {
        if (i % 16 == 0) printf("%04zx: ", i);
        printf("%02x ", p[i]);
        if (i % 16 == 15) printf("\n");
    }
    if (n % 16) printf("\n");
}

static int32_t propInt(IOHIDDeviceRef d, CFStringRef key) {
    CFTypeRef v = IOHIDDeviceGetProperty(d, key);
    int32_t r = -1;
    if (v && CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue(v, kCFNumberSInt32Type, &r);
    return r;
}

static IOHIDDeviceRef pickDevice(IOHIDManagerRef m, int usagePage, int usage, int quiet) {
    CFSetRef set = IOHIDManagerCopyDevices(m);
    if (!set) return NULL;
    IOHIDDeviceRef best = NULL;
    CFIndex n = CFSetGetCount(set);
    const void **vals = calloc(n ? n : 1, sizeof(void *));
    CFSetGetValues(set, vals);
    for (CFIndex i = 0; i < n; i++) {
        IOHIDDeviceRef d = (IOHIDDeviceRef)vals[i];
        int32_t vid = propInt(d, CFSTR(kIOHIDVendorIDKey));
        int32_t pid = propInt(d, CFSTR(kIOHIDProductIDKey));
        int32_t up = propInt(d, CFSTR(kIOHIDPrimaryUsagePageKey));
        int32_t u = propInt(d, CFSTR(kIOHIDPrimaryUsageKey));
        if (vid != g_vid || pid != g_pid) continue;
        if (usagePage >= 0 && up != usagePage) continue;
        if (usage >= 0 && u != usage) continue;
        best = d;
        if (up == usagePage && u == usage) break;
    }
    free(vals);
    CFRelease(set);
    return best;
}

static void cmdList(IOHIDManagerRef m) {
    CFSetRef set = IOHIDManagerCopyDevices(m);
    CFIndex n = set ? CFSetGetCount(set) : 0;
    const void **vals = calloc(n ? n : 1, sizeof(void *));
    if (n) CFSetGetValues(set, vals);
    printf("devices: %ld\n", (long)n);
    for (CFIndex i = 0; i < n; i++) {
        IOHIDDeviceRef d = (IOHIDDeviceRef)vals[i];
        int32_t vid = propInt(d, CFSTR(kIOHIDVendorIDKey));
        int32_t pid = propInt(d, CFSTR(kIOHIDProductIDKey));
        int32_t up = propInt(d, CFSTR(kIOHIDPrimaryUsagePageKey));
        int32_t u = propInt(d, CFSTR(kIOHIDPrimaryUsageKey));
        int32_t mf = propInt(d, CFSTR(kIOHIDMaxFeatureReportSizeKey));
        int32_t mo = propInt(d, CFSTR(kIOHIDMaxOutputReportSizeKey));
        int32_t mi = propInt(d, CFSTR(kIOHIDMaxInputReportSizeKey));
        CFTypeRef prod = IOHIDDeviceGetProperty(d, CFSTR(kIOHIDProductKey));
        char pbuf[256] = "";
        if (prod && CFGetTypeID(prod) == CFStringGetTypeID())
            CFStringGetCString(prod, pbuf, sizeof(pbuf), kCFStringEncodingUTF8);
        printf("  %04x:%04x usagePage=0x%x usage=0x%x in=%d out=%d feat=%d  %s%s\n",
               vid, pid, up, u, mi, mo, mf, pbuf,
               (vid == g_vid && pid == g_pid) ? "  <== KZZI" : "");
    }
    free(vals);
    if (set) CFRelease(set);
}

static void cmdDesc(IOHIDManagerRef m) {
    IOHIDDeviceRef d = pickDevice(m, 0xff02, 2, 0);
    if (!d) d = pickDevice(m, -1, -1, 0);
    if (!d) { fprintf(stderr, "device not found\n"); return; }
    CFTypeRef rd = IOHIDDeviceGetProperty(d, CFSTR(kIOHIDReportDescriptorKey));
    if (!rd || CFGetTypeID(rd) != CFDataGetTypeID()) { fprintf(stderr, "no descriptor\n"); return; }
    CFDataRef data = (CFDataRef)rd;
    printf("report descriptor (%ld bytes):\n", (long)CFDataGetLength(data));
    hexdump(CFDataGetBytePtr(data), CFDataGetLength(data));
}

static int openDev(IOHIDManagerRef m, IOHIDDeviceRef *out, int up, int u) {
    IOHIDDeviceRef d = pickDevice(m, up, u, 1);
    if (!d) { fprintf(stderr, "device not found (usagePage=%d usage=%d)\n", up, u); return 0; }
    IOReturn r = IOHIDDeviceOpen(d, kIOHIDOptionsTypeNone);
    if (r != kIOReturnSuccess) { fprintf(stderr, "open failed: 0x%x\n", r); return 0; }
    *out = d;
    return 1;
}

static void cmdGet(IOHIDManagerRef m, int up, int u, int rid, int len) {
    IOHIDDeviceRef d;
    if (!openDev(m, &d, up, u)) return;
    uint8_t *buf = calloc(1, len + 1);
    CFIndex n = len;
    // Note: for feature reports IOHIDDeviceGetReport takes reportID separately,
    // buf excludes the report ID byte.
    IOReturn r = IOHIDDeviceGetReport(d, kIOHIDReportTypeFeature, rid, buf, &n);
    if (r != kIOReturnSuccess) { fprintf(stderr, "getReport failed 0x%x\n", r); }
    else { printf("reportID 0x%02x len %ld:\n", rid, (long)n); hexdump(buf, n); }
    free(buf);
    IOHIDDeviceClose(d, kIOHIDOptionsTypeNone);
}

static int parseHex(const char *s, uint8_t *out, int max) {
    int n = 0;
    while (*s && n < max) {
        while (*s == ' ' || *s == ':' || *s == ',') s++;
        if (!*s) break;
        char *end;
        long v = strtol(s, &end, 16);
        if (end == s) break;
        out[n++] = (uint8_t)v;
        s = end;
    }
    return n;
}

static void cmdSet(IOHIDManagerRef m, int up, int u, int rid, const char *hex, int isOutput) {
    IOHIDDeviceRef d;
    if (!openDev(m, &d, up, u)) return;
    uint8_t *buf = calloc(1, 4096);
    int n = parseHex(hex, buf, 4096);
    IOReturn r = IOHIDDeviceSetReport(d, isOutput ? kIOHIDReportTypeOutput : kIOHIDReportTypeFeature, rid, buf, n);
    printf("setReport(%s) rid=0x%02x len=%d -> 0x%x %s\n", isOutput ? "output" : "feature", rid, n, r,
           r == kIOReturnSuccess ? "ok" : "FAIL");
    free(buf);
    IOHIDDeviceClose(d, kIOHIDOptionsTypeNone);
}

// read input reports for `secs` seconds on the vendor interface
static void inputCb(void *ctx, IOReturn res, void *sender, IOHIDReportType type, uint32_t rid,
                    uint8_t *report, CFIndex len) {
    printf("IN rid=0x%02x len=%ld: ", rid, (long)len);
    for (CFIndex i = 0; i < len && i < 64; i++) printf("%02x ", report[i]);
    printf("\n");
    fflush(stdout);
}

static void cmdRead(IOHIDManagerRef m, int up, int u, int secs) {
    IOHIDDeviceRef d;
    if (!openDev(m, &d, up, u)) return;
    uint8_t buf[4096] = {0};
    IOHIDDeviceRegisterInputReportCallback(d, buf, sizeof(buf), inputCb, NULL);
    IOHIDDeviceScheduleWithRunLoop(d, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    printf("listening %d s ...\n", secs);
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, secs, false);
    IOHIDDeviceUnscheduleFromRunLoop(d, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    IOHIDDeviceClose(d, kIOHIDOptionsTypeNone);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s list|desc|get|set|out|read [args]\n", argv[0]);
        return 1;
    }
    IOHIDManagerRef m = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    IOHIDManagerSetDeviceMatching(m, NULL);
    IOReturn r = IOHIDManagerOpen(m, kIOHIDOptionsTypeNone);
    if (r != kIOReturnSuccess) fprintf(stderr, "manager open 0x%x (continuing)\n", r);
    usleep(300000);
    const char *c = argv[1];
    if (!strcmp(c, "list")) cmdList(m);
    else if (!strcmp(c, "desc")) cmdDesc(m);
    else if (!strcmp(c, "get") && argc >= 5) cmdGet(m, atoi(argv[2]), atoi(argv[3]), (int)strtol(argv[4], NULL, 0), argc >= 6 ? atoi(argv[5]) : 64);
    else if (!strcmp(c, "set") && argc >= 5) cmdSet(m, atoi(argv[2]), atoi(argv[3]), (int)strtol(argv[4], NULL, 0), argv[5], 0);
    else if (!strcmp(c, "out") && argc >= 5) cmdSet(m, atoi(argv[2]), atoi(argv[3]), (int)strtol(argv[4], NULL, 0), argv[5], 1);
    else if (!strcmp(c, "read") && argc >= 5) cmdRead(m, atoi(argv[2]), atoi(argv[3]), atoi(argv[4]));
    else { fprintf(stderr, "bad args\n"); return 1; }
    IOHIDManagerClose(m, kIOHIDOptionsTypeNone);
    return 0;
}
