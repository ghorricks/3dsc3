// Smoke-test harness: runs stockcar.nex in a minimal Z80N/Next model (memory paging, L2, ports, NEXTREG).
#include "z80.h"
int vzh=0;
#include <stdlib.h>
#include <string.h>
#include <math.h>
static uint8_t ram[224*8192]; static uint8_t mmu[8]={0xFF,0xFF,10,11,4,5,0,1};
static uint8_t pad2; static uint8_t regs[256], nsel, pal[256], palidx, padval, ayreg; static int palsel;
static int ifr; static unsigned long lastint; static int wcnt[8]; static unsigned long prof[65536]; static unsigned long wsum,wmax,last_exit; static int wn,wf_lastf; static unsigned wf_addr; static int cpu_bad[3]; static uint8_t spr[8]; static int sprn, patcount; static int mode=0; static uint8_t ay[16]; static int ras=0, frames=0;
static uint8_t rd(void*u,uint16_t a){uint8_t p=mmu[a>>13]; return p==0xFF?0:ram[p*8192+(a&0x1FFF)];}
static unsigned minsp; static uint16_t curpc; static void* zz; static void wr(void*u,uint16_t a,uint8_t v){ if(getenv("WBOOST")){ static uint16_t ba=0; if(!ba) ba=strtoul(getenv("WBOOST"),0,16); if(a==ba) printf("WB %02X pc=%04X frames=%d\n",v,curpc,frames); } if(getenv("WW")&&a>=0xB1FF&&a<0xB210&&mmu[a>>13]==5){ static int nn=0; if(nn++<4) printf("WRITE %04X=%02X by pc=%04X ix=%04X sp=%04X frames=%d stk:",a,v,curpc,((struct z80*)zz)->ix,((struct z80*)zz)->sp,frames); if(nn==1){ unsigned sp=((struct z80*)zz)->sp; for(int q=0;q<10;q++) printf(" %02X%02X",ram[5*8192+((sp+2*q+1)&0x1FFF)],ram[5*8192+((sp+2*q)&0x1FFF)]); } printf("\n"); }uint8_t p=mmu[a>>13]; if(p!=0xFF) ram[p*8192+(a&0x1FFF)]=v;}
static void nreg(uint8_t r,uint8_t v){ regs[r]=v;
  if(r>=0x50&&r<=0x57) mmu[r-0x50]=v;
  else if(r==0x43) palsel=(v>>4)&7;
  else if(r==0x40) palidx=v;
  else if(r==0x44){ static int ph; if(!ph){ if(palsel==1) pal[palidx]=v; ph=1;} else { ph=0; palidx++; } }
  else if(r==0x41){ if(palsel==1) pal[palidx]=v; palidx++; } }
static uint8_t pin(z80*z,uint8_t lo){ uint16_t p=(z->b<<8)|lo;
  if(lo==0x1F) return padval; if(lo==0x37) return pad2;
  if(lo==0xFE&&getenv("DBGT")){ int f=frames-60; if(f>=0&&f<50&&(f%10)<4){ int k=f/10; unsigned want[5]={0xFD,0xFB,0x7F,0xDF,0xFD}, bit[5]={2,2,4,3,4}; if(z->b==want[k]) return 0xFF&~(1<<bit[k]); } }
  if(lo==0xFE){ if(getenv("PAUSEF")&&(z->b==0xFE||z->b==0x7F)){ int pf=atoi(getenv("PAUSEF")); if((frames>=pf&&frames<pf+4)||(frames>=pf+50&&frames<pf+54)) return 0xFE; } return 0xFF; }
  if(p==0x253B){ if(nsel==0x1F){ uint8_t r=ras&255; ras+=4; if(ras>=312){ras=0; ifr++; z80_gen_int(z,0xFF);} if(r==192)frames++; return r;} return regs[nsel]; }
  return 0xFF; }
static void pout(z80*z,uint8_t lo,uint8_t v){ uint16_t p=(z->b<<8)|lo;
  if(p==0x243B) nsel=v; else if(p==0x253B) nreg(nsel,v);
  else if(lo==0x57){ spr[sprn++&7]=v; } else if(lo==0x5B) patcount++;
  else if(p==0xFFFD) ayreg=v&15; else if(p==0xBFFD){ ay[ayreg]=v; if(getenv("AYLOG")) printf("AY f%d r%d=%d\n",ifr,ayreg,v); } }
static unsigned symaddr(const char*n){ static char cn[256][64]; static unsigned ca[256]; static int cc=0; for(int q=0;q<cc;q++) if(!strcmp(cn[q],n)) return ca[q]; FILE*f=fopen("build/main.sym","r"); char l[256],nm[128]; unsigned a;
  while(fgets(l,256,f)){ if(sscanf(l,"%127[^:]: EQU 0x%x",nm,&a)==2 && !strcmp(nm,n)){fclose(f); if(cc<256&&strlen(n)<64){ strcpy(cn[cc],n); ca[cc++]=a; } return a;} } fclose(f); fprintf(stderr,"no sym %s\n",n); exit(2);}
