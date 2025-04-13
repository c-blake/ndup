when not declared(File): import std/[syncio] # Compile w/fast-math for dot prods
import std/[os,strutils,terminal, posix, strscans, math, algorithm],
       cligen/[sysUt, osUt]

if stdin.isatty:quit """Square Gray Frame Digester filter after Zauner2010. Eg.:
  ffmpeg -i X -vf scale=32:32,format=gray -c:v pgm -f rawvideo - | pHash > Y.NL
saves 64-bit frame hashes of video file `X` to nio file `Y.NL`.""", 1

# 7 seems to match best on 5..8 for 32x32 frames.  www.phash.org impls more.
let m = if paramCount() > 0: 1.paramStr.parseInt else: 7 # Coskun2004 originally

var line, wH, mV: string
proc readFrame(f: File; w, h: var int; raster: var seq[byte]): bool =
  if not f.readLine(line): return       # EOF
  if line != "P5"      : IO !! "expected PGM P5"
  if not f.readLine(wH): IO !! "expected width height"
  if not f.readLine(mV): IO !! "expected max val"
  if mV != "255"       : Value !! "Scale is not 8-bits"
  if not scanf(wH, "$i $i", w, h): IO !! "expected w h"
  raster.setLen w*h
  let n = stdin.ureadBuffer(raster[0].addr, w*h)
  if n == 0: return
  if n < w*h: IO !! "partial raster: " & $n & " bytes"
  true

proc mkDCT(dctK: var seq[float], n: int) {.used.} =
  dctK.setLen n*m
  let k = sqrt(2.0 / n.float)   # Discrete Cosine Transform matrix
  let w = PI / 2.0 / n.float            
  for i in 0 ..< m:             # m: number of DCT coefficients
    for j in 0 ..< n:           # n: square image size
      dctK[i*n + j] = k * cos(w * float(i + 1) * float(2*j + 1))

proc dot(x, y: seq[float]; a, b, n: int): float =
  for i in 0..<n: result += x[a + i]*y[b + i] # dense (non-strided) dot product

var rast: seq[float]
proc mkCoef(coef: var seq[float]; dctK: seq[float]; raster: seq[byte]; n: int) =
  rast.setLen raster.len
  for i, r in raster: rast[i] = r.float
  coef.setLen m*m
  for i in 0..<m:               # Cij=sum [k,l],dctK[i,k]*raster[k,l]*dctK[j,l]
    for j in 0..<m:
      coef[i + m*j] = 0.0
      for l in 0..<n: coef[i + m*j] += dctK[j*n + l]*dot(rast, dctK, n*l, n*i,n)

proc median(coef: var seq[float]): float =
  var coef = coef; coef.sort; let n = coef.len
  if n mod 2 == 1: coef[(n - 1) div 2]
  else: 0.5*(coef[n div 2] + coef[(n div 2) - 1])

var w, h, n: int                # MainLoop: Read Frames,Calc&Emit hash-per-frame
var raster: seq[byte]
var dctK, coef: seq[float]
while stdin.readFrame(w, h, raster):
  if w != h: IO !! "non-square PGM image"
  if n != w: n=w; dctK.mkDCT n  # Mandate same image size frame to frame?
  coef.mkCoef dctK, raster, n
  let median = coef.median
  var tot = 0u64; for i, c in coef: (if c > median: inc tot, 1 shl i)
  discard stdout.uriteBuffer(tot.addr, tot.sizeof)

flushFile stdout                # Push expensive result to stable storage ASAP
discard posix.fsync(1)          #..in case CPU thermal shutdown is imminent.
