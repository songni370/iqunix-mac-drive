#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hid/IOHIDKeys.h>
#include <CoreFoundation/CoreFoundation.h>

static uint8_t rbuf[64]; static int rlen=0,rgot=0;
static void cb(void*c,IOReturn r,void*s,IOHIDReportType t,uint32_t id,uint8_t*rep,CFIndex len){if(len>64)len=64;memcpy(rbuf,rep,len);rlen=(int)len;rgot=1;CFRunLoopStop(CFRunLoopGetCurrent());}
static long pl(IOHIDDeviceRef d,CFStringRef k){CFTypeRef v=IOHIDDeviceGetProperty(d,k);if(!v||CFGetTypeID(v)!=CFNumberGetTypeID())return -1;long o=-1;CFNumberGetValue((CFNumberRef)v,kCFNumberLongType,&o);return o;}
static void drain(void){for(int i=0;i<10;i++){rgot=0;CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.02,false);if(!rgot)return;}}
static int cmd(IOHIDDeviceRef dev,const uint8_t*p,int plen,const char*label){
    uint8_t buf[32];memset(buf,0,32);for(int i=0;i<plen&&i<32;i++)buf[i]=p[i];
    drain();rgot=0;rlen=0;
    IOReturn res=IOHIDDeviceSetReport(dev,kIOHIDReportTypeOutput,0,buf,32);
    if(res!=kIOReturnSuccess){printf("%-38s SetReport=0x%08X\n",label,res);return 0;}
    for(int i=0;i<10&&!rgot;i++)CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.15,false);
    if(!rgot){printf("%-38s TIMEOUT\n",label);return 0;}
    printf("%-38s ->",label);for(int i=0;i<10&&i<rlen;i++)printf(" %02X",rbuf[i]);printf("\n");
    return 1;
}
int main(void){
    setvbuf(stdout,NULL,_IONBF,0);
    IOHIDManagerRef m=IOHIDManagerCreate(kCFAllocatorDefault,kIOHIDOptionsTypeNone);
    const void*keys[2]={CFSTR(kIOHIDVendorIDKey),CFSTR(kIOHIDProductIDKey)};
    int vid=0x320F,pid=0x5055;CFNumberRef vn=CFNumberCreate(NULL,kCFNumberIntType,&vid),pn=CFNumberCreate(NULL,kCFNumberIntType,&pid);
    const void*vals[2]={vn,pn};CFDictionaryRef mt=CFDictionaryCreate(NULL,keys,vals,2,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
    IOHIDManagerSetDeviceMatching(m,mt);IOHIDManagerOpen(m,kIOHIDOptionsTypeNone);
    CFSetRef ds=IOHIDManagerCopyDevices(m);CFIndex n=CFSetGetCount(ds);IOHIDDeviceRef*arr=calloc(n,sizeof(IOHIDDeviceRef));CFSetGetValues(ds,(const void**)arr);
    IOHIDDeviceRef raw=NULL;for(CFIndex i=0;i<n;i++){if(pl(arr[i],CFSTR(kIOHIDPrimaryUsagePageKey))==0xFF60&&pl(arr[i],CFSTR(kIOHIDPrimaryUsageKey))==0x61)raw=arr[i];}
    if(!raw){printf("no dev\n");return 2;}
    if(IOHIDDeviceOpen(raw,kIOHIDOptionsTypeNone)!=kIOReturnSuccess){printf("open fail\n");return 3;}
    uint8_t inb[64];IOHIDDeviceRegisterInputReportCallback(raw,inb,64,cb,NULL);IOHIDDeviceScheduleWithRunLoop(raw,CFRunLoopGetCurrent(),kCFRunLoopDefaultMode);

    printf("=== custom channel 0 / values ===\n");
    for(int v=1;v<=4;v++){uint8_t p[]={0x08,0x00,(uint8_t)v,0};char l[64];snprintf(l,64,"get ch0 val%d",v);cmd(raw,p,4,l);}
    for(int ch=1;ch<=5;ch++){uint8_t p[]={0x08,(uint8_t)ch,0x01,0};char l[64];snprintf(l,64,"get ch%d val1",ch);cmd(raw,p,4,l);}

    printf("\n=== UI_SYNC_REQUEST 0x16 ===\n");
    uint8_t u1[]={0x16,0x01,0x00,0x00};cmd(raw,u1,4,"0x16 01 00 00");
    uint8_t u2[]={0x16,0x01,0x00,0x01};cmd(raw,u2,4,"0x16 01 00 01");
    uint8_t u3[]={0x16,0x00};cmd(raw,u3,2,"0x16 00");

    printf("\n=== lighting full state ===\n");
    uint8_t gb[]={0x08,0x03,0x01,0},ge[]={0x08,0x03,0x02,0},gs[]={0x08,0x03,0x03,0},gc[]={0x08,0x03,0x04,0};
    cmd(raw,gb,4,"brightness");cmd(raw,ge,4,"effect");cmd(raw,gs,4,"speed");cmd(raw,gc,4,"color");
    int bright=rbuf[3]; // will refetch below properly
    cmd(raw,gb,4,"brightness(re)"); bright=rbuf[3];
    cmd(raw,ge,4,"effect(re)"); int effect=rbuf[3];
    cmd(raw,gs,4,"speed(re)"); int speed=rbuf[3];
    cmd(raw,gc,4,"color(re)"); int hue=rbuf[3], sat=rbuf[4];
    printf("state: bright=%d effect=%d speed=%d hue=%d sat=%d\n",bright,effect,speed,hue,sat);

    printf("\n=== roundtrip same values + save ===\n");
    uint8_t sb[]={0x07,0x03,0x01,(uint8_t)bright};cmd(raw,sb,4,"set brightness");
    uint8_t se[]={0x07,0x03,0x02,(uint8_t)effect};cmd(raw,se,4,"set effect");
    uint8_t ss[]={0x07,0x03,0x03,(uint8_t)speed};cmd(raw,ss,4,"set speed");
    uint8_t sc[]={0x07,0x03,0x04,(uint8_t)hue,(uint8_t)sat};cmd(raw,sc,5,"set color(hue,sat)");
    uint8_t sv[]={0x09,0x03,0x01};cmd(raw,sv,3,"save (brightness channel)");
    cmd(raw,gb,4,"brightness after");cmd(raw,gc,4,"color after");

    printf("\n=== macros: read full buffer ===\n");
    uint8_t msz[]={0x0D};cmd(raw,msz,1,"macro buffer size");
    int msize = (rbuf[1]<<8)|rbuf[2];
    printf("macro buffer size=%d\n",msize);
    int allFF=1;
    unsigned char mbuf[1024]; memset(mbuf,0,sizeof(mbuf));
    for(int off=0;off<msize;off+=28){
        int size=(msize-off<28)?msize-off:28;
        uint8_t p[]={0x0E,(uint8_t)(off>>8),(uint8_t)(off&0xFF),(uint8_t)size};
        if(!cmd(raw,p,4,"macro read")){allFF=0;break;}
        memcpy(&mbuf[off],&rbuf[4],size);
    }
    for(int i=0;i<msize;i++) if(mbuf[i]!=0xFF){allFF=0;break;}
    printf("macro buffer all-FF(empty)=%s\n", allFF?"yes":"no");
    if(allFF && msize>=512){
        printf("=== macro write test (safe: buffer empty) ===\n");
        // set last byte marker 0xFF (already FF), write 'TEST\0' at offset 0
        uint8_t w[]={0x0F,0x00,0x00,0x05,'T','E','S','T',0x00};cmd(raw,w,9,"macro write TEST+0");
        uint8_t r[]={0x0E,0x00,0x00,0x08};cmd(raw,r,4,"macro read back");
        printf("macro write persistent=%s\n", memcmp(&rbuf[4],"TEST\0",5)==0?"yes":"no");
        uint8_t rst[]={0x10};cmd(raw,rst,1,"macro reset (restore empty)");
        uint8_t r2[]={0x0E,0x00,0x00,0x08};cmd(raw,r2,4,"macro read after reset");
    }

    printf("\n=== restore lighting ===\n");
    cmd(raw,sb,4,"set brightness");
    cmd(raw,se,4,"set effect");
    cmd(raw,ss,4,"set speed");
    cmd(raw,sc,5,"set color");
    cmd(raw,sv,3,"save");
    cmd(raw,gb,4,"final brightness");cmd(raw,ge,4,"final effect");cmd(raw,gs,4,"final speed");cmd(raw,gc,4,"final color");

    IOHIDDeviceUnscheduleFromRunLoop(raw,CFRunLoopGetCurrent(),kCFRunLoopDefaultMode);
    IOHIDDeviceClose(raw,kIOHIDOptionsTypeNone);
    printf("done\n");
    return 0;
}
