from pathlib import Path
import fitz,cv2,numpy as np
from PIL import Image,ImageDraw
out=Path('tmp/source');out.mkdir(exist_ok=True)
for group,file in [('blu','Blood Master - BLU.pdf'),('rossi','Blood Master - ROSSI.pdf'),('backfire','BackFire - espansione.pdf')]:
 doc=fitz.open(file)
 for i,p in enumerate(doc):
  pix=p.get_pixmap(matrix=fitz.Matrix(3,3)); im=Image.frombytes('RGB',[pix.width,pix.height],pix.samples).rotate(-90,expand=True)
  im.save(out/f'{group}-{i+1}.png')
# Check whether the arena scans overlap, using feature matches only.
ims=[cv2.imread(f'tmp/pdfs/arena-{i}.jpg') for i in range(1,5)]
sift=cv2.SIFT_create(nfeatures=8000)
features=[sift.detectAndCompute(im,None) for im in ims]
for i in range(4):
 for j in range(i+1,4):
  a,b=features[i],features[j];m=cv2.BFMatcher().knnMatch(a[1],b[1],k=2);good=[x for x,y in m if x.distance<.65*y.distance]
  if len(good)>5:
   src=np.float32([a[0][x.queryIdx].pt for x in good]);dst=np.float32([b[0][x.trainIdx].pt for x in good]);h,mask=cv2.estimateAffinePartial2D(src,dst,method=cv2.RANSAC,ransacReprojThreshold=4)
   print(i+1,j+1,'matches',len(good),'inliers',int(mask.sum()),'transform',h.tolist())
