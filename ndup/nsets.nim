## A file collection, a way to digest, and desire to compare motivate this code.
## E.g., one can segment a file into frames based on a rolling hash & then stack
## goodHash(frame)s to form a digest like rsync, saved as an .NL file.  Compares
## need costly ops like set intersect only for pairs of digests SHARING AN ITEM.
## Spending space-time for an inverted index {item -> seq[fileNosWithIt]} trims
## work from O(nFiles^2) scans to O(nSeqs\*avgSeqLen^2) as well as saving many
## unneeded compares for any wildly common digest values.  Basic flow is `make`
## to maintain hash set files based on externally maintained digests, `pair` to
## emit pairs & `comp` over pair lists to score digest|SetFile similarity.

type D = uint64
const DSz = D.sizeof    #TODO Generalize to !=8-byte-sized digest item slots

import std/[tables, sets, os, times, strutils], std/memfiles as mf,
       cligen/[posixUt, osUt, mslice], setFile, invidx

proc make*(paths: string, iPat="", oPat="", skip=0, Skip=0, frac=0.0, Frac=0.0,
           merge=1, Num=5, Den=6, xclude = @[1.D], newer=false, verb=false) =
  ## Build saved non-0 digest set files in `oPat` from digest files in `iPat`.
  if "$p" notin iPat: erru "`iPat` must use path $p\n"; return
  if "$p" notin oPat: erru "`oPat` must use path $p\n"; return
  var rsCnt = 0
  for path in getDelim(paths, '\0'):
    var inp: MemFile
    let iPath = iPat % ["p", path]
    let oPath = oPat % ["p", path]
    try: createDir(parentDir(oPath))
    except: erru "cannot create output directory for ",path,'\n'; continue
    if newer and getLastModTimeNs(oPath) > getLastModTimeNs(iPath): continue
    try: inp = mf.open(iPath)
    except: erru "problem with ",iPath,'\n'; continue
    let n = inp.size div DSz
    var s = initSetFile(oPath, n div merge + 1, Num, Den)
    let nSkip0 = min(skip, int(frac * float(n)))
    let nSkip1 = min(Skip, int(Frac * float(n)))
    var pop = 0
    for i in countup(nSkip0, n - nSkip1 - merge, merge):
      var key = 1.D                 # Ensure keys are never zero
      for j in 0 ..< merge:         # Do non-0 wraparound product of successive
        let xIpJ = cast[ptr uint](cast[int](inp.mem) +% DSz * (i + j))[]
        key *= (if xIpJ == 0.D: 1.D else: xIpJ)
      if key == 0.D: key = 1.D      # non-0 * non-0 can still == 0 on overflow
      if key notin xclude:          # xclude trims false positives from common..
        if not s.incl(key): inc pop #..known-in-advance frames/block dig vals.
    inp.close
    let doRightSize = 2*pop*Den < Num*s.slots # Iter Wants Num/Den/2<ld<Num/Den
    if doRightSize:                 # Windows cannot rename open files
      inc rsCnt
      var sRS = initSetFile(oPath&".tmp", pop, Num, Den)
      for k in s: discard sRS.incl(k)
      if verb: echo oPath," ",sRS.doStats
      sRS.close
    elif verb:
      echo oPath," ",s.doStats
    s.close
    if doRightSize:
      moveFile oPath&".tmp", oPath  # An OS might cancel defunct IO with luck
  if verb: stderr.write "right-sized ",rsCnt," sets\n"

proc count(paths: string, sPat=""): (seq[string], int) =
  for path in getDelim(paths,'\0'): # 0) Collect paths, estimate InvIdx size
    result[0].add path
    try: result[1].inc int(getFileSize(sPat % ["p", path]) div 8)
    except: erru "problem sizing ",sPat % ["p", path],'\n'; raise

