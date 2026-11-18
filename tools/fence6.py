# Track 6 fences as clean straight segments (shallow walls ~ -1/7.4 slope, steep walls ~ 2:1) fitted to the original's wall mask.
# Rounded corners of the original become short chamfers.
import numpy as np
from PIL import Image
SS=-0.1345      # shallow: y = c + SS*x   (c fitted to the bottom rail)
ST=0.497        # steep:   x = c + ST*y   (c fitted to the right edge)
def _mask():
    m=np.array(Image.open("/home/claude/stockcar/orig/track6_median.png"))
    w=(m==(205,205,205)).all(2); w[:9]=False; w[172:,:22]=False; w[:30,100:112]=False
    return w
def _edges(w):
    below=np.zeros_like(w); below[:-1]=w[1:]
    right=np.zeros_like(w); right[:,:-1]=w[:,1:]
    return w&~below, w&~right
def fit(edge,kind,c0,rng,lo,hi):
    H,W=edge.shape; res=[]
    for c in np.arange(c0-rng,c0+rng+0.01,0.25):
        n=0
        for t in range(lo,hi+1):
            if kind=='s':
                y=int(round(c+SS*t)); x=t
            else:
                x=int(round(c+ST*t)); y=t
            if 0<=x<W and 0<=y<H and edge[y,x]: n+=1
        res.append((c,n))
    m=max(n for c,n in res); ok=[c for c,n in res if n>=0.8*m]
    return max(ok)                                   # lowest / rightmost rail that is well covered
def isect(a,b):
    s,t=(a,b) if a[0]=='s' else (b,a)
    x=(t[1]+ST*s[1])/(1-ST*SS); y=s[1]+SS*x
    return x,y
def _build():
    eb,er=_edges(_mask())
    L={}
    L['T']=('s',fit(eb,'s',47,6,110,180))        # outer top
    L['U']=('s',fit(eb,'s',206,8,70,230))        # outer bottom
    L['a']=('s',fit(eb,'s',73.7,3,60,149))
    L['b']=('s',fit(eb,'s',99.3,3,24,114))
    L['c']=('s',fit(eb,'s',124.9,3,80,174))
    L['d']=('s',fit(eb,'s',151.2,3,44,141))
    L['e']=('s',fit(eb,'s',177.1,3,104,199))
    L['R']=('t',fit(er,'t',183,10,60,130))        # outer right
    L['Lf']=('t',fit(er,'t',-27,10,70,160))        # outer left
    L['I']=('t',fit(er,'t',132,4,58,142))        # inner steep
    return L
LINES=None
def fence6(H=192,W=256):
    global LINES
    if LINES is None: LINES=_build()
    P=lambda a,b: isect(LINES[a],LINES[b])
    def at_x(n,x): return x, LINES[n][1]+SS*x
    def at_y(n,y): return LINES[n][1]+ST*y, y
    ch=12                                           # chamfer size at the rounded corners
    TL=P('T','Lf'); TR=P('T','R'); BR=P('U','R'); BL=P('U','Lf')
    def cut(c,p,q,d):                               # point d pixels from corner c towards p
        v=np.array(p)-np.array(c); v=v/np.hypot(*v); return tuple(np.array(c)+v*d)
    segs=[]
    # outer loop with chamfered corners
    tl_t=cut(TL,TR,TL,ch); tl_l=cut(TL,BL,TL,ch)
    tr_t=cut(TR,TL,TR,ch); tr_r=cut(TR,BR,TR,ch)
    br_r=cut(BR,TR,BR,ch); br_b=cut(BR,BL,BR,ch)
    bl_b=cut(BL,BR,BL,ch); bl_l=cut(BL,TL,BL,ch)
    segs+= [(tl_t,tr_t),(tr_t,tr_r),(tr_r,br_r),(br_r,br_b),(br_b,bl_b),(bl_b,bl_l),(bl_l,tl_l),(tl_l,tl_t)]
    # inner walls
    IA=P('a','I'); IE=P('e','I')
    ia_t=cut(IA,at_x('a',55),IA,8); ia_s=cut(IA,IE,IA,8)
    segs+= [(at_x('a',55),ia_t),(ia_t,ia_s),(ia_s,IE),(IE,at_x('e',102))]
    segs+= [(P('b','Lf'),at_x('b',119)),(P('d','Lf'),at_x('d',145)),(at_x('c',78),P('c','I'))]
    return segs
def mask6(H=192,W=256):
    b=np.zeros((H,W),bool)
    for (x0,y0),(x1,y1) in fence6.__wrapped__() if False else fence6():
        n=int(max(abs(x1-x0),abs(y1-y0)))+1
        for i in range(n+1):
            t=i/n; x=int(round(x0+(x1-x0)*t)); y=int(round(y0+(y1-y0)*t))
            if 0<=x<W and 0<=y<H: b[y,x]=True
    return b
if __name__=="__main__":
    fence6(); print(LINES)
    b=mask6()
    from PIL import Image
    m=np.array(Image.open("/home/claude/stockcar/orig/track6_median.png")).copy()
    img=(m*0.35).astype(np.uint8); img[b]=(255,40,40)
    Image.fromarray(img).resize((1024,768),Image.NEAREST).save("/home/claude/stockcar/build/f6.png")
