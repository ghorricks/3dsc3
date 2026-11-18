import sys,os,struct
def dec(d,n=None):
    o=bytearray();i=0
    while i<len(d):
        if d[i]==0xED and i+3<len(d) and d[i+1]==0xED:
            o+=bytes([d[i+3]])*d[i+2]; i+=4
        else: o.append(d[i]); i+=1
    return bytes(o)
def load(fn,out):
    b=open(fn,'rb').read(); h=b[:30]; pc=h[6]|h[7]<<8
    mem=bytearray(65536); f12=h[12] if h[12]!=255 else 1
    if pc: # v1
        body=b[30:]
        if f12&0x20:
            e=body.find(b'\x00\xed\xed\x00'); body=dec(body[:e] if e>=0 else body)
        mem[0x4000:0x4000+len(body[:49152])]=body[:49152]; ver=1
    else:
        el=b[30]|b[31]<<8; pc=b[32]|b[33]<<8; ver=2 if el==23 else 3
        hw=b[34]; p=32+el
        while p<len(b):
            ln=b[p]|b[p+1]<<8; pg=b[p+2]; p+=3
            if ln==0xFFFF: d=b[p:p+16384]; p+=16384
            else: d=dec(b[p:p+ln]); p+=ln
            base={8:0x4000,4:0x8000,5:0xC000}.get(pg)
            if base is not None and ver and hw in(0,1,2,3) or (base is not None): mem[base:base+16384]=d[:16384]
    os.makedirs(out+'/orig',exist_ok=True)
    open(out+'/orig/ram.bin','wb').write(mem)
    r=[h[0],h[1],h[3],h[2],h[14] if 0 else h[14],h[13],h[5],h[4],pc,h[8]|h[9]<<8,h[10],h[25]|h[26]<<8,h[23]|h[24]<<8]
    # a f b c d e h l pc sp i ix iy ; shadow after
    r+=[h[21],h[22],h[16],h[15],h[18],h[17],h[20],h[19],h[27],h[28],h[29]&3]
    open(out+'/orig/regs.txt','w').write(' '.join(map(str,r)))
    print(fn.split('/')[-1][-12:],'ver',ver,'pc %04X sp %04X iff %d im %d'%(pc,r[9],h[27],h[29]&3))
S='/mnt/user-data/attachments/75bc9376-5fde-5ee5-97ba-f2e8c55057d5/'
import glob
for i,f in enumerate(sorted(glob.glob(S+'*.z80'))): load(f,'/tmp/claude-0/-home-claude/75bc9376-5fde-5ee5-97ba-f2e8c55057d5/scratchpad/snaps/s%d'%i); print(i,f)
