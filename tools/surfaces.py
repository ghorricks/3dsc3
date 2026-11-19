# Surfaces: TRACK (dark grey), DIRT, ICE, SAND - assigned to the tracks in that order, repeating (track n -> (n-1)%4).
# Each track bank carries a 256-byte block at $3F00 (mapped at $FF00 in game):
#   $FF00 skid speed  (a turn at or above this speed with the accelerator held makes the car skid; 250 = top speed)
#   $FF01 n, then n x (palette index, 9-bit byte 1, blue LSB)  from $FF02 (max 20)
#   $FF28 infield bitmap: bit k (k = 219..0 = tr_n-1 of each tree try) set when that try lies in an infield (28 bytes)
#   $FF44 tyre-stack sprite spans (dy,dx,len,colour)... $7F      (stood in every internal area)
#   $FF84 outside scenery spans (trees / boulders / cacti / pines) ... $7F
NAMES=["TRACK","DIRT","ICE","SAND"]
def surf_of(n): return NAMES[(n-1)%4]
def p9(rgb):
    r,g,b=[int(v)>>5 for v in rgb]; return ((r<<5)|(g<<2)|(b>>1), b&1)
def c332(rgb): r,g,b=rgb; return ((int(r)>>5)<<5)|((int(g)>>5)<<2)|(int(b)>>6)
TYRE=[(20,20,24),(78,78,86),(120,120,128)]          # idx 36 black, 37 grey, 38 light
SURF={
 "TRACK":dict(road=(73,73,85),spk=[(62,62,78),(92,92,100),(62,62,78)],ground=(0,182,0),fol=[(0,109,0),(0,255,0),(109,36,0)],skid=250,out="tree"),
 "DIRT": dict(road=(145,72,0),spk=[(109,73,0),(182,109,85),(109,73,0)],ground=(96,64,36),fol=[(92,82,72),(130,118,104),(109,36,0)],skid=234,out="boulder"),
 "ICE":  dict(road=(164,186,216),spk=[(150,172,204),(186,206,232),(150,172,204)],ground=(152,170,200),fol=[(14,70,56),(30,110,80),(80,52,36)],skid=218,out="pine"),
 "SAND": dict(road=(214,190,120),spk=[(200,176,108),(228,206,142),(200,176,108)],ground=(150,128,66),fol=[(20,110,40),(70,170,70),(109,36,0)],skid=250,out="cactus"),
}
def road8(name): return c332(SURF[name]["road"])
def _tyres():
    s=[]
    for t in range(3):
        y0=-3-3*t
        s+=[(y0,-2,1,37),(y0,-1,4,38),(y0,3,1,37),(y0+1,-2,6,36),(y0+2,-2,6,36)]
    return s
def _tree():
    return [(-9,0,1,34),(-9,1,1,33),(-8,-1,2,34),(-8,1,2,33),(-7,-2,3,34),(-7,1,3,33),(-6,-2,3,34),(-6,1,3,33),(-5,-2,3,34),(-5,1,3,33),(-4,-2,3,34),(-4,1,3,33),(-3,0,2,35),(-2,0,2,35),(-1,0,2,35)]
def _boulder():
    return [(-5,1,2,34),(-4,0,4,34),(-3,-1,6,34),(-2,-1,6,33),(-1,0,4,33)]
def _cactus():
    s=[]
    for dy in range(-9,0): s+=[(dy,0,1,34),(dy,1,1,33)]
    s+=[(-4,-3,3,33)]+[(dy,-3,1,34) for dy in (-8,-7,-6,-5)]
    s+=[(-4,2,1,33),(-5,2,1,33)]+[(dy,3,1,33) for dy in (-8,-7,-6,-5)]
    return s
def _pine():
    s=[]; W=[0,1,1,2,2,3,3]
    for k in range(7):
        dy=-9+k; w=W[k]; s+=[(dy,-w,w+1,34),(dy,1,w+1,33)]
    for k in range(7):
        dy=-9+k; w=W[k]
        if k in (0,1,3,5): s+=[(dy,0,2,3)]
        else: s+=[(dy,-w,1,3),(dy,1+w,1,3)]
    s+=[(-2,0,2,35),(-1,0,2,35)]
    return s
OUT={"tree":_tree,"boulder":_boulder,"cactus":_cactus,"pine":_pine}
def spans(l): return bytes(sum(([v&255 for v in sp] for sp in l),[]))+b"\x7f"
def block(name,inf):
    S=SURF[name]; b=bytearray(256)
    b[0]=S["skid"]
    ent=[(2,)+p9(S["road"]),(12,p9(S["road"])[0],p9(S["road"])[1]^1),(32,)+p9(S["ground"])]
    ent+=[(33+i,)+p9(S["fol"][i]) for i in range(3)]
    ent+=[(36+i,)+p9(TYRE[i]) for i in range(3)]
    ent+=[(44+i,)+p9(S["spk"][i]) for i in range(3)]
    b[1]=len(ent); b[0x27]=c332(S["ground"])      # $FF27: the border colour (the surround, 8-bit)
    for i,e in enumerate(ent): b[2+3*i:5+3*i]=bytes(e)
    for k,v in enumerate(inf):
        if v: b[0x28+(k>>3)]|=1<<(k&7)
    t=spans(_tyres()); assert 0x44+len(t)<=0x84; b[0x44:0x44+len(t)]=t
    o=spans(OUT[S["out"]]()); assert 0x84+len(o)<=256,(name,len(o)); b[0x84:0x84+len(o)]=o
    assert 2+3*len(ent)<=0x28
    return bytes(b)
