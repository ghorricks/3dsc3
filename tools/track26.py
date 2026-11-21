# Track 26 = 3D Stock Cars II (1992), circuit 1, traced from the emulated original screen: road = black, everything else outside.
import numpy as np, sys, json
from PIL import Image
from scipy import ndimage as ndi
src=sys.argv[1]
a=np.array(Image.open(src).convert("RGB")).astype(int)
road=(a.sum(2)==0)|((a[...,0]>150)&(a[...,1]<60)&(a[...,2]<60))      # black tarmac, plus the red start pole and car sprites
road[:16]=False; road[184:]=False
road=ndi.binary_opening(road,structure=np.ones((5,5)))            # drops the speckles in the grass and the thin rail strip
road=ndi.binary_closing(road,structure=np.ones((5,5)))            # removes the cars' sprites
from skimage.morphology import remove_small_holes
road=remove_small_holes(road,400)                                 # cars sitting on the road
lab,k=ndi.label(road); sz=np.bincount(lab.ravel())[1:]; road=lab==(1+int(np.argmax(sz)))
er=ndi.binary_erosion(road,structure=np.array([[0,1,0],[1,1,1],[0,1,0]]),border_value=1)
fence=road&~er
img=np.zeros((192,256,3),np.uint8); img[:]=(0,170,0); img[road]=(70,70,85); img[fence]=(255,255,255)
img[:12]=(0,0,0)
Image.fromarray(img).save("/home/claude/stockcar/track_edits/track26.png")
open("/home/claude/stockcar/build/track26x.bin","wb").write(np.packbits(fence,axis=1).tobytes())
t=json.load(open("/home/claude/stockcar/build/tracks.json")); t["26"]={"wall_colour":7,"blue_bar":None,"wall_px":int(fence.sum()),"start":[int(sys.argv[2]),int(sys.argv[3])]}
json.dump(t,open("/home/claude/stockcar/build/tracks.json","w"))
Image.fromarray(img).resize((768,576),Image.NEAREST).save("/tmp/t26.png"); print(road.sum(),fence.sum())
