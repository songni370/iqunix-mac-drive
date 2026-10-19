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
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

static void input_cb(void *ctx, IOReturn result, void *sender, IOHIDReportType type,
                     uint32_t reportID, uint8_t *report, CFIndex reportLength) {
    double dt = nowSec() - sendTime;
    printf("<<< IN reportID=%u len=%ld t=%.3fs:", reportID, (long)reportLength, dt);
    for (CFIndex i = 0; i < reportLength; i++) printf(" %02X", report[i]);
    printf("\n");
    fflush(stdout);
    gotResponse = 1;
    if (pendingCmd >= 0 && reportLength > 0 && report[0] == (uint8_t)pendingCmd) matchedCmd = 1;
    CFRunLoopStop(CFRunLoopGetCurrent());
}

static long propLong(IOHIDDeviceRef d, CFStringRef key) {
    CFTypeRef v = IOHIDDeviceGetProperty(d, key);
    if (!v || CFGetTypeID(v) != CFNumberGetTypeID()) return -1;
    long out = -1;
    CFNumberGetValue((CFNumberRef)v, kCFNumberLongType, &out);
    return out;
}

static void drainStale(void) {
    for (int i = 0; i < 6; i++) {
        gotResponse = 0;
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.03, false);
        if (!gotResponse) return;
        printf("    (stale response drained)\n");
    }
}

static void sendCmd(IOHIDDeviceRef dev, const uint8_t *payload, size_t plen, const char *label) {
    uint8_t buf[32];
    memset(buf, 0, sizeof(buf));
    for (size_t i = 0; i < plen && i < sizeof(buf); i++) buf[i] = payload[i];
    drainStale();
    printf(">>> %-36s |", label);
    for (int i = 0; i < 8; i++) printf(" %02X", buf[i]);
    printf(" ...\n");
    fflush(stdout);
    pendingCmd = buf[0];
    matchedCmd = 0;
    gotResponse = 0;
    sendTime = nowSec();
    IOReturn res = IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 0, buf, sizeof(buf));
    if (res != kIOReturnSuccess) { printf("    SetReport FAILED 0x%08X\n", res); return; }
    for (int i = 0; i < 8 && !matchedCmd; i++) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.25, false);
    }
    if (!matchedCmd) printf("    (no matching response within 2s)\n");
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    const void *keys[2] = { CFSTR(kIOHIDVendorIDKey), CFSTR(kIOHIDProductIDKey) };
    int vid = 0x320F, pid = 0x5055;
    CFNumberRef vidN = CFNumberCreate(NULL, kCFNumberIntType, &vid);
    CFNumberRef pidN = CFNumberCreate(NULL, kCFNumberIntType, &pid);
    const void *vals[2] = { vidN, pidN };
    CFDictionaryRef match = CFDictionaryCreate(NULL, keys, vals, 2,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    IOHIDManagerSetDeviceMatching(manager, match);
    IOReturn mres = IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone);
    printf("IOHIDManagerOpen -> 0x%08X\n", mres);

    CFSetRef devSet = IOHIDManagerCopyDevices(manager);
    if (!devSet) { printf("NO DEVICES\n"); return 2; }
    CFIndex n = CFSetGetCount(devSet);
    IOHIDDeviceRef *arr = calloc(n, sizeof(IOHIDDeviceRef));
    CFSetGetValues(devSet, (const void **)arr);
    IOHIDDeviceRef raw = NULL;
    for (CFIndex i = 0; i < n; i++) {
        IOHIDDeviceRef d = arr[i];
        long page = propLong(d, CFSTR(kIOHIDPrimaryUsagePageKey));
        long usage = propLong(d, CFSTR(kIOHIDPrimaryUsageKey));
        printf("IFACE page=0x%04lX usage=0x%02lX\n", page, usage);
        if (page == 0xFF60 && usage == 0x61) raw = d;
    }
    if (!raw) { printf("RAW HID NOT FOUND\n"); return 3; }
    IOReturn ores = IOHIDDeviceOpen(raw, kIOHIDOptionsTypeNone);
    printf("IOHIDDeviceOpen(rawHID) -> 0x%08X\n", ores);
    if (ores != kIOReturnSuccess) { printf("CANNOT OPEN\n"); return 4; }

    uint8_t inBuf[64];
    IOHIDDeviceRegisterInputReportCallback(raw, inBuf, sizeof(inBuf), input_cb, NULL);
    IOHIDDeviceScheduleWithRunLoop(raw, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

    printf("--- VIA GET-ONLY probe (no EEPROM writes) ---\n");
    uint8_t c1[]  = { 0x01 };                                  // protocol version
    uint8_t c2[]  = { 0x02, 0x01 };                            // keyboard value: uptime
    uint8_t c3[]  = { 0x02, 0x02 };                            // layout options
    uint8_t c4[]  = { 0x02, 0x04 };                            // firmware version
    uint8_t c5[]  = { 0x11 };                                  // layer count
    uint8_t c6[]  = { 0x04, 0x00, 0x00, 0x00 };                // get keycode L0 R0 C0
    uint8_t c7[]  = { 0x0C };                                  // macro count
    uint8_t c8[]  = { 0x0D };                                  // macro buffer size
    uint8_t c9[]  = { 0x12, 0x00, 0x00, 0x00, 0x04 };          // keymap get buffer L0 off0 size4
    uint8_t c10[] = { 0x08, 0x01, 0x01, 0x00 };                // custom get ch1(begin?) val1
    uint8_t c11[] = { 0x08, 0x02, 0x01, 0x00 };                // custom get ch2 val1
    uint8_t c12[] = { 0x08, 0x03, 0x01, 0x00 };                // custom get ch3 val1
    uint8_t c13[] = { 0x08, 0x00, 0x01, 0x00 };                // custom get ch0 val1
    sendCmd(raw, c1, sizeof(c1),  "get_protocol_version");
    sendCmd(raw, c2, sizeof(c2),  "get_keyboard_value(uptime)");
    sendCmd(raw, c3, sizeof(c3),  "get_keyboard_value(layout_options)");
    sendCmd(raw, c4, sizeof(c4),  "get_keyboard_value(fw_version)");
    sendCmd(raw, c5, sizeof(c5),  "dynamic_keymap_get_layer_count");
    sendCmd(raw, c6, sizeof(c6),  "get_keycode(L0,R0,C0)");
    sendCmd(raw, c7, sizeof(c7),  "macro_get_count");
    sendCmd(raw, c8, sizeof(c8),  "macro_get_buffer_size");
    sendCmd(raw, c9, sizeof(c9),  "keymap_get_buffer(L0,0,4)");
    sendCmd(raw, c10, sizeof(c10), "custom_get(ch1,val1)");
    sendCmd(raw, c11, sizeof(c11), "custom_get(ch2,val1)");
    sendCmd(raw, c12, sizeof(c12), "custom_get(ch3,val1)");
    sendCmd(raw, c13, sizeof(c13), "custom_get(ch0,val1)");

    IOHIDDeviceUnscheduleFromRunLoop(raw, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    IOHIDDeviceClose(raw, kIOHIDOptionsTypeNone);
    free(arr);
    printf("done\n");
    return 0;
}
