// ZX Spectrum 48K snapshot runner: loads orig/ram.bin + regs.json-like regs, scripted keys, dumps frames
#include "z80.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
static uint8_t mem[65536]; static uint8_t keyrow[8];
static uint8_t rd(void*u,uint16_t a){return mem[a];}
static z80*zp; static void wr(void*u,uint16_t a,uint8_t v){ if(a==0xC5DD) fprintf(stderr,"W C5DD=%02X pc=%04X\n",v,zp->pc); if(a>=0x4000) mem[a]=v; }
static int pcnt[65536]; static uint8_t pin(z80*z,uint8_t lo){ if(getenv("PORTS")){ pcnt[((z->b<<8)|lo)]++; } uint16_t p=(z->b<<8)|lo;
  if(lo==0xFE){ uint8_t v=0xFF; for(int r=0;r<8;r++) if(!(p&(0x100<<r))) v&=keyrow[r]; return v; }
  if(lo==0x1F) return 0x00;
  return 0xFF; }
static void pout(z80*z,uint8_t lo,uint8_t v){}
typedef struct{char k; int row,bit;} K;
static const K keys[]={{'1',3,0},{'2',3,1},{'3',3,2},{'4',3,3},{'5',3,4},{'0',4,0},{'9',4,1},{'8',4,2},{'7',4,3},{'6',4,4},
 {'Q',2,0},{'W',2,1},{'E',2,2},{'R',2,3},{'T',2,4},{'P',5,0},{'O',5,1},{'I',5,2},{'U',5,3},{'Y',5,4},
 {'A',1,0},{'S',1,1},{'D',1,2},{'F',1,3},{'G',1,4},{'\n',6,0},{'L',6,1},{'K',6,2},{'J',6,3},{'H',6,4},
 {'Z',0,1},{'X',0,2},{'C',0,3},{'V',0,4},{' ',7,0},{'M',7,2},{'N',7,3},{'B',7,4},{'$',7,1},{'^',0,0}};
static const int zx[8][3]={{0,0,0},{0,0,205},{205,0,0},{205,0,205},{0,205,0},{0,205,205},{205,205,0},{205,205,205}};
static void shot(const char*fn){ FILE*f=fopen(fn,"wb"); fprintf(f,"P6 256 192 255\n");
  for(int y=0;y<192;y++) for(int x=0;x<256;x++){
    int a=0x4000|((y&0xC0)<<5)|((y&7)<<8)|((y&0x38)<<2)|(x>>3); int bit=(mem[a]>>(7-(x&7)))&1;
    uint8_t at=mem[0x5800+(y>>3)*32+(x>>3)]; int ink=at&7,pap=(at>>3)&7,br=(at&0x40)?1:0; int c=bit?ink:pap;
    for(int k=0;k<3;k++){ int v=zx[c][k]; if(br&&v) v=255; fputc(v,f);} }
  fclose(f);}
static int tr; static int hist[4096];
int main(int argc,char**argv){
  // args: totalframes shotEvery prefix  [key:start:len ...]
  int total=atoi(argv[1]), every=atoi(argv[2]); const char*pre=argv[3];
  FILE*f=fopen("orig/ram.bin","rb"); fread(mem,1,65536,f); fclose(f);
  memset(mem,0xC9,0x4000); { FILE*rf=fopen("/home/claude/stockcar/tools/test/48.rom","rb"); if(rf){ fread(mem,1,16384,rf); fclose(rf);} }
  z80 z; zp=&z; z80_init(&z); z.read_byte=rd; z.write_byte=wr; z.port_in=pin; z.port_out=pout;
  unsigned v[40]; FILE*r=fopen("orig/regs.txt","r"); for(int i=0;i<40;i++) if(fscanf(r,"%u",&v[i])!=1) break; fclose(r);
  z.a=v[0];z.b=v[2];z.c=v[3];z.d=v[4];z.e=v[5];z.h=v[6];z.l=v[7]; z.pc=v[8]; z.sp=v[9]; z.i=v[10]; z.ix=v[11]; z.iy=v[12];
  z.iff1=z.iff2=1; z.interrupt_mode=2; z.a_=v[13];z.f_=v[14];z.b_=v[15];z.c_=v[16];z.d_=v[17];z.e_=v[18];z.h_=v[19];z.l_=v[20]; { uint8_t F=v[1]; z.sf=F>>7&1; z.zf=F>>6&1; z.yf=F>>5&1; z.hf=F>>4&1; z.xf=F>>3&1; z.pf=F>>2&1; z.nf=F>>1&1; z.cf=F&1; }
  struct{char k;int s,l;} ks[64]; int nk=0; for(int i=4;i<argc&&nk<64;i++){ char c; int s,l; if(sscanf(argv[i],"%c:%d:%d",&c,&s,&l)==3){ if(c=='_')c=' '; if(c=='#')c='\n'; ks[nk].k=c;ks[nk].s=s;ks[nk].l=l;nk++; } }
  for(int fr=0;fr<total;fr++){
    memset(keyrow,0xFF,8);
    for(int i=0;i<nk;i++) if(fr>=ks[i].s&&fr<ks[i].s+ks[i].l) for(int j=0;j<sizeof keys/sizeof*keys;j++) if(keys[j].k==ks[i].k) keyrow[keys[j].row]&=~(1<<keys[j].bit);
    unsigned long end=z.cyc+69888; z80_gen_int(&z,0xFF);
    while(z.cyc<end){ if(z.halted&&!z.iff1){z.iff1=z.iff2=1;} if(getenv("TRACEFR")&&fr==atoi(getenv("TRACEFR"))&&tr++<60) fprintf(stderr,"%04X: %02X %02X %02X  hl=%04X de=%04X bc=%04X a=%02X\n",z.pc,mem[z.pc],mem[z.pc+1],mem[z.pc+2],(z.h<<8)|z.l,(z.d<<8)|z.e,(z.b<<8)|z.c,z.a); if(getenv("HIST")&&fr>=300) hist[z.pc>>4]++; z80_step(&z); }
    if(getenv("PCDBG")&&fr%20==0) fprintf(stderr,"fr %d pc %04X sp %04X halted %d iff %d\n",fr,z.pc,z.sp,z.halted,z.iff1);
    if(every&&fr%every==0){ char fn[128]; sprintf(fn,"%s%04d.ppm",pre,fr); shot(fn); }
  }
  if(getenv("HIST")) for(int i=0;i<4096;i++) if(hist[i]>20000) fprintf(stderr,"pc %04X0 x%d\n",i,hist[i]); if(getenv("PORTS")) for(int i=0;i<65536;i++) if(pcnt[i]>50) fprintf(stderr,"port %04X x%d\n",i,pcnt[i]); shot("orig/last.ppm"); { FILE*g=fopen("orig/final.bin","wb"); fwrite(mem,1,65536,g); fclose(g);}
  return 0; }