proc pair*(paths: string, sPat="", cmax=0.0115, delim='\t', rDelim='\n', Num=5,
           Den=6, verb=0) =
  ## Print pairs of set files in `paths` which share >=1 value.
  if paths.len == 0: erru "must provide valid path to paths\n"; return
  if "$p" notin sPat: erru "`sPat` must use path $p\n"; return
  let t0 = epochTime(); var t1, t2: typeof(t0)
  let (name, nDig) = count(paths, sPat)
  if name.len > 65534: quit $name.len & " is too many files",1 #TODO >2B fileIds
  let nDEst = uint64(nDig.float * Num.float / Den.float)
  let cmax  = int(cmax * name.len.float)
  if verb > 0: erru "nFiles: ",name.len," nDigEstimated: ",nDEst," virt.mem: ",
                    nDEst.invIdxSpace*DSz.uint64 shr 20," MiB\n"
  var d2fNs = initInvIdx[D, uint16](nDEst)
  for i in 0 ..< name.len:          # 1) Build an inverted index
    try:
      var s = initSetFile(sPat % ["p", name[i]])
      for e in s: d2fNs.add e, uint16(i + 1), cmax  # 1-origin file numbers
      s.close
    except: erru "problem opening ",sPat % ["p", name[i]],'\n'; raise
  if verb > 0: erru "nDig: ",d2fNs.len," in ",(t1=epochTime();t1-t0)," s\n"
  var cmps = initHashSet[uint32]()  # 2) Uniqify-implied pair comparisons
  var nC = 0
  for key, fNs in d2fNs:            # Accumulate any new pairs from fNs*fNs
    if fNs[].len == cmax:           # Too wide a collision cluster
      inc nC
      if verb > 1: erru ">= ",fNs[].len," way collision for key: ",key,'\n'
    elif fNs[].len > 1:             # Need at least 2 to compare
      inc nC
      if verb > 2:
        var str = "key " & $key
        for fn in fNs[]: str.add ' '; str.add name[fn - 1]
        erru str, "\n"
      for i in 0 ..< fNs[].len:     # i<j => fNs[i]<fNs[j] by construction
        for j in i+1 ..< fNs[].len: # So, below pair is always the same order.
          if fNs[][i] < fNs[][j]:
            cmps.incl (fNs[][i].uint32 shl 16) or fNs[][j].uint32
          elif fNs[][i] > fNs[][j]: # Hrm j = i+1.. should already nix diag
            cmps.incl (fNs[][j].uint32 shl 16) or fNs[][i].uint32
  if verb > 0: erru "nColliding: ",nC,'\n'
  if verb > 0: erru cmps.len," unique cmps in ",(t2=epochTime(); t2-t1)," s\n"
  for cmp in cmps:                  # 3) Emit pair cmp
    let hi = int(cmp shr 16)
    let lo = int(cmp and 0xFFFF'u32)
    stdout.write name[hi - 1], delim, name[lo - 1], rDelim

proc compare*(inp, pat, outp: string; delim='\t') =
  ## Read path pairs on stdin & print comparison stats & paths.
  if "$p" notin pat: erru "`pat` must use path $p\n"; return
  var cache = initTable[string, SetFile](65536)
  proc file2set(path: string): SetFile =
    try: return cache[path]
    except:
      let fPath = pat % ["p",path]
      try   : (let f = initSetFile(fPath); cache[path] = f; return f)
      except: erru "problem opening ",fPath,'\n'; raise
  var fields: seq[string]
  var lno = 0
  let outf = syncio.open(outp, fmWrite)
  let T = "\t"
  for line in lines(inp):
    inc lno
    if line.splitr(fields, sep=delim) != 2:
      erru inp,":",lno," malformed input path pair\n"
      continue
    let pA = fields[0]; let pB = fields[1]
    let htA = file2set(pA)
    let htB = file2set(pB)
    if htA.size == 0 or htB.size == 0:
      continue
    var count, htAlen, htBlen: int
    if htA.size < htB.size:         # Choose loop order to minimize lookups
      for e in htB: inc htBlen      # prePage/cache in VMorder;Also exact htBlen
      for e in htA:
        inc htAlen
        if e in htB: inc count
    else:
      for e in htA: inc htAlen      # prePage/cache in VMorder;Also exact htAlen
      for e in htB:
        inc htBlen
        if e in htA: inc count
    if count > 0:
      outf.write count, T, htAlen, T, htBlen, T, pA, T, pB, '\n'
  outf.close

when isMainModule: import cligen; dispatchMulti(
  [nsets.make, help={
    "paths" : "path to \\0-delim list of paths",
    "iPat"  : "$p input digest file pattern",
    "oPat"  : "$p output set file pattern",
    "skip"  : "skip SKIP initial ints",
    "Skip"  : "skip SKIP final ints",
    "frac"  : "skip init FRAC of ints",
    "Frac"  : "skip final FRAC of ints",
    "merge" : "merge successive entries into 1 int",
    "Num"   : "numerator in max table load fraction",
    "Den"   : "denom in max table load fraction",
    "xclude": "merged hash vals to exclude from sets",
    "newer" : "produce output only if inp is newer",
    "verb"  : "print post-make set statistics"}],
  [pair, help={
    "paths" : "path to \\0-delim list of set file inputs",
    "sPat"  : "$p input setFile pattern",
    "cmax"  : "cluster size limit/filter (frac of nPath)",
    "delim" : "output pair delimiter",
    "rDelim": "output row terminator",
    "Num"   : "numerator in max table load fraction",
    "Den"   : "denom in max table load fraction",
    "verb"  : "verbosity: 0..3 are meaningful"}],
  [compare, help={
    "inp"   : "file containing input path pairs",
    "pat"   : "$p pattern for setFile input paths",
    "outp"  : "file for output comparison stats",
    "delim" : "in-line delimiter between input path pairs"}])
