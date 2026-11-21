import os
# Builds all data: clean track banks (base fence plane + ground plane + progress map), meta, car model, speed tables, font.
import numpy as np, json, math, sys, cv2
from collections import deque
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi
sys.path.insert(0,"/home/claude/stockcar/tools")
from clean import *
import clean as C
B="/home/claude/stockcar/build/"; CELL=4; CW,CH=64,48
VEC={11,9,12,10,13,14}; VEC2={9,12,10,13}
from vecfence import widen_zone
# track 11: the two long diagonal stretches are narrow: grow them by 5 px into the grass (the vertical stretches stay as they are)
def _user_lane(L):                      # track 11 is drawn by hand: tools/track11_shape.png (yellow lane on green, 4x the playfield)
    _a=np.array(Image.open(os.path.join(os.path.dirname(os.path.abspath(__file__)),"track11_shape.png")).convert("RGB"))[2::4,2::4]
    return (_a[:,:,0]>120)&(_a[:,:,2]<80)
def _lane14(L):                          # track 14: the lane of the original (wide, rounded bends), kept as a mask: tools/lane14.npy
    from skimage.morphology import disk as _dk
    L0=np.load(os.path.join(os.path.dirname(os.path.abspath(__file__)),"lane14.npy"))
    L0=ndi.binary_opening(ndi.binary_closing(np.pad(L0,8),structure=_dk(3)),structure=_dk(2))[8:-8,8:-8]      # tidy the ragged notch behind the grid
    Z=np.zeros(L0.shape,np.uint8)
    cv2.fillPoly(Z,[np.array([(0,60),(33,79),(88,109),(88,121),(0,121)],np.int32)],1)                          # the start straight: wider, taken from the grass on its outer (lower-left) side
    G=ndi.binary_dilation(L0,structure=_dk(6))&(Z>0)
    return ndi.binary_opening(np.pad(L0|G,8),structure=_dk(3))[8:-8,8:-8]|L0
WIDEN={11:_user_lane,14:_lane14}
EXACT=set(range(1,28))
INFILL=set()
CLOCKWISE={5,6,7,8,12,13,14}          # tracks the original runs clockwise round the screen
PATHS={}
info=json.load(open(B+"tracks.json"))
NH=32
HEAD=[(math.cos(a*2*math.pi/NH),math.sin(a*2*math.pi/NH)*0.5) for a in range(NH)]   # iso: y squashed
def c332(r,g,b): return ((int(r)>>5)<<5)|((int(g)>>5)<<2)|(int(b)>>6)
ZXRGB=[(0,0,0),(0,0,255),(255,0,0),(255,0,255),(0,255,0),(0,255,255),(255,255,0),(255,255,255)]
SURF={"tarmac":0x49,"sand":0xB4,"gravel":0xB6,"dirt":0x88}
TRACK_YOFF_=0
import surfaces as SFX                    # TRACK / DIRT / ICE / SAND, assigned 1,2,3,4 then repeating (tools/surfaces.py)
SURFRGB={0x49:(70,70,70),0xB4:(182,182,0),0xB6:(180,180,180),0x88:(145,72,0)}
CROSS=np.array([[0,1,0],[1,1,1],[0,1,0]],bool)
TWOLEG={20:(177,180)}                     # (y,x) of a free point behind the start: serpentine lap, farthest point is mid-lap
VIA={16:[(38,85),(21,66),(36,44),(68,31),(105,27),(136,42),(174,37),(206,50),(231,67),(214,89),(230,110),(216,130),(187,146),(159,161),(128,175),(89,173),(59,159),(30,152),(17,138),(24,124),(42,123),(62,130),(95,136),(125,141),(150,130),(172,112),(160,104),(148,104),(135,107),(110,103),(92,101)],23:[(150,34),(196,57),(208,100),(221,124),(233,150),(216,164),(175,167),(127,171),(60,152),(35,110),(25,72),(50,48),(80,44)],11:[(150,177),(100,160),(60,140),(37,125),(32,108),(37,100),(80,100),(127,98),(180,99),(218,99),(224,90),(200,70),(150,45),(112,23),(60,23),(35,30),(30,45),(40,58),(80,61),(112,61),(120,80),(127,98),(135,120),(143,138),(190,138),(215,145),(224,155),(215,172),(200,177)],10:[(100,28),(36,50),(128,100),(222,150),(128,176),(36,150),(128,100),(222,50),(185,31)]}   # figure-8: the lap is not the farthest-away route
def make_path(dist,solid,start,H,W,maxn=250,wide=False,via=None,twoleg=None):
    """lane centreline = least-cost route start -> far end of the lap, cost grows near walls; sampled every ~6 px, smoothed"""
    from skimage.graph import route_through_array
    sx,sy=start
    free=dist>=0
    clr=ndi.distance_transform_edt(~solid)
    ok=free&(clr>=(4.5 if wide else 2.5))
    if ok.sum()<free.sum()*0.2: ok=free&(clr>=1.5)
    cost=np.where(ok,1.0+(400.0 if wide else 60.0)/(clr+1.0)**2,np.where(free,2000.0,1e9))   # narrow-but-reachable pixels are expensive, never the blocked strip behind the line
    dm=np.where(ok,dist,-1); ey,ex=np.unravel_index(int(np.argmax(dm)),dm.shape)
    if via:
        route=[]; cur=(sy,sx)
        for (vx,vy) in via:
            r,_=route_through_array(cost,cur,(vy,vx),fully_connected=True,geometric=True); route+=r[1:] if route else r; cur=(vy,vx)
    else:
        route,_=route_through_array(cost,(sy,sx),(ey,ex),fully_connected=True,geometric=True)
        if twoleg:   # second leg: from the far end back to the rear of the start, never re-using the first leg's lanes
            c2=cost.copy(); used=np.zeros(cost.shape,bool)
            for (yy,xx) in route: used[yy,xx]=True
            used=ndi.binary_dilation(used,iterations=9)
            for (yy,xx) in route[-14:]: used[max(0,yy-12):yy+13,max(0,xx-12):xx+13]=False
            c2[used]=1e9
            r2,_=route_through_array(c2,(ey,ex),twoleg,fully_connected=True,geometric=True); route=list(route)+list(r2[1:])
    R=np.array(route,float)[:,::-1]                       # (x,y)
    seg=np.hypot(np.diff(R[:,0]),np.diff(R[:,1])*2); cum=np.concatenate([[0],np.cumsum(seg)])
    step=max(6.0,cum[-1]/maxn)
    t=np.arange(0,cum[-1],step); P=np.stack([np.interp(t,cum,R[:,0]),np.interp(t,cum,R[:,1])],1)
    for _ in range(2):
        Q=P.copy(); Q[1:-1]=(P[:-2]+2*P[1:-1]+P[2:])/4; P=Q
    out=[(int(round(min(255,x))),int(round(y))) for x,y in P]
    return [p[0] for p in out],[p[1] for p in out],len(out)

