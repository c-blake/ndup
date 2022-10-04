import std/[random, bitops, strutils],
       cligen/[mfile, mslice, strUt, osUt, fileUt, statx]
proc hash(ms: MSlice): uint64 = ms.toOpenArrayChar.hashCB

var sBox: array[256, uint64]            # Rand Substitution-box for "Buzhash"
proc sBox_init(seed: int) =             # Init S-box from user-controlled seed
  var r = initRand(seed*seed)
  for i in 0..255: sBox[i] = r.next
  shuffle sBox
template s(c): untyped = sBox[ord(c)]

proc doIn*(outs: seq[File], fMin=0, w=61, mask=0u64, vals: seq[uint64],
           inp: MSlice): bool =
  ## Simultaneously frame & hash for each of `vals`.
  var rh = 0u64                                 # R)olling H)ash
  var i0 = newSeq[int](vals.len)                # block starts
  for i in 0 ..< inp.len:                       # For each byte:
    rh = rh.rotateLeftBits(1)                   # Rotate hash by 1 bit
    if i >= w:                                  # When there is a full window..
      rh = rh xor s(inp[i-w]).rotateLeftBits(w) #  ..Xor out impact of old byte
    rh = rh xor s(inp[i])                       # Xor in S[newByte]; rh up2Date
    let rhMask = rh and mask
    for k, val in vals:                         # Check rh against each val
      if i - i0[k] >= fMin and rhMask == val:   #  ..if block size >= fMin
        let h = hash(inp[i0[k] ..< i])          # Append mixier hash to k-th out
        if outs[k].uriteBuffer(h.addr, h.sizeof) < h.sizeof: return true
        i0[k] = i                               # Record new block start @i
  for k, val in vals:                           # Hash last_i0..EOF
    let h = hash(inp[i0[k] ..< inp.len])        # Append mixier hash to k-th out
    if outs[k].uriteBuffer(h.addr, h.sizeof) < h.sizeof: return true

proc framed*(slice="", Seed=654321, fMin=64, win=61, mask=255u64,
             vals: seq[int] = @[], oPat="/tmp/d/$p", paths: seq[string]): int =
  ## Frame & d)igest input paths using a rolling-hash for frame boundaries & a
  ## more collision resistant hash for frame digests.  File times are used to
  ## skip work.  Files whose input slice < `fMin` bytes are ignored.  `oPat`
  ## outputs have dirs made as needed.
  if "$p" notin oPat: erru "`oPat` must use path $p\n"; return
  var vals = if vals.len > 0: vals else: @[123456789]   # 987654321 675309867
  sBox_init Seed                        # Init sBox
  let (sWin, sMask, sfMin, sSeed) = ($win, $mask, $fMin, $Seed) # cache strings
  var sV: seq[string]
  for v in vals: sV.add $v
  for path in paths:
    let inp = mopen(path)               # Open input
    if inp.len > fMin:                  # Separate threshold?
      var outs: seq[File]               # Open outputs
      var vs: seq[uint64]               # Needed pre-masked vals
      for j, v in vals:
        let v = v.uint64 and mask       # Pre-mask match val (for oPath, too)
        let oPath = oPat % ["p",path, "v",sV[j], "win",sWin, "mask",sMask,
                            "fMin",sfMin, "slice",slice, "Seed",sSeed]
        if fileTime(path, 'v') > fileTime(oPath, 'v'):
          outs.add mkdirOpen(oPath, fmWrite)
          vs.add v
      if vs.len > 0:
        if outs.doIn(fMin, win, mask, vs, inp[parseSlice(slice, inp.len)]):
          erru "out of disk space\n"; return 1
      for f in outs: f.close            # Clean up
    inp.close

when isMainModule: import cligen; dispatch framed, help={
  "slice": "fileSlice (float|%:frac; <0:tailRel) to do",
  "Seed" : "RNG seed for sBox generation",
  "fMin" : "Ensure frame size >= this many bytes",
  "win"  : "size of rolling hash window",
  "mask" : "rHash & mask == val (mask=>AVG block size)",
  "vals" : "values of rHash to match; none=>123456789",
  "oPat":"""hash digests go here; This interpolates:
  $p $v $win $mask $fMin $slice $Seed"""}
