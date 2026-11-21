# Tiny LZSS for the title picture: one stream per 16 KB Layer 2 bank (a match never leaves its bank).
# control byte = 8 flags, MSB first (1 = literal byte, 0 = match); match = 2 bytes: offset low, (offset high nibble << 4) | (length - 3); offset 1..4095, length 3..18
import sys
def pack(bank):
    n=len(bank); out=bytearray(); i=0; flags=[]; items=[]
    heads={}
    def key(i): return bytes(bank[i:i+3])
    while i<n:
        best=(0,0)
        if i+3<=n:
            for j in reversed(heads.get(key(i),[])[-64:]):
                off=i-j
                if off>4095: break
                l=0
                while i+l<n and l<18 and bank[j+l]==bank[i+l]: l+=1
                if l>best[0]: best=(l,off)
                if l==18: break
        l,off=best
        if l>=3:
            items.append((0,bytes([off&255,((off>>8)<<4)|(l-3)])))
            adv=l
        else:
            items.append((1,bytes([bank[i]]))); adv=1
        for k in range(i,min(i+adv,n-2)): heads.setdefault(key(k),[]).append(k)
        i+=adv
    for g in range(0,len(items),8):
        grp=items[g:g+8]; f=0
        for t in range(8):
            f<<=1
            if t<len(grp): f|=grp[t][0]
            else: f|=1                       # padding flags are never read (the decoder stops at the bank end)
        out.append(f)
        for _,b in grp: out+=b
    return bytes(out)
def unpack(stream,size=16384):
    out=bytearray(); p=0; buf=0x80
    def bit():
        nonlocal buf,p
        buf<<=1; c=buf>>8; buf&=255
        if buf==0 and c:                      # sentinel consumed: load the next flag byte
            nb=stream[p]; p+=1; v=(nb<<1)|1; c=v>>8; buf=v&255
        return c
    while len(out)<size:
        if bit(): out.append(stream[p]); p+=1
        else:
            lo=stream[p]; hi=stream[p+1]; p+=2
            off=lo|((hi>>4)<<8); l=(hi&15)+3
            for _ in range(l): out.append(out[-off])
    return bytes(out)
def build(src,outprefix):
    d=open(src,'rb').read()[:49152]; ss=[]
    for k in range(3):
        b=d[k*16384:(k+1)*16384]; z=pack(b); assert unpack(z)==b,"roundtrip"; ss.append(z)
    assert len(ss[0])+len(ss[1])<=8192 and len(ss[2])<=8192
    open(outprefix+"_a.lz","wb").write(ss[0]+ss[1])      # page 1: banks 0 and 1, back to back
    open(outprefix+"_b.lz","wb").write(ss[2])            # page 2: bank 2
    return [len(x) for x in ss]
if __name__=="__main__": print(build(sys.argv[1],sys.argv[2]))

def build6(src,outprefix):
    """full-colour title: six 8 KB pieces (32 rows each), packed two to a page; a table gives each piece's page index (0,1,2 = pages 24,25,30) and address"""
    d=open(src,'rb').read()[:49152]
    z=[pack(d[k*8192:(k+1)*8192]) for k in range(6)]
    for k in range(6): assert unpack(z[k],8192)==d[k*8192:(k+1)*8192]
    plan=[[3,0],[4,2],[1,5]]; tab=[0]*6; names="abc"
    for p,ks in enumerate(plan):
        blob=b""
        for k in ks:
            w=(p<<13)|len(blob); tab[k]=w; blob+=z[k]
        assert len(blob)<=8192,(p,len(blob))
        open(outprefix+"_%s.lz"%names[p],"wb").write(blob)
    open(outprefix+"_tab.bin","wb").write(b"".join(bytes([w&255,w>>8]) for w in tab))
    return [len(x) for x in z]