meta=[]; PREV=[]
PERP_N={27:26,26:26,25:26,9:24,13:26,15:26,16:26,17:26,18:26,19:26,20:26,21:26,22:26,23:26,24:26}
for n in range(1,28):
    EX=n in EXACT; PERP=PERP_N.get(n,70)
    H,W=(192,256) if EX else (174,254); C.H,C.W=H,W
    if EX:
        raw=np.frombuffer(open(B+f"track{n:02d}x.bin","rb").read(),np.uint8).reshape(192,32)
    else:
        raw=np.frombuffer(open(B+f"track{n:02d}.bin","rb").read(),np.uint8).reshape(176,32)
    m=np.unpackbits(raw,axis=1)[:H,:W].astype(bool)
    if n in INFILL:                         # the infield fence band and grid are green in the original but are not in the wall mask: add them (the area enclosed by the outer fence)
        _a=np.array(Image.open(os.path.join(os.path.dirname(os.path.abspath(__file__)),"..","orig",f"track{n}_median.png")).convert("RGB"))
        _g=(_a[:,:,1]>150)&(_a[:,:,0]<60)&(_a[:,:,2]<60)
        _c=ndi.binary_closing(np.pad(m,6),structure=np.ones((3,3)),iterations=2)[6:-6,6:-6]
        m=m|(_g&ndi.binary_fill_holes(_c)&~_c)
    if n in (1,2,3,4,21,22) and not EX:      # flag pole in the top-right of the hex tracks: erase its columns above the fence
        m[0:44,197:254]=False
    base=base_lines(repair(vclose(remove_poles(m)))); ground,k,how=ground_k(base,tuple(info[str(n)]["start"]))
    base=drop_stray(base,ground)
    perim=ground&~ndi.binary_erosion(ground,structure=CROSS,border_value=1)
    gap=perim&~ndi.binary_dilation(base,iterations=7)
    if gap.any(): print("track",n,"fence gap pixels filled:",int(gap.sum()))
    if n<7: base=base|gap
    base=skel_prune(base)
    if EX:                                    # exact track: close tiny end-cap loops, then re-thin to 1-px lines
        from skimage.morphology import skeletonize
        _l,_k=ndi.label(~base,structure=np.ones((3,3)))
        for _i,_sl in enumerate(ndi.find_objects(_l),1):
            if (_l[_sl]==_i).sum()<=(700 if n in (21,22) else 220) and _sl[0].start>0 and _sl[1].start>0 and _sl[0].stop<H and _sl[1].stop<W: base[_l==_i]=True
        base=skeletonize(base)
        if 7<=n<=24:
            np.save(B+f'base{n}.npy',base)
            from fenceg import straighten,EDITS
            base=EDITS[n](straighten(base)); ground,k,how=ground_k(base,tuple(info[str(n)]['start']))
        if n in VEC:                          # vectorised from the faithful wall mask (tools/vecfence.py)
            from vecfence import vec_base,vec_base2
            import vecfence as _vf; _vf.CLEAN=(n>=12); _vf.ROUND=(n==14)
            base=(vec_base2(m,tuple(info[str(n)]['start']))[0] if n in VEC2 else vec_base(m,tuple(info[str(n)]['start']),widen=WIDEN.get(n))[0]); ground,k,how=ground_k(base,tuple(info[str(n)]['start']))
        if n==25:                             # designed here (tools/track25.py): the fence is already exact
            base=np.load(B+'fence25.npy'); ground,k,how=ground_k(base,tuple(info['25']['start']))
        if n in (4,5,6):                      # tracks 4, 5, 6: clean straight fences fitted to the original
            if n==4:
                from fence4 import fence4 as _f
            elif n==6:
                from fence6 import mask6 as _f
            else:
                from fence5 import fence5 as _f
            base=_f(H,W); ground,k,how=ground_k(base,tuple(info[str(n)]["start"]))
        if n==1:                              # wall tips: the original has plain pointed junctions, not loops
            from skimage.draw import line as _ln
            for (x0,y0,x1,y1) in ((192,88,220,112),(36,128,60,152)):
                base[y0:y1+1,x0:x1+1]=False
            def _ray(xa,ya,xb,sl):                # straight 2:1 isometric edge
                for x in range(min(xa,xb),max(xa,xb)+1): base[int(round(ya+(x-xa)*sl)),x]=True
            _ray(191,93,214,0.5); _ray(196,113,214,-0.5)           # right tip: both inner walls meet in a point
            rr,cc=_ln(144,35,153,54); base[rr,cc]=True             # lower-left: outer wall runs straight through
            _ray(61,137,41,-0.5)                                   # inner wall joins it
            base=skeletonize(base)
        if n in (2,3):                        # snap the wobbly skeleton to perfectly straight 2:1 isometric lines
            rem=base.copy(); out=np.zeros_like(base)
            out[:,:4]=base[:,:4]; out[:,252:]=base[:,252:]; rem[:,:4]=False; rem[:,252:]=False
            xs=np.arange(W); segs=[]
            if n==3:                              # interior vertical fences (kept as traced)
                for x in range(4,252):
                    y=0
                    while y<H:
                        if rem[y,x]:
                            y1=y
                            while y1+1<H and rem[y1+1,x]: y1+=1
                            if y1-y>=6: out[y:y1+1,x]=True; rem[y:y1+1,max(x-2,0):x+3]=False
                            y=y1+1
                        else: y+=1
            while True:
                best=None
                for sl in (0.5,-0.5):
                    for c in range(-200,420):
                        ys=np.round(xs*sl+c).astype(int); ok=(ys>=0)&(ys<H)
                        hit=np.zeros(W,bool); hit[ok]=rem[ys[ok],xs[ok]]|rem[np.clip(ys[ok]-1,0,H-1),xs[ok]]|rem[np.clip(ys[ok]+1,0,H-1),xs[ok]]
                        i=0
                        while i<W:
                            if hit[i]:
                                j=i; last=i
                                while j<W and j-last<=3:
                                    if hit[j]: last=j
                                    j+=1
                                n_=int(hit[i:last+1].sum())
                                if best is None or n_>best[0]: best=(n_,sl,c,i,last)
                                i=last+1
                            else: i+=1
                if best is None or best[0]<5: break
                _,sl,c,i0,i1=best; segs.append([sl,c,i0,i1])
                for x in range(i0,i1+1):
                    y=int(round(x*sl+c))
                    if 0<=y<H: rem[max(y-3,0):y+4,max(x-1,0):x+2]=False
            segs=[q for q in segs if not (q[3]-q[2]<=18 and any(o is not q and o[0]==q[0] and 0<abs(o[1]-q[1])<=8 and (o[3]-o[2])>(q[3]-q[2]) and o[2]-6<=q[3] and q[2]<=o[3]+6 for o in segs))]   # doubled-rail stubs
            merged=True                               # collinear pieces (same slope, offset <=2, overlapping or <=20 px apart) become one segment
            while merged:
                merged=False
                for a in range(len(segs)):
                    for b in range(a+1,len(segs)):
                        SA,SB=segs[a],segs[b]
                        if SA[0]==SB[0] and abs(SA[1]-SB[1])<=2 and SB[2]<=SA[3]+20 and SA[2]<=SB[3]+20:
                            L=SA if (SA[3]-SA[2])>=(SB[3]-SB[2]) else SB
                            segs[a]=[L[0],L[1],min(SA[2],SB[2]),max(SA[3],SB[3])]; del segs[b]; merged=True; break
                    if merged: break
            for sg in segs:                           # outer walls reach the screen edges
                if sg[2]<=6: sg[2]=0
                if sg[3]>=248: sg[3]=255
            for sl,c,i0,i1 in segs:
                for x in range(i0,i1+1):
                    y=int(round(x*sl+c))
                    if 0<=y<H: out[y,x]=True
            if os.environ.get('DBGSEG'): print('SEGS',sorted(segs,key=lambda q:(q[0],q[1])))
            def seg_px(sg,xa,xb): return [(x,int(round(x*sg[0]+sg[1]))) for x in range(xa,xb+1)]
            for kk,sg in enumerate(segs):             # extend each end (up to 14 px) until it meets another segment
                for d,x0 in ((-1,sg[2]),(1,sg[3])):
                    for step in range(1,21):
                        x=x0+d*step
                        if not 0<=x<W: break
                        y=int(round(x*sg[0]+sg[1]))
                        hit=False
                        for k2,o in enumerate(segs):
                            if k2==kk or o[0]==sg[0] or not (o[2]-1<=x<=o[3]+1): continue
                            if abs(int(round(x*o[0]+o[1]))-y)<=2: hit=True
                        if hit:
                            for q in range(1,step+1):
                                xx=x0+d*q; yy=int(round(xx*sg[0]+sg[1]))
                                if 0<=yy<H: out[yy,xx]=True
                            break
            base=out
            Image.fromarray((base*255).astype(np.uint8)).resize((768,576),Image.NEAREST).save(B+'base02.png')
            ground,k,how=ground_k(base,tuple(info[str(n)]["start"]))     # road area must follow the straightened fences
    if n in (1,2,3,4,21,22) and not EX:      # leftover pole stubs near the top of the hexagon tracks
        for x in range(120,200):
            y=5
            while y<45:
                if base[y,x]:
                    y0=y
                    while y<45 and base[y,x]: y+=1
                    if y-y0>=6 and not base[y0+2:y-2,max(x-1,0)].any() and not base[y0+2:y-2,x+1].any(): base[y0+1:y-1,x]=False
                else: y+=1
    _ed=os.path.join(os.path.dirname(os.path.abspath(__file__)),"..","track_edits",f"track{n:02d}.png")
    _edited=os.path.exists(_ed)
    if _edited:                              # hand-edited layout image (256x192): white = fence-base line, grey = road surface, green = outside, black = status bar rows 0-11 (kept from the computed track)
        _im=np.array(Image.open(_ed).convert("RGB")).astype(int)
        _pal=np.array([(0,0,0),(0,170,0),(70,70,85),(255,255,255)])
        _cl=np.argmin(((_im[:,:,None,:]-_pal[None,None,:,:])**2).sum(3),axis=2)
        _nb=(_cl==3); _ng=(_cl==2)
        _nb[:12]=base[:12]; _ng[:12]=ground[:12]
        print(f"   edited layout track{n:02d}.png: base {int(base.sum())}->{int(_nb.sum())} ground {int(ground.sum())}->{int(_ng.sum())}")
        base=_nb; ground=_ng
    solid=ndi.binary_dilation(base,structure=CROSS)|~ground
    if os.path.exists(B+f'tex{n}.npy') and not _edited: _t=np.load(B+f'tex{n}.npy'); solid=solid|_t; ground=ground&~_t     # slab tops: no road, no ground
    if 7<=n<=27: np.save(B+f'solid{n}.npy',solid); np.save(B+f'ground{n}.npy',ground); np.save(B+f'basef{n}.npy',base)
    wc=ZXRGB[7]                                                    # every fence is white, as on track 1 (the Spectrum original needed different colours)
    # ---- start: nearest roomy open pixel
    sx0,sy0=info[str(n)]["start"]
    _lab,_nl=ndi.label(~solid)                                  # start must lie in the biggest drivable region
    _main=_lab==(1+int(np.argmax(np.bincount(_lab[_lab>0])[1:])))
    if n in INFILL and _lab[sy0,sx0]>0: _main=_lab==_lab[sy0,sx0]            # track 14: the infield is bigger than the lane band, but the grid is in the band
    def openp(x,y,r):
        return r<=x<W-r and r<=y<H-r and _main[y,x] and not solid[y-r:y+r+1,x-r:x+r+1].any()
    best=None
    for maxrad,r in ((25,4),(25,3),(25,2),(25,1),(120,4),(120,3),(120,2),(120,1)):
        for rad in range(0,maxrad):
            for dy in range(-rad,rad+1):
                for dx in range(-rad,rad+1):
                    if max(abs(dx),abs(dy))==rad and openp(sx0+dx,sy0+dy,r): best=(sx0+dx,sy0+dy);break
                if best:break
            if best:break
        if best:break
    sx,sy=best
    free_c=np.zeros((CH,CW),bool)
    for cy in range(CH):
        for cx in range(CW):
            blk=solid[cy*CELL+1:cy*CELL+3,cx*CELL+1:cx*CELL+3]
            free_c[cy,cx]=blk.size==4 and blk.sum()==0
    c0=(sx//CELL,sy//CELL); free_c[c0[1],c0[0]]=True
    def bfs(head=None):
        blocked=np.zeros((CH,CW),bool)
        if head is not None:
            hx,hy=HEAD[head]
            for cy in range(CH):
                for cx in range(CW):
                    px,py=cx*CELL+2-sx,cy*CELL+2-sy
                    along=px*hx+(py*2)*(hy*2); perp=abs(-px*(hy*2)+(py*2)*hx)
                    if -10<=along<=-2 and perp<=PERP: blocked[cy,cx]=True
        d=np.full((CH,CW),255,np.uint8); q=deque([c0]); d[c0[1],c0[0]]=0
        while q:
            cx,cy=q.popleft()
            for ox in(-1,0,1):
                for oy in(-1,0,1):
                    nx,ny=cx+ox,cy+oy
                    if ox and oy and not (0<=nx<CW and 0<=ny<CH and free_c[cy,nx] and free_c[ny,cx] and not blocked[cy,nx] and not blocked[ny,cx]): continue   # no corner cutting through thin diagonal fences
                    if (ox or oy) and 0<=nx<CW and 0<=ny<CH and free_c[ny,nx] and not blocked[ny,nx] and d[ny,nx]==255:
                        d[ny,nx]=min(254,d[cy,cx]+1);q.append((nx,ny))
        return d
    d0=bfs(None)
    ring=np.argwhere(d0==6)
    if len(ring)==0: ring=np.argwhere((d0>=2)&(d0<=4))
    vecs=[((cx-c0[0])*CELL,(cy-c0[1])*CELL*2) for cy,cx in ring]
    groups=[]
    for v in vecs:
        for g in groups:
            if v[0]*g[0][0]+v[1]*g[0][1]>0: g.append(v);break
        else: groups.append([v])
    # counter-clockwise (as seen on screen) around the centre of the circuit
    gy_,gx_=np.nonzero(ground); cxm,cym=gx_.mean(),gy_.mean()*2
    rx,ry=sx-cxm,sy*2-cym; tx,ty=(-ry,rx) if n in CLOCKWISE else (ry,-rx)      # CCW tangent on a y-down screen (CW for the tracks the original runs clockwise)
    gm=[(sum(v[0] for v in g),sum(v[1] for v in g)) for g in groups] or [(1,0)]
    pick=max(gm,key=lambda v:v[0]*tx+v[1]*ty)
    h0=int(round(math.atan2(pick[1],pick[0])/(2*math.pi/NH)))%NH
    def sray(h,maxn=60):
        x,y=float(sx),float(sy);c=0
        while c<maxn and 0<=int(x)<W and 0<=int(y)<H and not solid[int(y),int(x)]: x+=HEAD[h][0];y+=HEAD[h][1];c+=1
        return c
    cands=[(sray(h),-min((h-h0)%NH,(h0-h)%NH),h) for h in range(NH) if min((h-h0)%NH,(h0-h)%NH)<=4]
    head=max(cands)[2] if max(cands)[0]>=10 else max((sray(h),h) for h in range(NH))[1]
    head={7:31,11:16,14:20,15:20,16:20,17:0,18:0,19:0,20:16,21:20,22:20,23:0,24:0,25:0,26:0,27:16}.get(n,head)                       # lane direction fixed where the fences are not axis-aligned
    def pbfs(head):
        """pixel-level 4-connected flood from the start; a car centre can only move through non-solid pixels"""
        blocked=np.zeros((H,W),bool)
        hx,hy=HEAD[head]
        yy,xx=np.mgrid[0:H,0:W]
        px=xx-sx; py=(yy-sy)*2
        along=px*hx+py*(hy*2); perp=np.abs(-px*(hy*2)+py*hx)
        blocked=(along>=-10)&(along<=-2)&(perp<=PERP)
        free=~solid&~blocked
        free[sy,sx]=True
        dist=np.full((H,W),-1,np.int32); dist[sy,sx]=0; q=deque([(sx,sy)])
        while q:
            x,y=q.popleft(); dd=dist[y,x]+1
            for nx,ny in((x+1,y),(x-1,y),(x,y+1),(x,y-1)):
                if 0<=nx<W and 0<=ny<H and free[ny,nx] and dist[ny,nx]<0:
                    dist[ny,nx]=dd; q.append((nx,ny))
        dc=np.full((CH,CW),255,np.uint8)
        for cy in range(CH):
            for cx in range(CW):
                blk=dist[cy*CELL:cy*CELL+CELL,cx*CELL:cx*CELL+CELL]
                v=blk[blk>=0]
                if v.size: dc[cy,cx]=min(254,int(v.min())//6)
        global BEHIND,DIST
        DIST=dist
        im=np.zeros((H,W,3),np.uint8); im[solid]=(255,255,255); im[dist>=0]=(40,40,160); im[(dist>=0)&(dist%60<4)]=(120,120,255); im[sy-2:sy+3,sx-2:sx+3]=(255,0,0)
        Image.fromarray(im).resize((W*2,H*2),Image.NEAREST).save(B+f"flood{n:02d}.png")
        zone=(along<-11)&(along>-40)&(perp<=40)&(dist>=0)
        BEHIND=int(dist[zone].max()) if zone.any() else -1
        return dc
    if os.environ.get("DUMPP") and n==6: print("HEAD",head,h0,HEAD[head],sx,sy,cxm,cym)
    d=pbfs(head); dmax=int(d[d<255].max()); reach=int((d<255).sum())
    # ---- number board: pick the emptiest corner (cell coords, 4x2 cells, screen y = track y + 8)
    pan=panel_of(base)|ground
    best_b=None
    for (bc,br) in (((0,r) for r in range(8,15)) if n==10 else (((1,20),(27,20),(1,2),(27,2))+tuple((c,r) for c in range(25,29) for r in range(19,22)) if n==12 else ((1,20),(27,20),(1,2),(27,2)))):      # track 10: middle left, on the grass
        x0,y0=bc*8,br*8
        sub=pan[max(y0-3,0):min(y0+16+8,H),max(x0-3,0):min(x0+32+3,W)]
        sc=int(sub.sum())
        if best_b is None or sc<best_b[0]: best_b=(sc,bc,br)
    _,bcol,brow=best_b
    if n>=26:                                  # narrow board (20 px) inside the infield, as far top-right as it fits
        cand=[]
        for bc in range(0,29):
            for br in range(3,22):
                x0,y0=bc*8,br*8
                cand.append((int(pan[max(y0-2,0):min(y0+16,H),x0+5:x0+27].sum()),-bc,br,bc,br))
        cand.sort(); print("board 26 candidates",len(cand),cand[:8]); bcol,brow=(21,18) if n==26 else (cand[0][3],cand[0][4])
    # ---- bank: base plane | ground plane | progress map
    _lab,_=ndi.label(~solid); _comp=_lab==_lab[sy,sx]               # only the drivable region is road: islands and the outside stay grass (with trees)
    ground=ndi.binary_dilation(_comp,iterations=1)&ground
    gp=np.zeros((192,256),bool); gp[:H,:W]=ground
    bp=np.zeros((192,256),bool); bp[:H,:W]=base
    px,py,npts=make_path(DIST,solid,(sx,sy),H,W,wide=(6<=n<=27 and n!=11),via=VIA.get(n),twoleg=TWOLEG.get(n))
    PATHS[n]=(px,py)
    if os.environ.get("DUMPP"): print("P",n,npts,list(zip(px,py)) if str(n) in os.environ["DUMPP"].split(",") else "")
    page=bytearray(16384); page[0:6144]=np.packbits(bp,axis=1).tobytes(); page[6144:12288]=np.packbits(gp,axis=1).tobytes(); page[12288:12288+CW*CH]=d.tobytes()
    _inf=np.zeros((H,W),bool)
    for _l in range(1,_lab.max()+1):
        if _l==_lab[sy,sx]: continue
        _ys,_xs=np.nonzero(_lab==_l)
        if len(_ys)<120 or _xs.min()<=0 or _ys.min()<=0 or _xs.max()>=W-1 or _ys.max()>=H-1: continue      # the outside of the track touches the picture edge: only enclosed islands are infield
        _inf[_lab==_l]=True
    _tx=(n-1)*4+11 & 255; _ty=(_tx*2+1)&255; _bits=[]          # the game's tree spots: same generator as draw_trees
    for _k in range(220):
        _tx=(_tx*5+17)&255; _ty=(_ty*9+3)&255
        _bits.append(bool(4<=_tx<250 and 18<=_ty<190 and _ty-5<H and _inf[_ty-5,_tx]))
    _bits=_bits[::-1]                                              # tr_n counts down: index tr_n-1
    page[0x3F00:0x4000]=SFX.block(SFX.surf_of(n),_bits)
    page[0x3C00:0x3C00+npts]=bytes(px); page[0x3D00:0x3D00+npts]=bytes(py)
    ph=[]
    for i in range(npts):
        j=(i+2)%npts; ph.append(int(round(math.atan2(2*(py[j]-py[i]),px[j]-px[i])/(2*math.pi/NH)))%NH)
    page[0x3E00:0x3E00+npts]=bytes(ph)
    open(B+f"track{n:02d}.pg","wb").write(page)
    _sn=SFX.surf_of(n); road=SFX.road8(_sn); SURFRGB[road]=SFX.SURF[_sn]['road']
    lo=c332(*[v*0.45 for v in wc]); mid=c332(*[v*0.85 for v in wc]); hi=c332(*[min(255,v*0.85+80) for v in wc]); post=c332(*[min(255,v*0.85+40) for v in wc])
    meta.append((sx,sy,head,lo,mid,hi,post,road,dmax,bcol,brow,npts))
    img=render(base,ground,wc,SURFRGB[road]); PREV.append(img)
    print(f"{n:2d} start({sx:3d},{sy:3d}) head {head:2d} dmax {dmax:3d} reach {reach:4d} ray {sray(head):2d} ground:{how}{k} board({bcol},{brow}) behind {BEHIND//6}")
with open(B+"tracks.inc","w") as f:
    f.write("; per track (12 bytes): startx,starty,head,lo,mid,hi,post,road,dmax,boardcol,boardrow,0\ntrack_meta:\n")
    for i,t in enumerate(meta): f.write("    db "+",".join(map(str,t))+f"  ; track {i+1}\n")
sheet=Image.new("RGB",(260*6+28,194*5+20),(40,40,40))
for i,pv in enumerate(PREV): sheet.paste(Image.fromarray(pv),(4+(i%6)*260,4+(i//6)*194))
sheet.save(B+"preview_filled.png")
with open("/home/claude/stockcar/src/trackdata.asm","w") as f:
    for n in range(27): f.write(f'    MMU 6 7, {32+2*n if n<24 else {24:90,25:94,26:26}[n]}\n    ORG $C000\n    INCBIN "build/track{n+1:02d}.pg"\n')
SPEEDK=12.5/14   # top speed scaled so track 1 lap is ~14 s (original), was 12.5 s
# ---- speed table: NH headings x 16 levels -> (dx,dy) signed 8.8
with open(B+"speed.inc","w") as f:
    f.write("speed_u:\n")    # per-level step (x4, 8.8 fixed): step = speed_u * level / 4
    for h in range(NH):
        f.write("    dw "+",".join(str(int(round(HEAD[h][i]*256*SPEEDK*4/15))&0xFFFF) for i in (0,1))+"\n")
with open(B+"hvec.inc","w") as f:
    f.write("hcos:  db "+",".join(str(int(round(127*math.cos(a*2*math.pi/NH)))&255) for a in range(NH))+"\n")
    f.write("hsin:  db "+",".join(str(int(round(127*math.sin(a*2*math.pi/NH)))&255) for a in range(NH))+"\n")
    R5=math.radians(-3.55)      # track 5: its fences run at -14.8 / 75.2 degrees, not on the 11.25-degree heading steps: start line and grid use turned vectors
    f.write("hcos5: db "+",".join(str(int(round(127*math.cos(a*2*math.pi/NH+R5)))&255) for a in range(NH))+"\n")
    f.write("hsin5: db "+",".join(str(int(round(127*math.sin(a*2*math.pi/NH+R5)))&255) for a in range(NH))+"\n")
# ---- 3D car model: 16 headings, 16x16, anchor (8,12) = ground point. idx 1 top,2 light side,3 dark side,4 front/back,5 window,6 tyre,7 headlight,8 tail light
def car_patterns():
    S=6; out=bytearray()
    for h in range(NH):
        a=h*2*math.pi/NH; ca,sa=math.cos(a),math.sin(a)
        im=Image.new("P",(16*S,16*S),0); dr=ImageDraw.Draw(im)
        def P(u,v,z):
            gx=u*ca-v*sa; gy=u*sa+v*ca
            return ((8+gx)*S,(12+gy*0.5-z*0.95)*S)
        def face(pts3,col): dr.polygon([P(*p) for p in pts3],fill=col)
        def lerp(p,q,t): return p+(q-p)*t
        def draw_box(bx,kind):
            u0,u1,w,z0,z1=bx
            faces=[((ca,sa),[(u1,-w,z0),(u1,w,z0),(u1,w,z1),(u1,-w,z1)],"front"),
                   ((-ca,-sa),[(u0,-w,z0),(u0,w,z0),(u0,w,z1),(u0,-w,z1)],"back"),
                   ((-sa,ca),[(u0,w,z0),(u1,w,z0),(u1,w,z1),(u0,w,z1)],"right"),
                   ((sa,-ca),[(u0,-w,z0),(u1,-w,z0),(u1,-w,z1),(u0,-w,z1)],"left")]
            vis=[f for f in faces if f[0][1]>0.001]
            vis.sort(key=lambda f:sum(P(*p)[1] for p in f[1]))
            for nrm,pts,name in vis:
                col=4 if name in("front","back") else (3 if nrm[0]>0 else 2)
                face(pts,col)
                if kind=="cabin":
                    c0,c1,c2,c3=[np.array(p,float) for p in pts]
                    def q(t,zz): return tuple(lerp(lerp(c0,c1,t),lerp(c3,c2,t),zz))
                    face([q(.1,.15),q(.9,.15),q(.9,.85),q(.1,.85)],5)           # windows
                if kind=="nose" and name=="front":
                    for s_ in(-1,1): face([(u1+.01,s_*w*.7-.55,1.5),(u1+.01,s_*w*.7+.55,1.5),(u1+.01,s_*w*.7+.55,2.5),(u1+.01,s_*w*.7-.55,2.5)],7)   # headlights
                if kind=="tail" and name=="back":
                    for s_ in(-1,1): face([(u0-.01,s_*w*.7-.55,1.5),(u0-.01,s_*w*.7+.55,1.5),(u0-.01,s_*w*.7+.55,2.5),(u0-.01,s_*w*.7-.55,2.5)],8)   # tail lights
            face([(u0,-w,z1),(u1,-w,z1),(u1,w,z1),(u0,w,z1)],1)               # roof / bonnet top
        def wheel(u0,v,rz=1.45,ru=1.55):                                         # a round tyre in the side plane
            dr.polygon([P(u0+ru*math.cos(t*math.pi/6),v,1.35+rz*math.sin(t*math.pi/6)) for t in range(12)],fill=6)
        for u in(-3.7,3.7):                                                     # far-side tyres (behind the body)
            for v in(-2.9,2.9):
                if (v>0)!=(ca>0): wheel(u,v)
        draw_box((-4.6,4.6,2.6,0.8,3.2),"plain")
        draw_box((4.6,6.0,2.2,0.8,2.5),"nose")                                  # sloping bonnet
        draw_box((-6.0,-4.6,2.2,0.8,2.8),"tail")                                # lower boot
        draw_box((-3.4,1.4,1.9,3.2,5.2),"cabin")
        for u in(-3.7,3.7):                                                     # near-side tyres on top of the body: round wheels show in the arches
            wheel(u,2.62 if ca>0 else -2.62,1.55,1.65)
        arr=np.array(im); px=np.zeros((16,16),np.uint8)
        if h==14:                                                               # the big car for the menu screens: same model, 3x the resolution, heading left and slightly down
            f=2; nn=16*S//f; bg=np.zeros((nn,nn),np.uint8)
            for y in range(nn):
                for x in range(nn):
                    cnt=np.bincount(arr[y*f:(y+1)*f,x*f:(x+1)*f].ravel(),minlength=9)
                    if cnt[1:].sum()>=f*f*0.5: bg[y,x]=cnt[1:].argmax()+1
            yy,xx=np.nonzero(bg); bg=bg[yy.min():yy.max()+1,xx.min():xx.max()+1]
            global BIGCAR; BIGCAR=bytes([bg.shape[1],bg.shape[0]])+bg.tobytes()
        for y in range(16):
            for x in range(16):
                cnt=np.bincount(arr[y*S:(y+1)*S,x*S:(x+1)*S].ravel(),minlength=9)
                if cnt[1:].sum()>=S*S*0.4: px[y,x]=cnt[1:].argmax()+1
        for (uu,col_,nrm) in ((6.02,7,(ca,sa)),(-6.02,8,(-ca,-sa))):
            if nrm[1]<=0.001: continue
            pts=[]
            for s_ in(-1,1):
                X,Y=P(uu,s_*2.6*.7,2.0); pts.append((int(X/S),int(Y/S)))
            if pts[0]==pts[1]: pts[1]=(pts[1][0]+(1 if abs(sa)>abs(ca) else 0),pts[1][1]+(0 if abs(sa)>abs(ca) else 1))
            for (X,Y) in pts:
                if 0<=X<16 and 0<=Y<16: px[Y,X]=col_
        out+=bytes(px[5:15].flatten().tolist())            # only rows 5..14 ever contain car pixels
    return bytes((out[i]<<4)|out[i+1] for i in range(0,len(out),2))   # two pixels per byte (values 0..8): 80 bytes per heading
cars=car_patterns()
_rc=os.path.join(os.path.dirname(os.path.abspath(__file__)),"ref_car.png")
if os.path.exists(_rc):                                   # the menu car is drawn pixel for pixel from the supplied low-res reference
    _im=Image.open(_rc).convert("RGB"); _w,_h=_im.size; _b=bytearray([_w,_h])
    for _y in range(_h):
        for _x in range(_w):
            r,g,b=_im.getpixel((_x,_y)); v=0
            if r>150 and b>200 and g>150: v=9                     # hubcaps
            elif r>200 and g>200 and b<120: v=7
            elif abs(r-g)<8 and abs(g-b)<8 and 25<g<60: v=6
            elif b>g and b>=90 and r<80: v=5
            elif g>=200: v=1
            elif g>=130: v=2
            elif g>=80: v=3
            _b.append(v)
    BIGCAR=bytes(_b)
import lzss; lzss.build(os.path.join(os.path.dirname(os.path.abspath(__file__)),"title.nxi"),B+"title")
open(B+"cars.bin","wb").write(cars); open(B+"bigcar.bin","wb").write(BIGCAR)
# contact sheet of the car model (8x zoom), blue
shade=[(0,0,0),(120,160,255),(70,110,230),(30,60,150),(50,80,190),(10,20,40),(40,40,40),(255,255,120),(255,60,60)]
cs=Image.new("RGB",(16*8*8,16*8*4),(70,110,70))
for h in range(NH):
    tile=Image.new("RGB",(16,16),(70,110,70)); 
    for y in range(16):
        for x in range(16):
            v=cars[h*160+(y-5)*16+x] if 5<=y<15 and h*160+(y-5)*16+x<len(cars) else 0
            if v and v<len(shade): tile.putpixel((x,y),shade[v])
    cs.paste(tile.resize((128,128),Image.NEAREST),((h%8)*128,(h//8)*128))
cs.save(B+"car_model.png")
# car palette (4 colours x 4 shades) for L2 palette indices 16..31: BLUE, GREEN, RED, YELLOW
CARC=[(40,90,255),(0,210,0),(230,0,0),(255,225,0)]
with open(B+"pal.inc","w") as f:
    f.write("; L2 palette 0..31\npal_l2:\n")
    st=[0x00,0x49,0x49,0xFF,0xFC,0x92,0xDB,0xB6,0x05,0x25,0xFC,0xE0,0xD7,0,c332(34,76,217),c332(80,130,255)]   # 0 black,1 lo,2 road,3 white,4 yellow,5 mid,6 hi,7 post,8 window,9 tyre,10 head,11 tail,12 hubcap,14 blue (as the blue car),15 light blue
    f.write("    db "+",".join(f"${v:02X}" for v in st)+"\n")
    for r,g,b in CARC:
        sh=[c332(min(255,r*1.0+40),min(255,g*1.0+40),min(255,b*1.0+40)),c332(r*.85,g*.85,b*.85),c332(r*.55,g*.55,b*.55),c332(r*.7,g*.7,b*.7)]
        f.write("    db "+",".join(f"${v:02X}" for v in sh)+"\n")
    f.write("    db $14,$0C,$1C,$64    ; 32 grass, 33 dark foliage, 34 light foliage, 35 trunk\n")
# ---- font 8x8 ASCII 32..95
_ns={}
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'font8.py')).read(),_ns)
fb=_ns['font_bytes']()
fb=bytearray(fb)   # '\' = down chevron, ']' = up chevron (track change arrows beside the best-laps title; neither character is used in any text)
for _ch,_rows in ((92,["........","........","#.....#.",".#...#..","..#.#...","...#....","........","........"]),(93,["........","........","...#....","..#.#...",".#...#..","#.....#.","........","........"])):
    for _i,_r in enumerate(_rows): fb[(_ch-32)*8+_i]=int(_r.replace('#','1').replace('.','0'),2)
fb=bytes(fb)
open(B+"font.bin","wb").write(fb)
# ---- title logo: "3D STOCK CARS 3", 2x scaled, bold, 1 bit/pixel, 240x16 (30 bytes/row)
_G=_ns['G']; _txt="3D STOCK CARS 3"
_rows=[[0]*240 for _ in range(16)]
for _i,_ch in enumerate(_txt):
    _gl=[r.strip() for r in _G[_ch]]
    for _y in range(7):
        for _x in range(7):
            if _gl[_y][_x]=='#':
                for _dy in range(2):
                    for _dx in range(2):
                        for _bx in (0,1):
                            for _by in (0,1):
                                _rows[_y*2+_dy+_by][_i*16+_x*2+_dx+_bx]=1
_lb=bytearray()
for _r in _rows:
    for _b in range(30):
        _v=0
        for _k in range(8): _v=(_v<<1)|_r[_b*8+_k]
        _lb.append(_v)
open(B+"logo.bin","wb").write(_lb)
print("data built")
