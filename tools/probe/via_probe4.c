#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hid/IOHIDKeys.h>
#include <CoreFoundation/CoreFoundation.h>

#define ROWS 8
#define COLS 16
#define LAYERS 4
#define LAYER_BYTES (ROWS * COLS * 2)

typedef struct { uint8_t buf[32]; int len; int got; double dt; } Resp;
static Resp resp;
static double sendTime = 0;

static double nowSec(void){struct timespec ts;clock_gettime(CLOCK_MONOTONIC,&ts);return ts.tv_sec+ts.tv_nsec/1e9;}
static void input_cb(void *ctx, IOReturn result, void *sender, IOHIDReportType type,
                     uint32_t reportID, uint8_t *report, CFIndex reportLength){
    if (reportLength > (CFIndex)sizeof(resp.buf)) reportLength = sizeof(resp.buf);
    memcpy(resp.buf, report, reportLength);
    resp.len = (int)reportLength;
    resp.dt = nowSec() - sendTime;
    resp.got = 1;
    CFRunLoopStop(CFRunLoopGetCurrent());
}
static void drain(void){
    for (int i=0;i<10;i++){ resp.got=0; CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.02,false); if(!resp.got) return; printf("    (drain: %02X...)\n", resp.buf[0]); }
}
static int cmd(IOHIDDeviceRef dev, const uint8_t *payload, int plen, const char *label){
    uint8_t buf[32]; memset(buf,0,32);
    for (int i=0;i<plen && i<32;i++) buf[i]=payload[i];
    drain();
    resp.got=0; resp.len=0; sendTime=nowSec();
    IOReturn res = IOHIDDeviceSetReport(dev,kIOHIDReportTypeOutput,0,buf,32);
    if (res!=kIOReturnSuccess){printf("%-34s SetReport=0x%08X\n",label,res);return 0;}
    for (int i=0;i<10 && !resp.got;i++) CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.15,false);
    if (resp.got){
        printf("%-34s ->",label);
        for (int i=0;i<12 && i<resp.len;i++) printf(" %02X",resp.buf[i]);
        printf("  (t=%.3fs, len=%d)\n",resp.dt,resp.len);
        return 1;
    }
    printf("%-34s -> (timeout)\n",label);
    return 0;
}
static long propLong(IOHIDDeviceRef d, CFStringRef k){CFTypeRef v=IOHIDDeviceGetProperty(d,k);if(!v||CFGetTypeID(v)!=CFNumberGetTypeID())return -1;long o=-1;CFNumberGetValue((CFNumberRef)v,kCFNumberLongType,&o);return o;}

