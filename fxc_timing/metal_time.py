# Times the Metal front end (metal -> air) and the AIR -> metallib backend per variant.
import subprocess, time, os, statistics, json
out={}
for n in sorted(os.listdir('out')):
  d=os.path.join('out',n)
  if not os.path.isdir(d) or n=='allsix': continue
  ts=[]
  for _ in range(3):
    t=time.time()
    subprocess.run(['xcrun','-sdk','macosx','metal','-ffast-math','-c',d+'/frag.metal','-o',d+'/frag.air'],check=True,capture_output=True)
    ts.append(time.time()-t)
  out[n]=round(statistics.median(ts)*1000)
  print(f"{n:40s} metal->air {out[n]:6d} ms", flush=True)
json.dump(out,open('metal_times.json','w'),indent=1)
