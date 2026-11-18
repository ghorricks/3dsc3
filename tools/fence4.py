# Track 4 fences as clean straight isometric segments (2:1 slopes and verticals), fitted to the original's wall mask.
import numpy as np
def fence4(H=192,W=256):
    b=np.zeros((H,W),bool)
    def ln(kind,c,x0,x1):
        for x in range(x0,x1+1):
            y=int(round(c-0.5*x)) if kind=='/' else int(round(c+0.5*x))
            if 0<=y<H and 0<=x<W: b[y,x]=True
    def vl(x,y0,y1): b[y0:y1+1,x]=True
    def hl(y,x0,x1): b[y,x0:x1+1]=True
    ln('/',77,0,124); hl(15,124,130); ln('\\',-50,130,254); vl(254,77,128)
    ln('/',253.5,128,254); ln('\\',125.5,3,128)
    vl(1,77,88); vl(1,112,127)                       # left edge either side of the notch
    ln('\\',88.5,1,22); ln('/',113,1,22); vl(22,99,102)  # arrow-head notch
    ln('\\',19.5,60,94)                              # inner walls
    ln('\\',57,59,91)
    ln('/',149,58,164)
    ln('/',185,60,162)
    ln('\\',-15,129,207); vl(207,88,117); ln('/',220,134,207)
    return b
