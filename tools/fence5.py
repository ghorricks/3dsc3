# Track 5 fences as clean straight segments (shallow walls ~ -1/7.25 slope, steep walls 2:1) fitted to the original's wall mask.
import numpy as np
SS=-0.138      # shallow: y = c + SS*x   (c fitted to the bottom rail)
ST=0.5076      # steep:   x = c + ST*y   (c fitted to the right edge)
def fit(mask,kind,c0,rng,xr):
    H,W=mask.shape; best=None
    below=np.zeros_like(mask); below[:-1]=mask[1:]
    right=np.zeros_like(mask); right[:,:-1]=mask[:,1:]
    edge=(mask&~below) if kind=='s' else (mask&~right)
    res=[]
    for c in np.arange(c0-rng,c0+rng+0.01,0.25):
        n=0
        if kind=='s':
            for x in range(xr[0],xr[1]+1):
                y=int(round(c+SS*x))
                if 0<=y<H and edge[y,x]: n+=1
        else:
            for y in range(xr[0],xr[1]+1):
                x=int(round(c+ST*y))
                if 0<=x<W and edge[y,x]: n+=1
        res.append((c,n))
    m=max(n for c,n in res)
    ok=[c for c,n in res if n>=0.8*m]
    return (max(ok) if kind=='s' else max(ok)),m   # lowest / rightmost rail that is well covered
def isect(a,b):
    # a,b = (kind,c)
    if a[0]==b[0]: raise ValueError
    s,t=(a,b) if a[0]=='s' else (b,a)
    # y = cs + SS x ; x = ct + ST y  -> x = ct + ST (cs + SS x)
    x=(t[1]+ST*s[1])/(1-ST*SS); y=s[1]+SS*x
    return x,y
LINES={'A':('s',47.80),'C':('s',194.08),'E':('s',73.55),'G':('s',167.45),'H':('s',98.16),
       'B':('t',177.82),'D':('t',-20.87),'F':('t',127.78),'I':('t',78.49),'J':('t',28.26)}
def pt(a,b): return isect(LINES[a],LINES[b])
def at_x(n,x): return x, LINES[n][1]+SS*x                  # point on shallow line n at x
def at_y(n,y): return LINES[n][1]+ST*y, y                  # point on steep line n at y
def segments():
    TL,TR,BR,BL=pt('A','D'),pt('A','B'),pt('C','B'),pt('C','D')
    EF,FG=pt('E','F'),pt('F','G')
    HD,HI=pt('H','D'),pt('H','I')
    JG=pt('J','G')
    return [(TL,TR),(TR,BR),(BR,BL),(BL,TL),
            (at_x('E',59),EF),(EF,FG),(JG,FG),
            (HD,HI),(HI,at_y('I',122)),(at_y('J',111),JG)]
def fence5(H=192,W=256):
    b=np.zeros((H,W),bool)
    for (x0,y0),(x1,y1) in segments():
        n=int(max(abs(x1-x0),abs(y1-y0)))+1
        for i in range(n+1):
            t=i/n; x=int(round(x0+(x1-x0)*t)); y=int(round(y0+(y1-y0)*t))
            if 0<=x<W and 0<=y<H: b[y,x]=True
    return b
