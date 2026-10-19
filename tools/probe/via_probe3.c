#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hid/IOHIDKeys.h>
#include <CoreFoundation/CoreFoundation.h>

static int gotResponse = 0;
static int matchedCmd = -1;
static int pendingCmd = -1;
static double sendTime = 0;

static double nowSec(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}
static void input_cb(void *ctx, IOReturn result, void *sender, IOHIDReportType type,
                     uint32_t reportID, uint8_t *report, CFIndex reportLength) {
    double dt = nowSec() - sendTime;
    printf("<<< IN t=%.3fs:", dt);
    for (CFIndex i = 0; i < reportLength; i++) printf(" %02X", report[i]);
    printf("\n"); fflush(stdout);
    gotResponse = 1;
    if (pendingCmd >= 0 && reportLength > 1 && (report[0] == (uint8_t)pendingCmd || report[1] == (uint8_t)pendingCmd)) matchedCmd = 1;
    CFRunLoopStop(CFRunLoopGetCurrent());
}
static long propLong(IOHIDDeviceRef d, CFStringRef key) {
    CFTypeRef v = IOHIDDeviceGetProperty(d, key);
    if (!v || CFGetTypeID(v) != CFNumberGetTypeID()) return -1;
    long out = -1; CFNumberGetValue((CFNumberRef)v, kCFNumberLongType, &out); return out;
}
static void drainStale(void) {
    for (int i = 0; i < 8; i++) {
        gotResponse = 0;
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.03, false);
        if (!gotResponse) return;
        printf("    (stale drained)\n");
    }
}
static void sendRaw(IOHIDDeviceRef dev, const uint8_t *payload, size_t plen, const char *label) {
    uint8_t buf[32]; memset(buf, 0, sizeof(buf));
    for (size_t i = 0; i < plen && i < sizeof(buf); i++) buf[i] = payload[i];
    drainStale();
    printf(">>> %-42s |", label);
    for (int i = 0; i < 10; i++) printf(" %02X", buf[i]);
    printf("\n"); fflush(stdout);
    pendingCmd = buf[0]; matchedCmd = 0; gotResponse = 0; sendTime = nowSec();
    IOReturn res = IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 0, buf, sizeof(buf));
    if (res != kIOReturnSuccess) { printf("    SetReport FAILED 0x%08X\n", res); return; }
    for (int i = 0; i < 12 && !matchedCmd; i++) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.15, false);
    if (!matchedCmd) printf("    (no matching response)\n");
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    const void *keys[2] = { CFSTR(kIOHIDVendorIDKey), CFSTR(kIOHIDProductIDKey) };
    int vid = 0x320F, pid = 0x5055;
    CFNumberRef vidN = CFNumberCreate(NULL, kCFNumberIntType, &vid);
    CFNumberRef pidN = CFNumberCreate(NULL, kCFNumberIntType, &pid);
    const void *vals[2] = { vidN, pidN };
    CFDictionaryRef match = CFDictionaryCreate(NULL, keys, vals, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    IOHIDManagerSetDeviceMatching(manager, match);
    IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone);
    CFSetRef devSet = IOHIDManagerCopyDevices(manager);
    CFIndex n = CFSetGetCount(devSet);
    IOHIDDeviceRef *arr = calloc(n, sizeof(IOHIDDeviceRef));
    CFSetGetValues(devSet, (const void **)arr);
    IOHIDDeviceRef raw = NULL;
    for (CFIndex i = 0; i < n; i++) {
        long page = propLong(arr[i], CFSTR(kIOHIDPrimaryUsagePageKey));
        long usage = propLong(arr[i], CFSTR(kIOHIDPrimaryUsageKey));
        if (page == 0xFF60 && usage == 0x61) raw = arr[i];
    }
    if (!raw) { printf("RAW NOT FOUND\n"); return 3; }
    IOReturn ores = IOHIDDeviceOpen(raw, kIOHIDOptionsTypeNone);
    printf("open -> 0x%08X\n", ores);
    if (ores != kIOReturnSuccess) return 4;
    uint8_t inBuf[64];
    IOHIDDeviceRegisterInputReportCallback(raw, inBuf, sizeof(inBuf), input_cb, NULL);
    IOHIDDeviceScheduleWithRunLoop(raw, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

    printf("\n=== A. framing experiment ===\n");
    uint8_t a1[] = { 0x01 };
    uint8_t a2[] = { 0x00, 0x01 };
    uint8_t a3[] = { 0x01, 0x00 };
    uint8_t a4[] = { 0x00, 0x00, 0x01 };
    sendRaw(raw, a1, sizeof(a1), "A1 [01]");
    sendRaw(raw, a2, sizeof(a2), "A2 [00 01]");
    sendRaw(raw, a3, sizeof(a3), "A3 [01 00]");
    sendRaw(raw, a4, sizeof(a4), "A4 [00 00 01]");

    printf("\n=== B. keyboard values ===\n");
    for (int v = 1; v <= 6; v++) {
        uint8_t p[] = { 0x02, (uint8_t)v };
        char lbl[64]; snprintf(lbl, sizeof(lbl), "B get_kv(%d)", v);
        sendRaw(raw, p, sizeof(p), lbl);
    }

    printf("\n=== C. get_keycode ===\n");
    int coords[][3] = {{0,0,0},{0,0,1},{0,1,1},{1,0,0},{3,7,15},{0,5,5},{0,6,14}};
    for (unsigned i = 0; i < sizeof(coords)/sizeof(coords[0]); i++) {
        uint8_t p[] = { 0x04, (uint8_t)coords[i][0], (uint8_t)coords[i][1], (uint8_t)coords[i][2] };
        char lbl[64]; snprintf(lbl, sizeof(lbl), "C get_keycode(%d,%d,%d)", coords[i][0], coords[i][1], coords[i][2]);
        sendRaw(raw, p, sizeof(p), lbl);
    }

    printf("\n=== D. keymap get_buffer (offset,size) ===\n");
    uint8_t d1[] = { 0x12, 0x00, 0x00, 0x04 };
    sendRaw(raw, d1, sizeof(d1), "D1 buffer(0,4)");
    uint8_t d2[] = { 0x12, 0x00, 0x00, 0x1C };
    sendRaw(raw, d2, sizeof(d2), "D2 buffer(0,28)");
    uint8_t d3[] = { 0x12, 0x00, 0x04, 0x04 };
    sendRaw(raw, d3, sizeof(d3), "D3 buffer(offset=4,4)");

    printf("\n=== E. custom lighting ch3 values 1..4 ===\n");
    for (int v = 1; v <= 4; v++) {
        uint8_t p[] = { 0x08, 0x03, (uint8_t)v, 0x00 };
        char lbl[64]; snprintf(lbl, sizeof(lbl), "E custom_get(ch3,%d)", v);
        sendRaw(raw, p, sizeof(p), lbl);
    }

    printf("\n=== F. macros ===\n");
    uint8_t f1[] = { 0x0C }; sendRaw(raw, f1, sizeof(f1), "F1 macro count");
    uint8_t f2[] = { 0x0D }; sendRaw(raw, f2, sizeof(f2), "F2 macro buffer size");
    uint8_t f3[] = { 0x0E, 0x00, 0x00, 0x08 }; sendRaw(raw, f3, sizeof(f3), "F3 macro buffer(0,8)");

    printf("\n=== G. unknown / misc ===\n");
    uint8_t g1[] = { 0x7E }; sendRaw(raw, g1, sizeof(g1), "G1 cmd 0x7E");
    uint8_t g2[] = { 0x02, 0x03 }; sendRaw(raw, g2, sizeof(g2), "G2 switch matrix state");
    uint8_t g3[] = { 0x02, 0x02 }; sendRaw(raw, g3, sizeof(g3), "G3 layout options");
    uint8_t g4[] = { 0x02, 0x05 }; sendRaw(raw, g4, sizeof(g4), "G4 device indication");
    uint8_t g5[] = { 0x02, 0x06 }; sendRaw(raw, g5, sizeof(g5), "G5 keycodes version");

    printf("\n=== H. version repeat ===\n");
    uint8_t h1[] = { 0x01 }; sendRaw(raw, h1, sizeof(h1), "H version #1");
    sendRaw(raw, h1, sizeof(h1), "H version #2");
    sendRaw(raw, h1, sizeof(h1), "H version #3");

    IOHIDDeviceUnscheduleFromRunLoop(raw, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    IOHIDDeviceClose(raw, kIOHIDOptionsTypeNone);
    printf("done\n");
    return 0;
}
