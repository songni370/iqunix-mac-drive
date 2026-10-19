#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hid/IOHIDKeys.h>
#include <CoreFoundation/CoreFoundation.h>

static int gotResponse = 0;

static void input_cb(void *ctx, IOReturn result, void *sender, IOHIDReportType type,
                     uint32_t reportID, uint8_t *report, CFIndex reportLength) {
    printf("<<< IN reportID=%u len=%ld:", reportID, (long)reportLength);
    for (CFIndex i = 0; i < reportLength; i++) printf(" %02X", report[i]);
    printf("\n");
    fflush(stdout);
    gotResponse = 1;
    CFRunLoopStop(CFRunLoopGetCurrent());
}

static long propLong(IOHIDDeviceRef d, CFStringRef key) {
    CFTypeRef v = IOHIDDeviceGetProperty(d, key);
    if (!v || CFGetTypeID(v) != CFNumberGetTypeID()) return -1;
    long out = -1;
    CFNumberGetValue((CFNumberRef)v, kCFNumberLongType, &out);
    return out;
}

static void printDescriptor(IOHIDDeviceRef d) {
    CFTypeRef v = IOHIDDeviceGetProperty(d, CFSTR(kIOHIDReportDescriptorKey));
    if (!v || CFGetTypeID(v) != CFDataGetTypeID()) { printf("  (no report descriptor)\n"); return; }
    CFDataRef data = (CFDataRef)v;
    const UInt8 *p = CFDataGetBytePtr(data);
    CFIndex n = CFDataGetLength(data);
    printf("  reportDescriptor(%ld):", (long)n);
    for (CFIndex i = 0; i < n; i++) printf(" %02X", p[i]);
    printf("\n");
}

static IOReturn sendReport(IOHIDDeviceRef dev, const uint8_t *payload, size_t plen, const char *label) {
    uint8_t buf[32];
    memset(buf, 0, sizeof(buf));
    for (size_t i = 0; i < plen && i < sizeof(buf); i++) buf[i] = payload[i];
    IOReturn res = IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 0, buf, sizeof(buf));
    printf(">>> %-34s SetReport=0x%08X |", label, res);
    for (int i = 0; i < 32; i++) printf(" %02X", buf[i]);
    printf("\n");
    fflush(stdout);
    if (res != kIOReturnSuccess) return res;
    gotResponse = 0;
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.6, false);
    if (!gotResponse) printf("    (no response within 600ms)\n");
    return res;
}

int main(void) {
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
    fflush(stdout);

    CFSetRef devSet = IOHIDManagerCopyDevices(manager);
    if (!devSet) { printf("NO DEVICES\n"); return 2; }
    CFIndex n = CFSetGetCount(devSet);
    printf("matched devices: %ld\n", (long)n);
    IOHIDDeviceRef *arr = calloc(n, sizeof(IOHIDDeviceRef));
    CFSetGetValues(devSet, (const void **)arr);
    IOHIDDeviceRef raw = NULL;

    for (CFIndex i = 0; i < n; i++) {
        IOHIDDeviceRef d = arr[i];
        long page = propLong(d, CFSTR(kIOHIDPrimaryUsagePageKey));
        long usage = propLong(d, CFSTR(kIOHIDPrimaryUsageKey));
        long maxIn = propLong(d, CFSTR(kIOHIDMaxInputReportSizeKey));
        long maxOut = propLong(d, CFSTR(kIOHIDMaxOutputReportSizeKey));
        long maxFeat = propLong(d, CFSTR(kIOHIDMaxFeatureReportSizeKey));
        long loc = propLong(d, CFSTR(kIOHIDLocationIDKey));
        printf("IFACE page=0x%04lX usage=0x%02lX in=%ld out=%ld feat=%ld loc=0x%lX\n",
               page, usage, maxIn, maxOut, maxFeat, loc);
        if (page == 0xFF60 && usage == 0x61) raw = d;
        printDescriptor(d);
    }
    fflush(stdout);

    if (!raw) { printf("RAW HID 0xFF60/0x61 NOT FOUND\n"); return 3; }

    IOReturn ores = IOHIDDeviceOpen(raw, kIOHIDOptionsTypeNone);
    printf("IOHIDDeviceOpen(rawHID) -> 0x%08X\n", ores);
    if (ores != kIOReturnSuccess) { printf("CANNOT OPEN (TCC / sandbox / busy)\n"); return 4; }

    uint8_t inBuf[64];
    IOHIDDeviceRegisterInputReportCallback(raw, inBuf, sizeof(inBuf), input_cb, NULL);
    IOHIDDeviceScheduleWithRunLoop(raw, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

    printf("--- VIA protocol probe ---\n");
    uint8_t c1[] = { 0x01, 0x00 };                                  // get_protocol_version
    sendReport(raw, c1, sizeof(c1), "get_protocol_version");
    uint8_t c2[] = { 0x02, 0x01 };                                  // get_keyboard_value(uptime)
    sendReport(raw, c2, sizeof(c2), "get_keyboard_value(uptime)");
    uint8_t c3[] = { 0x11, 0x00 };                                  // get layer count
    sendReport(raw, c3, sizeof(c3), "dynamic_keymap_get_layer_count");
    uint8_t c4[] = { 0x04, 0x00, 0x00, 0x00, 0x00 };                // get keycode layer0 row0 col0
    sendReport(raw, c4, sizeof(c4), "dynamic_keymap_get_keycode(0,0,0)");
    uint8_t c5[] = { 0x02, 0x10 };                                  // keyboard value 0x10 (dynamic definition size?)
    sendReport(raw, c5, sizeof(c5), "get_keyboard_value(0x10)");
    uint8_t c6[] = { 0x02, 0x11 };
    sendReport(raw, c6, sizeof(c6), "get_keyboard_value(0x11)");

    IOHIDDeviceUnscheduleFromRunLoop(raw, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    IOHIDDeviceClose(raw, kIOHIDOptionsTypeNone);
    free(arr);
    printf("done\n");
    return 0;
}