int main(void){
    setvbuf(stdout,NULL,_IONBF,0);
    IOHIDManagerRef m=IOHIDManagerCreate(kCFAllocatorDefault,kIOHIDOptionsTypeNone);
    const void *keys[2]={CFSTR(kIOHIDVendorIDKey),CFSTR(kIOHIDProductIDKey)};
    int vid=0x320F,pid=0x5055;
    CFNumberRef vn=CFNumberCreate(NULL,kCFNumberIntType,&vid), pn=CFNumberCreate(NULL,kCFNumberIntType,&pid);
    const void *vals[2]={vn,pn};
    CFDictionaryRef match=CFDictionaryCreate(NULL,keys,vals,2,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
    IOHIDManagerSetDeviceMatching(m,match); IOHIDManagerOpen(m,kIOHIDOptionsTypeNone);
    CFSetRef ds=IOHIDManagerCopyDevices(m); CFIndex n=CFSetGetCount(ds);
    IOHIDDeviceRef *arr=calloc(n,sizeof(IOHIDDeviceRef)); CFSetGetValues(ds,(const void**)arr);
    IOHIDDeviceRef raw=NULL;
    for(CFIndex i=0;i<n;i++){ if(propLong(arr[i],CFSTR(kIOHIDPrimaryUsagePageKey))==0xFF60 && propLong(arr[i],CFSTR(kIOHIDPrimaryUsageKey))==0x61) raw=arr[i]; }
    if(!raw){printf("NO DEV\n");return 2;}
    if(IOHIDDeviceOpen(raw,kIOHIDOptionsTypeNone)!=kIOReturnSuccess){printf("OPEN FAIL\n");return 3;}
    uint8_t inBuf[64]; IOHIDDeviceRegisterInputReportCallback(raw,inBuf,64,input_cb,NULL);
    IOHIDDeviceScheduleWithRunLoop(raw,CFRunLoopGetCurrent(),kCFRunLoopDefaultMode);

    uint8_t ver[]={0x01};
    cmd(raw,ver,1,"protocol version");
    uint8_t lc[]={0x11};
    int layers=LAYERS;
    if(cmd(raw,lc,1,"layer count")) layers = resp.buf[1] ? resp.buf[1] : LAYERS;
    printf("layers = %d\n", layers);
    if (layers > 8) layers = 8;

    uint8_t keymap[8][LAYER_BYTES];
    memset(keymap,0,sizeof(keymap));
    int ok=1;
    for (int L=0; L<layers && ok; L++){
        for (int off=0; off<LAYER_BYTES; off+=28){
            int size = (LAYER_BYTES-off < 28) ? LAYER_BYTES-off : 28;
            uint8_t p[4]={0x12,(uint8_t)(off>>8),(uint8_t)(off&0xFF),(uint8_t)size};
            if(!cmd(raw,p,4,"read buffer")){ok=0;break;}
            if(resp.buf[0]!=0x12){ok=0;break;}
            memcpy(&keymap[L][off], &resp.buf[4], size);
        }
        printf("layer %d read %s\n",L,ok?"OK":"FAIL");
    }
    // print keycodes of layer 0 and 1 as rows
    for(int L=0;L<layers && ok;L++){
        printf("\n--- layer %d keycodes (row-major %dx%d) ---\n", L, ROWS, COLS);
        for(int r=0;r<ROWS;r++){
            printf("r%d:",r);
            for(int c=0;c<COLS;c++){
                int idx=r*COLS+c; uint16_t kc = (keymap[L][idx*2]<<8)|keymap[L][idx*2+1];
                printf(" %04X",kc);
            }
            printf("\n");
        }
    }
    if(ok){
        printf("\n=== write-back identical keymap test ===\n");
        int wrote=1;
        for(int L=0;L<layers && wrote;L++){
            for(int off=0;off<LAYER_BYTES;off+=28){
                int size = (LAYER_BYTES-off < 28) ? LAYER_BYTES-off : 28;
                uint8_t p[32]; memset(p,0,32); p[0]=0x13; p[1]=(uint8_t)(off>>8); p[2]=(uint8_t)(off&0xFF); p[3]=(uint8_t)size;
                memcpy(&p[4], &keymap[L][off], size);
                if(!cmd(raw,p,4+size,"write buffer")){wrote=0;break;}
            }
        }
        printf("write-back: %s\n", wrote?"OK":"FAIL");
        printf("=== verify read-back ===\n");
        int same=1;
        for(int L=0;L<layers && same;L++){
            for(int off=0;off<LAYER_BYTES && same;off+=28){
                int size=(LAYER_BYTES-off<28)?LAYER_BYTES-off:28;
                uint8_t p[4]={0x12,(uint8_t)(off>>8),(uint8_t)(off&0xFF),(uint8_t)size};
                if(!cmd(raw,p,4,"verify read")){same=0;break;}
                if(memcmp(&resp.buf[4], &keymap[L][off], size)!=0){printf("MISMATCH layer %d off %d\n",L,off);same=0;}
            }
        }
        printf("verify: %s\n", same?"IDENTICAL":"DIFF");
    }

    printf("\n=== lighting write test (set same brightness, save) ===\n");
    uint8_t gb[]={0x08,0x03,0x01,0x00};
    cmd(raw,gb,4,"get brightness");
    uint8_t br = resp.got ? resp.buf[3] : 5;
    uint8_t sb[]={0x07,0x03,0x01,0x00,0x00,0x00,0x00,br};
    cmd(raw,sb,8,"set brightness (same)");
    cmd(raw,gb,4,"get brightness after");
    uint8_t save[]={0x09,0x03,0x01,0x00};
    cmd(raw,save,4,"custom save");
    cmd(raw,gb,4,"get brightness after save");

    printf("\n=== device indication (0x03 0x05 0x01) ===\n");
    uint8_t di[]={0x03,0x05,0x01};
    cmd(raw,di,3,"set device indication");

    printf("\n=== encoder get (0x14, layer0 id0 cw) ===\n");
    uint8_t eg[]={0x14,0x00,0x00,0x01};
    cmd(raw,eg,4,"get encoder(0,0,1)");

    IOHIDDeviceUnscheduleFromRunLoop(raw,CFRunLoopGetCurrent(),kCFRunLoopDefaultMode);
    IOHIDDeviceClose(raw,kIOHIDOptionsTypeNone);
    printf("done\n");
    return 0;
}
