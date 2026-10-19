#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hid/IOHIDKeys.h>
#include <CoreFoundation/CoreFoundation.h>

#define ROWS 8
#define COLS 16
#define LAYER_BYTES (ROWS*COLS*2)

static uint8_t rbuf[64]; static int rlen=0; static int rgot=0; static double sendTime=0;
static double nowSec(void){struct timespec ts;clock_gettime(CLOCK_MONOTONIC,&ts);return ts.tv_sec+ts.tv_nsec/1e9;}
static void cb(void*c,IOReturn r,void*s,IOHIDReportType t,uint32_t id,uint8_t*rep,CFIndex len){
    if(len>64)len=64; memcpy(rbuf,rep,len); rlen=(int)len; rgot=1; (void)nowSec;
    CFRunLoopStop(CFRunLoopGetCurrent());
}
static long pl(IOHIDDeviceRef d,CFStringRef k){CFTypeRef v=IOHIDDeviceGetProperty(d,k);if(!v||CFGetTypeID(v)!=CFNumberGetTypeID())return -1;long o=-1;CFNumberGetValue((CFNumberRef)v,kCFNumberLongType,&o);return o;}
static void pstr(IOHIDDeviceRef d,CFStringRef k,char*out,size_t n){CFTypeRef v=IOHIDDeviceGetProperty(d,k);out[0]=0;if(v&&CFGetTypeID(v)==CFStringGetTypeID())CFStringGetCString((CFStringRef)v,out,n,kCFStringEncodingUTF8);}
static void drain(void){for(int i=0;i<10;i++){rgot=0;CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.02,false);if(!rgot)return;}}
static int cmd(IOHIDDeviceRef dev,const uint8_t*p,int plen,const char*label,int verbose){
    uint8_t buf[32];memset(buf,0,32);for(int i=0;i<plen&&i<32;i++)buf[i]=p[i];
    drain(); rgot=0; rlen=0; sendTime=nowSec();
    IOReturn res=IOHIDDeviceSetReport(dev,kIOHIDReportTypeOutput,0,buf,32);
    if(res!=kIOReturnSuccess){printf("%-40s SetReport=0x%08X\n",label,res);return 0;}
    for(int i=0;i<10&&!rgot;i++)CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.15,false);
    if(!rgot){printf("%-40s -> TIMEOUT\n",label);return 0;}
    if(verbose){printf("%-40s ->",label);for(int i=0;i<16&&i<rlen;i++)printf(" %02X",rbuf[i]);printf("\n");}
    else printf("%-40s ok (cmd=%02X)\n",label,rbuf[0]);
    return 1;
}