static void dump(const char*fn){ FILE*f=fopen(fn,"wb"); fprintf(f,"P6 256 192 255\n");
  for(int i=0;i<256*192;i++){ uint8_t c=pal[ram[18*8192+i]]; uint8_t r=(c>>5)*255/7,g=((c>>2)&7)*255/7,b=(c&3)*255/3; fputc(r,f);fputc(g,f);fputc(b,f);} fclose(f);}
static void pk(unsigned a,uint8_t v){ static unsigned PB=0,HC=0; if(!PB){ PB=symaddr("pc_block"); HC=symaddr("hctx"); } wr(0,a,v); wr(0,a-PB+HC,v); }
static int cf=-1, nmf=-1;
int main(int argc,char**argv){
  FILE*f=fopen("stockcar.nex","rb"); uint8_t h[512]; fread(h,1,512,f);
  static const int order[]={5,2,0,1,3,4}; int nb=0;
  for(int k=0;k<112;k++){ int b= k<6?order[k]:k; if(h[18+b]){ fread(&ram[b*2*8192],1,16384,f); nb++; } }
  fprintf(stderr,"loaded %d banks, PC=%02X%02X\n",nb,h[15],h[14]);
  z80 z; zz=&z; z80_init(&z); z.read_byte=rd; z.write_byte=wr; z.port_in=pin; z.port_out=pout; z.pc=h[14]|(h[15]<<8); z.sp=h[12]|(h[13]<<8);
  unsigned A_X=symaddr("car_x"),A_Y=symaddr("car_y"),A_H=symaddr("heading"),A_S=symaddr("speed"),A_LP=symaddr("lastp"),A_TI=symaddr("track_idx");
  unsigned a_pgn=symaddr("pg_names"), a_pgc=symaddr("pg_choice"), a_rdy=symaddr("pg_ready"); int cho_hit=0;
  int trk=argc>1?atoi(argv[1]):0; int accel_frames=argc>2?atoi(argv[2]):200; mode=argc>3?atoi(argv[3]):0; const char*shot=argc>4?argv[4]:0;
  int sx=0,sy=0,ex=0,ey=0,es=0,ehd=0,elp=0; int lastf=-1, phase=0; int startedrace=0; int lastp2=-1, barn=0, ms_done=0, updt_done=0, upd_hit=0; unsigned long guard=0;
  while(frames<4+accel_frames+40 && guard<(getenv("GUARD")?strtoul(getenv("GUARD"),0,10):900000000UL)){
    uint16_t pc=z.pc; curpc=pc; unsigned long c0=z.cyc; uint8_t o0=rd(0,pc),o1=rd(0,pc+1);
    if(getenv("HUMBOT") && pc==symaddr("human_step")){ static double wpf=0; static int hbn=0; static int px_[256],py_[256]; if(!hbn){ FILE*pf=fopen(getenv("HUMBOT"),"r"); int a,b; while(fscanf(pf,"%d %d",&a,&b)==2){ px_[hbn]=a; py_[hbn]=b; hbn++; } fclose(pf); }
      { static int lb=-1; unsigned cx=rd(0,z.ix+26)|(rd(0,z.ix+27)<<8); int bb=rd(0,cx+symaddr("boost_cnt")-symaddr("pc_block")); if(bb!=lb){ printf("BOOST %d->%d frame %d wpf %.1f lapsdone %d laptenths %d\n",lb,bb,frames,wpf,rd(0,z.ix+24),rd(0,cx+symaddr("lap_tenths")-symaddr("pc_block"))|(rd(0,cx+symaddr("lap_tenths")-symaddr("pc_block")+1)<<8)); lb=bb; } } wpf+=1.0/7.4; int i=(int)wpf; double fr=wpf-i; int i0=i%hbn,i1=(i+1)%hbn,i2=(i+2)%hbn; double x=px_[i0]+(px_[i1]-px_[i0])*fr,y=py_[i0]+(py_[i1]-py_[i0])*fr;
      double ang=atan2(2.0*(py_[i2]-py_[i0]),(double)(px_[i2]-px_[i0])); int hd=((int)floor(ang/(2*M_PI/32)+0.5))&31; z.cyc+=0; if(getenv("HBOFF")){ int ox=0,oy=0; sscanf(getenv("HBOFF"),"%d,%d",&ox,&oy); x+=ox; y+=oy; } wr(0,z.ix+1,(int)x); wr(0,z.ix+3,(int)y); wr(0,z.ix+4,hd); wr(0,z.ix+5,150); if((i&15)==0 && fr<0.14) { unsigned cx=rd(0,z.ix+26)|(rd(0,z.ix+27)<<8); printf("HB wp %d lap %d best %d boost %d ctxboost %d\n",i,rd(0,z.ix+24),rd(0,z.ix+14)|(rd(0,z.ix+15)<<8),rd(0,z.ix+21),rd(0,cx+symaddr("boost_cnt")-symaddr("pc_block"))); } }
    if(getenv("HUMBOT") && pc==symaddr("update_lap")){ static int lb2=-1; int bb=rd(0,symaddr("boost_cnt")); if(bb!=lb2){ printf("UL boost %d->%d frame %d laps %d gate %d lapt %d\n",lb2,bb,frames,rd(0,symaddr("laps_done")),rd(0,symaddr("gate")),rd(0,symaddr("lap_tenths"))|(rd(0,symaddr("lap_tenths")+1)<<8)); lb2=bb; } }
    if(pc==8){ static FILE*efs[16]; FILE*ef=efs[z.a&15]; uint16_t ra=rd(0,z.sp)|(rd(0,z.sp+1)<<8); int fn=rd(0,ra); z.sp+=2; z.pc=ra+1; z.cf=0; z.cyc+=100;
      if(fn==0x9A){ char nm[32]; int i=0; for(;i<31&&(nm[i]=rd(0,z.ix+i));i++); const char*sp=getenv("SAV")?getenv("SAV"):"build/3DSC3.SAV"; if(!strcmp(nm,"3DSC3.TMP")) sp="build/3DSC3.TMP"; static char fp[64]; if(!strncmp(nm,"3DSC3_",6)){ snprintf(fp,64,"build/%s",nm); sp=fp; } if(!strcmp(nm,"3DSC3.SLC")){ static char sl[64]; snprintf(sl,64,"build/%s",nm); sp=sl; } if(z.b==0x0A){ ef=fopen(sp,"r+b"); if(!ef) ef=fopen(sp,"w+b"); } else ef=fopen(sp,(z.b&2)?"wb":"rb"); if(!ef){ z.cf=1; z.a=5; } else { int h=1; while(efs[h]) h++; efs[h]=ef; z.a=h; } printf("esx open %s mode %d ok %d ra=%04X sp=%04X f=%d\n",nm,z.b,ef!=0,ra,z.sp,frames); }
      else if(fn==0x9D){ int n=0,L=(z.b<<8)|z.c; for(int i=0;i<L;i++){ int ch=fgetc(ef); if(ch<0)break; wr(0,z.ix+i,ch); n++; } z.b=n>>8; z.c=n&255; printf("esx read %d\n",n); }
      else if(fn==0x9E){ int L=(z.b<<8)|z.c; for(int i=0;i<L;i++) fputc(rd(0,z.ix+i),ef); printf("esx write %d\n",L); }
      else if(fn==0x9B){ if(ef){ fclose(ef); efs[z.a&15]=0; } }
      else if(fn==0x8F){ char cmd[200]; int i=0; unsigned hl=z.ix; for(;i<199&&(cmd[i]=rd(0,hl+i));i++); printf("http: f%d ix=%04X mmu7=%d tbl=%02X%02X%02X %s\n",frames,z.ix,mmu[7],ram[80*8192],ram[80*8192+1],ram[80*8192+5],cmd);
        if(getenv("NETFAIL")){ z.cf=1; z.a=9; } else { const char*rsp=strstr(cmd,"?version")?(getenv("OLDV")?"26111001,releases/old.nex,1,0\n":"26111999,releases/3DSC3_26111999.nex,442880,00000000\n"):strstr(cmd,"name=")?"OK\n":strstr(cmd,"track=all")?"1,GAAAA,14.2\n1,GAVIN,14.5\n1,ETHAN,15.6\n1,3DSC3,99.9\n2,GAV  ,10.8\n2,GAVIN,11.9\n2,3DSC3,99.8\n3,DAD  ,18.5\n3,3DSC3,99.8\n24,ZED  ,60.1\n":"---\nGAVIN,42.3\nSPEED,42.5\nBLUE,100.0\n---\n"; if(strstr(cmd,"?download")){ const char*pp=strstr(cmd,"&part="); int part=pp?atoi(pp+6):0; int n=getenv("UPDSIZE")?atoi(getenv("UPDSIZE")):442880; FILE*df=fopen("build/3DSC3.SLC","wb"); for(int k=part*60928;k<n&&k<(part+1)*60928;k++){ if(k<4) fputc("Next"[k],df); else fputc(k&255,df);} fclose(df); printf("slice %d\n",part); } if(strstr(cmd,"-f 3DSC3.TMP")){ FILE*tf=fopen("build/3DSC3.TMP","wb"); fputs(rsp,tf); fclose(tf); } } }
      else if(fn==0xB0){ char a1[32],a2[32]; int i=0; for(;i<31&&(a1[i]=rd(0,z.ix+i));i++); a1[i]=0; i=0; unsigned de=(z.d<<8)|z.e; for(;i<31&&(a2[i]=rd(0,de+i));i++); a2[i]=0; char p1[64],p2[64]; snprintf(p1,64,"build/%s",a1); snprintf(p2,64,"build/%s",a2); int r=rename(p1,p2); if(r){ z.cf=1; z.a=5; } printf("esx rename %s -> %s : %d\n",a1,a2,r); }
      else if(fn==0x9F){ long off=((long)z.c<<24)|((long)z.d<<16)|((long)z.e<<8); off=((long)z.b<<24)|((long)z.c<<16)|((long)z.d<<8)|z.e; fseek(ef,off,SEEK_SET); printf("esx seek %ld\n",off); }
      else if(fn==0xAD){ char nm[32]; int i=0; for(;i<31&&(nm[i]=rd(0,z.ix+i));i++); nm[i]=0; if(!strncmp(nm,"3DSC3",5)&&nm[5]!='.'||!strcmp(nm,"3DSC3.SLC")||!strcmp(nm,"3DSC3.OLD")||!strcmp(nm,"3DSC3.NEX")){ char p[64]; snprintf(p,64,"build/%s",nm); remove(p);} else remove("build/3DSC3.TMP"); }
      else printf("esx unknown %02X\n",fn); }
    else if(getenv("UPDT") && pc==symaddr("menu_run") && !updt_done && (updt_done=1)){ z.sp-=2; wr(0,z.sp,pc&255); wr(0,z.sp+1,pc>>8); z.pc=symaddr("hs_update"); }
    else if(getenv("UPDT") && (pc==symaddr("pg_update.k1")||pc==symaddr("ud_fail")+0*1) && !upd_hit++ ){ printf("UPDATE reached %04X frames %d\n",pc,frames); if(pc==symaddr("pg_update.k1")) frames=4+accel_frames+40; }
    else if(getenv("MUSLOG") && pc==symaddr("menu_run.loop") && frames>=atoi(getenv("MUSLOG"))){ frames=4+accel_frames+40; }
    else if(getenv("MENUSHOT") && pc==symaddr("menu_run.loop") && ++vzh>=(getenv("VZF")?atoi(getenv("VZF")):0) && !ms_done && (ms_done=1)){ dump(getenv("MENUSHOT")); frames=4+accel_frames+40; }
    else if(getenv("INSTR") && pc==symaddr("menu_run") && !updt_done && (updt_done=1)){ z.sp-=2; wr(0,z.sp,pc&255); wr(0,z.sp+1,pc>>8); z.pc=symaddr("menu_instr"); }
    else if(getenv("DBGT") && pc==symaddr("pg_instr.w2") && frames>=220 && !ms_done && (ms_done=1)){ printf("trk_max=%d\n",rd(0,symaddr("trk_max"))); dump("build/instr.ppm"); frames=4+accel_frames+40; }
    else if(getenv("INSTR") && !getenv("DBGT") && pc==symaddr("pg_instr.w2") && !ms_done && (ms_done=1)){ dump("build/instr.ppm"); frames=4+accel_frames+40; }
    else if(getenv("BARSHOT") && pc==symaddr("ud_bar.k") && (++barn==2)){ dump("build/bar.ppm"); frames=4+accel_frames+40; }
    else if(pc==a_pgc && (cho_hit=1)&&0){}
    else if(pc==a_rdy && !getenv("READY")){ z.pc=rd(0,z.sp)|(rd(0,z.sp+1)<<8); z.sp+=2; z.cyc+=10; }
    else if(pc==a_pgn && !getenv("NAMES")){ z.pc=rd(0,z.sp)|(rd(0,z.sp+1)<<8); z.sp+=2; z.cyc+=10; }   /* skip the name entry screen unless NAMES=1 */
    else if(o0==0xED&&o1==0x91){ nreg(rd(0,pc+2),rd(0,pc+3)); z.pc+=4; z.cyc+=20; }
    else if(o0==0xED&&o1==0x92){ nreg(rd(0,pc+2),z.a); z.pc+=3; z.cyc+=17; }
    else if(o0==0xED&&o1==0x23){ z.a=(z.a>>4)|(z.a<<4); z.pc+=2; z.cyc+=8; }   /* swapnib */
    else if(o0==0xED&&o1==0x30){ unsigned p=z.d*z.e; z.d=p>>8; z.e=p&255; z.pc+=2; z.cyc+=8; }
    else z80_step(&z);
    if(getenv("WATCH")){ static unsigned w[8]; static int nw=0; if(!nw){ char*p=getenv("WATCH"); while(*p&&nw<8){ w[nw++]=strtoul(p,&p,16); if(*p==',')p++; } } for(int q=0;q<nw;q++) if(z.pc==w[q]) wcnt[q]++; }
    { static uint16_t ring[32]; static int rp=0; ring[rp++&31]=pc; if(getenv("LOW")&&pc<0x4000&&pc!=8){ static int n=0; if(n++<1){ printf("LOW pc=%04X sp=%04X frames=%d\n",pc,z.sp,frames); for(int q=0;q<32;q++) printf("%04X ",ring[(rp+q)&31]); printf("\n"); for(int q=0;q<48;q++) printf("%02X ",rd(0,0xB1F0+q)); printf("\n"); } } }
    { static uint16_t ms=0xFFFF; if(z.sp<ms&&z.sp>0x9000){ ms=z.sp; minsp=ms; } } guard++; { static int pfv=-2; if(pfv==-2){ pfv=getenv("PF")?atoi(getenv("PF")):-1; } if(pfv>=0?frames==pfv:frames>40) prof[pc]+=z.cyc-c0; }
    if(wf_addr==0) wf_addr=symaddr("wait_frame");
    if(z.pc==wf_addr && frames>40){ if(last_exit){ unsigned long w=z.cyc-last_exit; wsum+=w; wn++; if(w>wmax)wmax=w; if(w>(getenv("SPK")?atol(getenv("SPK")):600000)) printf("SPIKE f%d w=%lu\n",frames,w); } }
    if(frames!=wf_lastf){ wf_lastf=frames; last_exit=z.cyc; }
    if(frames!=lastf){ lastf=frames;
      int sf=(getenv("MUSLOG")||getenv("DBGT"))?100000:4;
      if(getenv("MSEL")&&frames==30) dump("build/hs.ppm");
      if(frames==3 && !phase){ dump("build/test_select.ppm"); phase=1; }
      padval=0;
      if(getenv("MUSPOKE")&&frames==3){ int pg,pt; sscanf(getenv("MUSPOKE"),"%d,%d",&pg,&pt); wr(0,symaddr("mus_pg"),pg); wr(0,symaddr("mus_ptr"),pt&255); wr(0,symaddr("mus_ptr")+1,pt>>8); }
      if(frames==1){ wr(0,symaddr("ctl"),getenv("ALLCPU")?6:0); wr(0,symaddr("ctl")+1,6); wr(0,symaddr("ctl")+2,6); wr(0,symaddr("ctl")+3,6); wr(0,symaddr("menu_sel"),getenv("MSEL")?atoi(getenv("MSEL")):0); wr(0,A_TI,trk); wr(0,symaddr("difficulty"),getenv("DIFF")?atoi(getenv("DIFF")):0); }
      if(frames>=sf && frames<=sf+2) padval=0x80;
      if(getenv("PADDWN")&&frames>=20&&frames<=22) padval=0x04;
      if(getenv("PADRGT")&&frames>=10&&frames<40&&((frames-10)/3)%2==0&&(frames-10)%3==0+0) padval=0x01;
      if(getenv("PADRGT")&&frames==45) printf("ctl %d %d %d %d\n",rd(0,symaddr("ctl")),rd(0,symaddr("ctl")+1),rd(0,symaddr("ctl")+2),rd(0,symaddr("ctl")+3));
      if(getenv("ONL")){ int o=atoi(getenv("ONL")); if(frames>=o&&frames<=o+2) padval=0x04; if(frames>=o+20&&frames<=o+22) padval=0x01; if(frames==o+15) dump("build/online2.ppm"); if(frames==o+40) dump("build/online3.ppm"); }
      if(getenv("PADDWN")&&frames==60) dump("build/online.ppm");                       // START
      if(frames==sf+3) startedrace=1;
      int r0=sf+20;
      if(getenv("SKIDPOKE") && startedrace && frames>r0+5) { wr(0,symaddr("snd_skid"),5); if(frames<r0+12) printf("SK f%d now %d lt %d\n",frames,rd(0,symaddr("snd_skid")),rd(0,symaddr("lt_s"))); }
      if(startedrace && mode==3 && frames==r0+1){ pk(symaddr("boost_cnt"),3); }
      if(startedrace && mode==3 && frames>=r0+10 && frames%10==0) printf("f%d pos(%d,%d) spd %d boost_t %d cnt %d\n",frames-r0,rd(0,A_X+1),rd(0,A_Y+1),rd(0,A_S),rd(0,symaddr("boost_t")),rd(0,symaddr("boost_cnt")));
      if(startedrace && (mode==1||mode==2) && frames>=r0 && (frames-r0)%15==0) printf("m%d f%d hd %d spd %d dir %d\n",mode,frames-r0,rd(0,A_H),rd(0,A_S),rd(0,symaddr("dir")));
      if(startedrace && mode==5 && frames>r0 && frames<r0+70 && frames%3==0 && frames>r0+30){ unsigned P=symaddr("sl_prev"); printf("f%d pos(%d,%d) armed %d prev %d cx %d cy %d ns %d nc %d lastp %d\n",frames-r0,rd(0,A_X+1),rd(0,A_Y+1),rd(0,symaddr("lap_armed")),(short)(rd(0,P)|(rd(0,P+1)<<8)),rd(0,symaddr("sl_cx")),rd(0,symaddr("sl_cy")),rd(0,symaddr("sl_ns")),rd(0,symaddr("sl_nc")),rd(0,A_LP)); }
      if(startedrace && mode==5 && frames==r0+3){ /* POKE */ unsigned L_=symaddr("lap_tenths"); pk(L_,0x2C); pk(L_+1,0x01); pk(A_LP,200); }
      if(startedrace && mode==6 && !getenv("NOBP") && frames==r0+3){ pk(symaddr("boost_cnt"),3); wr(0,symaddr("hud_dirty"),1); }
      if(startedrace && mode==6 && frames>=r0){ /* CPU cars: idle player, sample positions */
        unsigned CT=symaddr("cpu_t"); int rf=frames-r0;
        for(int k=0;k<3;k++){ unsigned b=CT+(k+1)*34; int cx=rd(0,b+1), cy=rd(0,b+3);
          int gb=(rd(0,0xD800+cy*32+(cx>>3))>>(7-(cx&7)))&1, wb=(rd(0,0xC000+cy*32+(cx>>3))>>(7-(cx&7)))&1;
          if(!gb||wb) cpu_bad[k]++; }
        { static int ovl=0,tot=0; int px[4],py[4]; px[0]=rd(0,A_X+1); py[0]=rd(0,A_Y+1); for(int k=0;k<3;k++){ px[k+1]=rd(0,CT+(k+1)*34+1); py[k+1]=rd(0,CT+(k+1)*34+3);} for(int a=0;a<4;a++)for(int b=a+1;b<4;b++) if(abs(px[a]-px[b])<9&&abs(py[a]-py[b])<5) ovl++; tot++; if(rf==2790) printf("overlap pair-frames %d of %d frames\n",ovl,tot); }
        if(rf%250==0||rf==3){ char fn[64]; sprintf(fn,"build/cpu_%04d.ppm",rf); dump(fn); }
        if(rf==0){ printf("sl_x0 %d.%d sl_y0 %d.%d sl_h %d\n",rd(0,symaddr("sl_x0")+1),rd(0,symaddr("sl_x0")),rd(0,symaddr("sl_y0")+1),rd(0,symaddr("sl_y0")),rd(0,symaddr("sl_h"))); for(int k=0;k<4;k++) printf("slot%d lat %d (%d,%d) hd %d mode %d\n",k,rd(0,CT+k*34+8),rd(0,CT+k*34+1),rd(0,CT+k*34+3),rd(0,CT+k*34+4),rd(0,CT+k*34+23)); } if(rf%5==0){ for(int k=0;k<3;k++){ unsigned b=CT+(k+1)*34; printf("f%4d car%d pos(%3d,%3d) hd %2d spd %3d wp %3d lapf %4d best %5d bad %d bst %d t %d r %d %d\n",rf,k+1,rd(0,b+1),rd(0,b+3),rd(0,b+4),rd(0,b+5),rd(0,b+6),rd(0,b+12)|(rd(0,b+13)<<8),rd(0,b+14)|(rd(0,b+15)<<8),cpu_bad[k],rd(0,b+21),rd(0,b+22),rd(0,b+30),rd(0,b+31)); } }
      }
      if(getenv("CTL2")&&frames==2) wr(0,symaddr("ctl")+atoi(getenv("CTL2")),1);
      if(getenv("DUMPF")&&frames==atoi(getenv("DUMPF"))) dump("build/dumpf.ppm");
      if(startedrace && (mode==8||mode==9)){ int rf=frames-r0; unsigned LS=symaddr("lt_s"),PH=symaddr("phase");
        static int lastls=-1, gcount=0, shot=0; int ph=rd(0,PH), ls=rd(0,LS);
        if(ph==0 && rf%10==0){ unsigned CD=symaddr("cd_s"); int cd=rd(0,CD)|(rd(0,CD+1)<<8); if(cd>1&&cd<179){ wr(0,CD,1); wr(0,CD+1,0); } }
        if((rf%60)<6) padval=0x10;
        if(mode==9&&getenv("CHO")){ if(cf<0&&cho_hit) cf=frames;
          if(cf>=0){ int d=frames-cf; padval=0; if(d>=10&&d<=12) padval=0x04; if(getenv("CHORGT")&&d>=40&&d<=42) padval=0x01; if(getenv("CHORGT")&&d>=140&&d<=142) padval=0x02; if(d==20) dump("build/choice1.ppm"); if(d>=30&&d<=32&&!getenv("CHO1")) padval=0x04; if(d==40) dump("build/choice2.ppm"); if(d>=50&&d<=52&&!getenv("CHOWAIT")) padval=0x80; if(getenv("CHOWAIT")&&d%25==0&&d<=300){ char fn[64]; sprintf(fn,"build/scr_%03d.ppm",d); dump(fn); } if(d==60) dump("build/choice3.ppm"); if(d==70) dump("build/choice_s1.ppm"); if(d==110) dump("build/choice_s2.ppm"); if(d==120) printf("AFTER CHOICE: phase %d track_idx %d nxt %d\n",rd(0,symaddr("phase")),rd(0,symaddr("track_idx")),rd(0,symaddr("nxt_flag"))); } }
        if(ph==1 && ls!=lastls){ lastls=ls; char fn[64]; sprintf(fn,"build/rc_ls%d.ppm",ls); dump(fn); printf("rf %d lt_s %d\n",rf,ls); }
        if(mode==9 && ph==1 && ls==0){ static int g9=0, did1=0, did2=0, did3=0; g9++; unsigned CT=symaddr("cpu_t");
          if(g9>=100&&!did1){ did1=1; for(int k=1;k<4;k++) wr(0,CT+k*34+24,6); }
          if(g9>=140&&!did2){ did2=1; dump("build/fin_a.ppm"); }
          if(g9>=160&&!did3){ did3=1; pk(symaddr("laps_done"),6); pk(symaddr("best_tenths"),147); pk(symaddr("best_tenths")+1,0); }
          if(g9>=170 && g9%3==0){ char fn[64]; sprintf(fn,"build/fr_%03d.ppm",g9); dump(fn); } }
        if(mode==8 && ph==1 && ls==0){ gcount++; if(gcount==40){ unsigned L_=symaddr("lap_tenths"); pk(L_,0x2C); pk(L_+1,0x01); pk(A_LP,200); } { static int fl=0; unsigned LS=symaddr("lap_show"); int v=rd(0,LS); if(v&&!fl) fl=gcount; if(fl&&gcount==fl+20) dump("build/lapflash.ppm"); if(fl&&gcount==fl+v+0&&0){} if(fl&&gcount==fl+160) dump("build/lapflash3.ppm"); } if(gcount==300) dump("build/lapflash2.ppm"); if(gcount==100){ dump("build/rc_race.ppm"); } if(gcount==400){ wr(0,symaddr("race_over"),1); } if(gcount==415) dump("build/res1.ppm"); }
      }
      if(startedrace && mode==7 && frames>=r0){ /* residue check: spin heading in place, compare screen with clean copy outside the car box */
        int cx=rd(0,A_X+1), cy=rd(0,A_Y+1), hd=rd(0,A_H); int bad=0,bx=0,by=0;
        for(int y=12;y<192;y++) for(int x=0;x<256;x++){ if(x>=cx-8&&x<cx+8&&y>=cy-12&&y<cy+4) continue; if(ram[18*8192+y*256+x]!=ram[100*8192+y*256+x]){ if(!bad){bx=x;by=y;} bad++; } }
        if(bad&&frames>r0+2) printf("f%d hd %d car(%d,%d) residue %d first(%d,%d)\n",frames-r0,hd,cx,cy,bad,bx,by);
        if((frames-r0)%3==2){ char fn[64]; sprintf(fn,"build/hd_%02d.ppm",hd); dump(fn);} pk(A_H,((frames-r0)/3)&31); if(getenv("PX")){ int px=atoi(getenv("PX")); wr(0,A_X+1,px); } pk(A_S,0); pk(A_X,0x80); pk(A_X+1,169); pk(A_Y,0x80); pk(A_Y+1,64); }
      if(startedrace && mode==4 && frames>=r0 && frames<r0+accel_frames){ /* BOT: follow the progress map, ray-marching so fences are respected */
        int cx=rd(0,A_X+1), cy=rd(0,A_Y+1), hd=rd(0,A_H), cur=rd(0,A_LP); int sp=rd(0,A_S); int best=-99999, bs=0;
        for(int st=-3;st<=3;st++){ int h2=(hd+st+32)&31; double a=h2*2*M_PI/32; double fx=cx,fy=cy; int lastq=-1,run=0;
          for(int dist=2;dist<=30;dist+=2){ int px=(int)(cx+cos(a)*dist), py=(int)(cy+sin(a)*dist*0.5);
            int bad=(px<2||px>253||py<2||py>190);
            if(!bad){ int wb=(rd(0,0xC000+py*32+(px>>3))>>(7-(px&7)))&1, gb=(rd(0,0xD800+py*32+(px>>3))>>(7-(px&7)))&1; int wl=(rd(0,0xC000+py*32+((px-1)>>3))>>(7-((px-1)&7)))&1, wr_=(rd(0,0xC000+py*32+((px+1)>>3))>>(7-((px+1)&7)))&1;
              if(wb||wl||wr_||!gb) bad=1; }
            if(bad) break; int q=rd(0,0xF000+(py>>2)*64+(px>>2)); if(q!=255){ lastq=q; if(cur>40&&q<10) lastq+=90; } run=dist; }
          int sc=(lastq<0?-50:lastq)*3+run; sc-=abs(st)*3; if(run<8) sc-=60; if(sc>best){best=sc;bs=st;} }
        padval=(sp<100?0x10:0)|(bs<0?0x02:(bs>0?0x01:0)); }
      else if(startedrace && mode<8 && frames>=r0 && frames<r0+accel_frames) padval=(mode==2?0x04:0x10)|(((mode==1||mode==2)&&frames>r0+30)?0x02:0)|((mode==3&&frames>r0+30)?0x08:0);
      if(getenv("TWOP")&&startedrace){ int d=frames-r0; pad2=(d>=0)?(0x10|((d/20)%2?0x02:0x01)):0; padval=(d>=0)?0x10:0; if(d>=0&&frames%10==0 && frames!=lastp2){ lastp2=frames; unsigned ct=symaddr("cpu_t"); printf("ctx %02X%02X %02X%02X ",rd(0,ct+27),rd(0,ct+26),rd(0,ct+34+27),rd(0,ct+34+26)); printf("f%d heads %d %d  speeds %d %d\n",frames,rd(0,ct+4),rd(0,ct+34+4),rd(0,ct+5),rd(0,ct+34+5)); } }
      if(getenv("QUITT")){ int q=atoi(getenv("QUITT")); int w=atoi(getenv("QUITW")?getenv("QUITW"):"1"); int d=frames-q; if(d>=0&&d<=2) padval=0x80; else if(d>=20&&d<=22&&w>=1) padval=0x04; else if(d>=40&&d<=42&&w>=2) padval=0x80; else if(d>=0&&d<60) padval=0; }
      if(startedrace && frames==r0-1) { sx=ram[(4*8192)+(A_X+1-0x8000)]; sy=ram[(4*8192)+(A_Y+1-0x8000)]; }
      if(startedrace && frames==r0+accel_frames) { ex=ram[(4*8192)+(A_X+1-0x8000)]; ey=ram[(4*8192)+(A_Y+1-0x8000)]; es=ram[(4*8192)+(A_S-0x8000)]; ehd=ram[(4*8192)+(A_H-0x8000)]; elp=ram[(4*8192)+(A_LP-0x8000)]; }
    }
  }
  if(getenv("HSD")){ for(int tr=0;tr<24;tr++){ int n=0; for(int e=0;e<10;e++){ uint8_t*q=&ram[80*8192+tr*80+e*8]; if(!(q[5]==0xE7&&q[6]==3)) n++; } if(n) printf("track %d: %d real\n",tr+1,n); } uint8_t*q=&ram[80*8192+4*80]; for(int i=0;i<24;i++) printf("%02X ",q[i]); printf("\n"); }
  if(getenv("HS")){ for(int e=0;e<3;e++){ uint8_t*q=&ram[80*8192+e*8]; printf("hs[%d] %.5s %d\n",e,q,q[5]|(q[6]<<8)); } }
  if(getenv("PROF")){ FILE*pf=fopen("build/prof.txt","w"); for(int i=0;i<65536;i++) if(prof[i]) fprintf(pf,"%04X %lu\n",i,prof[i]); fclose(pf); }
  if(getenv("WATCH")){ for(int q=0;q<8;q++) printf("watch%d=%d ",q,wcnt[q]); printf("\n"); }
  printf("minsp=%04X\n",minsp);
  if(getenv("FINALPC")) printf("final pc=%04X sp=%04X\n",z.pc,z.sp);
  if(wn) printf("work/frame avg %lu max %lu cycles (28MHz budget 560000) over %d frames\n",wsum/wn,wmax,wn);
  { unsigned B_=symaddr("best_tenths"); printf("best_tenths=%d ", rd(0,B_)|(rd(0,B_+1)<<8)); }
  dump(shot?shot:"build/test_race.ppm");
  printf("track %2d start(%3d,%3d) head %2d -> after %d frames (%3d,%3d) speed %3d lastp %3d | pal wall=%02X road=%02X | AY r0=%d r8=%d\n",trk+1,sx,sy,ehd,accel_frames,ex,ey,es,elp,pal[1],pal[2],ay[0],ay[8]);
  return 0; }