int main(void){
    setvbuf(stdout,NULL,_IONBF,0);
    // 1) enumerate all raw-hid 0xFF60/0x61 devices
    IOHIDManagerRef all=IOHIDManagerCreate(kCFAllocatorDefault,kIOHIDOptionsTypeNone);
    IOHIDManagerSetDeviceMatching(all,NULL);
    IOHIDManagerOpen(all,kIOHIDOptionsTypeNone);
    CFSetRef set=IOHIDManagerCopyDevices(all);
    CFIndex cnt=set?CFSetGetCount(set):0;
    IOHIDDeviceRef *devs=calloc(cnt,sizeof(IOHIDDeviceRef));
    if(set)CFSetGetValues(set,(const void**)devs);
    IOHIDDeviceRef raw=NULL;
    printf("=== raw HID 0xFF60/0x61 devices ===\n");
    for(CFIndex i=0;i<cnt;i++){
        long page=pl(devs[i],CFSTR(kIOHIDPrimaryUsagePageKey));
        long usage=pl(devs[i],CFSTR(kIOHIDPrimaryUsageKey));
        if(page==0xFF60&&usage==0x61){
            char prod[256]; pstr(devs[i],CFSTR(kIOHIDProductKey),prod,sizeof(prod));
            printf("VID=0x%04lX PID=0x%04lX product=%s\n",pl(devs[i],CFSTR(kIOHIDVendorIDKey)),pl(devs[i],CFSTR(kIOHIDProductIDKey)),prod);
            if(pl(devs[i],CFSTR(kIOHIDVendorIDKey))==0x320F&&pl(devs[i],CFSTR(kIOHIDProductIDKey))==0x5055)raw=devs[i];
        }
    }
    if(!raw){printf("target not found\n");return 2;}
    if(IOHIDDeviceOpen(raw,kIOHIDOptionsTypeNone)!=kIOReturnSuccess){printf("open fail\n");return 3;}
    uint8_t inb[64];IOHIDDeviceRegisterInputReportCallback(raw,inb,64,cb,NULL);
    IOHIDDeviceScheduleWithRunLoop(raw,CFRunLoopGetCurrent(),kCFRunLoopDefaultMode);

    printf("\n=== layers (correct offset) ===\n");
    uint8_t km[4][LAYER_BYTES]; memset(km,0,sizeof(km));
    for(int L=0;L<4;L++){
        for(int off=0;off<LAYER_BYTES;off+=28){
            int size=(LAYER_BYTES-off<28)?LAYER_BYTES-off:28;
            int base=L*LAYER_BYTES+off;
            uint8_t p[4]={0x12,(uint8_t)(base>>8),(uint8_t)(base&0xFF),(uint8_t)size};
            if(!cmd(raw,p,4,"read layer buffer",0)){printf("read fail\n");return 4;}
            memcpy(&km[L][off],&rbuf[4],size);
        }
    }
    for(int L=0;L<4;L++){
        int diff=0; if(L>0) for(int b=0;b<LAYER_BYTES;b++) if(km[L][b]!=km[0][b])diff++;
        printf("layer %d: bytes differing from layer0 = %d\n",L,diff);
    }
    // print layer 1..3 non-zero/different keys
    for(int L=1;L<4;L++){
        printf("--- layer %d differing keys ---\n",L);
        int shown=0;
        for(int i=0;i<ROWS*COLS;i++){
            uint16_t k0=(km[0][i*2]<<8)|km[0][i*2+1];
            uint16_t kL=(km[L][i*2]<<8)|km[L][i*2+1];
            if(k0!=kL){printf("  (r%d,c%d) %04X -> %04X\n",i/COLS,i%COLS,k0,kL);if(++shown>30)break;}
        }
        if(!shown)printf("  (identical to layer 0)\n");
    }

    printf("\n=== write test: change an unused position, read back, restore ===\n");
    // find an unused (0x0000) position in layer 0, prefer row 6
    int pos=-1;
    for(int r=6;r<8&&pos<0;r++)for(int c=0;c<COLS;c++){uint16_t kc=(km[0][(r*COLS+c)*2]<<8)|km[0][(r*COLS+c)*2+1];if(kc==0){pos=r*COLS+c;break;}}
    if(pos<0){printf("no unused key found\n");}
    else{
        int row=pos/COLS,col=pos%COLS;
        printf("target matrix pos r%d c%d\n",row,col);
        uint8_t wr[32];memset(wr,0,32);wr[0]=0x13;wr[1]=(uint8_t)((pos*2)>>8);wr[2]=(uint8_t)((pos*2)&0xFF);wr[3]=0x02;wr[4]=0x00;wr[5]=0x04;
        cmd(raw,wr,6,"write keycode=0x0004",1);
        uint8_t rd[4]={0x12,(uint8_t)((pos*2)>>8),(uint8_t)((pos*2)&0xFF),0x02};
        cmd(raw,rd,4,"read back",1);
        printf("read-back keycode = %04X (expect 0004)\n",(rbuf[4]<<8)|rbuf[5]);
        uint8_t rs[32];memset(rs,0,32);rs[0]=0x13;rs[1]=(uint8_t)((pos*2)>>8);rs[2]=(uint8_t)((pos*2)&0xFF);rs[3]=0x02;rs[4]=0x00;rs[5]=0x00;
        cmd(raw,rs,6,"restore keycode=0x0000",1);
        cmd(raw,rd,4,"read back after restore",1);
        printf("restored keycode = %04X (expect 0000)\n",(rbuf[4]<<8)|rbuf[5]);
    }

    printf("\n=== lighting state (full 32B) ===\n");
    uint8_t gb[]={0x08,0x03,0x01,0}; cmd(raw,gb,4,"get brightness",1);
    uint8_t ge[]={0x08,0x03,0x02,0}; cmd(raw,ge,4,"get effect",1);
    uint8_t gs[]={0x08,0x03,0x03,0}; cmd(raw,gs,4,"get speed",1);
    uint8_t gc[]={0x08,0x03,0x04,0}; cmd(raw,gc,4,"get color",1);

    printf("\n=== try set brightness payload layouts (target 5) ===\n");
    // A: [07, ch, id, value]
    uint8_t a[]={0x07,0x03,0x01,0x05}; cmd(raw,a,4,"A set [07,03,01,05]",1);
    cmd(raw,gb,4,"A get brightness",1);
    // B: [07, ch, id, 0, value]
    uint8_t b[]={0x07,0x03,0x01,0x00,0x05}; cmd(raw,b,5,"B set [07,03,01,00,05]",1);
    cmd(raw,gb,4,"B get brightness",1);
    // C: [07, ch, id, 0,0,0, value]
    uint8_t c[]={0x07,0x03,0x01,0,0,0,0x05}; cmd(raw,c,7,"C set [07,03,01,0,0,0,05]",1);
    cmd(raw,gb,4,"C get brightness",1);

    printf("\n=== save payload layouts ===\n");
    uint8_t s1[]={0x09,0x03,0x01}; cmd(raw,s1,3,"save [09,03,01]",1);
    cmd(raw,gb,4,"get after save1",1);
    uint8_t s2[]={0x09,0x03,0x01,0x00,0x00}; cmd(raw,s2,5,"save [09,03,01,00,00]",1);
    cmd(raw,gb,4,"get after save2",1);
    uint8_t s3[]={0x09,0x03}; cmd(raw,s3,2,"save [09,03]",1);
    cmd(raw,gb,4,"get after save3",1);

    printf("\n=== restore brightness 5 then save (layout A) ===\n");
    cmd(raw,a,4,"set 5",1);
    cmd(raw,s1,3,"save",1);
    cmd(raw,gb,4,"final brightness",1);

    printf("\n=== macro write test (write same zeros) ===\n");
    uint8_t m1[]={0x0F,0x00,0x00,0x08,0,0,0,0,0,0,0,0}; cmd(raw,m1,12,"macro set buf(0,8 zeros)",1);
    uint8_t m2[]={0x0E,0x00,0x00,0x08}; cmd(raw,m2,4,"macro get buf(0,8)",1);

    IOHIDDeviceUnscheduleFromRunLoop(raw,CFRunLoopGetCurrent(),kCFRunLoopDefaultMode);
    IOHIDDeviceClose(raw,kIOHIDOptionsTypeNone);
    printf("\ndone\n");
    return 0;
}
