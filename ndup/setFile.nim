## Utility code to deal with (NON-ZERO) hash code key sets as Linear Probed-
## Robin Hood reorganized files.

const HSz = 8   #TODO Generalize to non-8-byte-sized hash codes.

import std/[math, parseutils, hashes], memfiles as mf, cligen/osUt
when not declared(fmRead): import std/syncio
type SetFile* = MemFile

proc rightSize(count: Natural, num=5, den=6): int {.inline.} =
  nextPowerOfTwo(count * den div num + 1)

proc initSetFile*(path: string, size=0, num=5, den=6): SetFile {.inline.} =
  if size == 0: mf.open(path, fmRead)
  else: mf.open(path, fmReadWrite, newFileSize = HSz*rightSize(size, num, den))

proc slots*(s: SetFile): int {.inline.} = s.size div HSz

template BadIndex: untyped =
  when declared(IndexDefect): IndexDefect else: IndexError

template boundsCheck(s, i) =
  when not defined(danger):
    if s.mem.isNil: raise newException(ValueError, "nil MemFile")
    if (let n = s.size div HSz; i >=% n):
      raise newException(BadIndex(), formatErrorIndexBound(i, n))

proc `[]`*(s: SetFile, i: int): uint64 {.inline.} =
  boundsCheck(s, i)
  cast[ptr uint64](cast[int](s.mem) + HSz * i)[]

proc `[]`*(s: var SetFile, i: int): var uint64 {.inline.} =
  boundsCheck(s, i)
  cast[ptr uint64](cast[int](s.mem) + HSz * i)[]

proc `[]=`*(s: var SetFile, i: int, value: uint64) {.inline.} =
  boundsCheck(s, i)
  cast[ptr uint64](cast[int](s.mem) + HSz * i)[] = value

proc depth(keyHash: uint64, mask: uint64, i: int): int {.inline.} =
  int((i.uint64 + mask + 1u64 - (keyHash and mask)) and mask)

proc hash(key: uint64): uint64 = hashes.hash(key).uint64 # (0u64, toOpenArray[char](cast[ptr UncheckedArray[char]](key.unsafeAddr),0,7))
proc incl*(s: var SetFile, key: uint64): bool {.inline.} =
  let mask = uint64(s.slots - 1)
  var k = key
  var i = hash(k) and mask      # Robin-Hood LP makes small isects ~2X faster
  var d = 0                     # Basic idea is Avg Depth Minimization
  while s[i.int] != 0u64:
    if s[i.int] == k: return true               # Found; Nothing to do
    let dX = depth(hash(s[i.int]), mask, i.int) # depth of eXisting
    if d > dX:                                  # Target deeper than existing
      swap k, s[i.int]                          # Swap & continue to find slot
      d = dX
    i = (i+1) and mask          # CPUs branch.predict/prefetch, drives stream
    inc d                       #..faster than seek all => Linear probing best
  s[i.int] = k

proc contains*(s: SetFile, key: uint64): bool {.inline.} =
  let mask = uint64(s.slots - 1)
  var i = hash(key) and mask
  var d = 0                     # d <= depth check is the 1/2 work saving bit
  while s[i.int] != 0 and d <= depth(hash(s[i.int]), mask, i.int):
    if s[i.int] == key: return true
    i = (i + 1) and mask
    inc d

iterator items*(s: SetFile): uint64 {.inline.} =
  for i in 0 ..< s.slots:
    if s[i] != 0: yield s[i]

proc `$`*(s: SetFile): string =
  let mask = uint64(s.slots - 1)
  for i in 0u64..mask:
    if s[i.int] == 0: echo "  ", i, ": EMPTY"
    else: echo "  ", i, ": ", s[i.int], " HOME: ", hash(s[i.int]) and mask,
               " DEPTH: ", depth(hash(s[i.int]), mask, i.int)

proc make*(outp: string; n, Num, Den: int) =
  ## Create from 1-per-line decimal numbers on stdin
  var s = initSetFile(outp, n, Num, Den)
  var num, lno: BiggestUInt
  for decimal in getDelim(stdin):
    inc lno
    if parseBiggestUInt(decimal, num) != decimal.len:
      erru "stdin:",lno,": not an unsigned decimal: ",decimal,"\n"
    discard s.incl(cast[uint64](num))
  s.close

proc isect*(paths: seq[string]) =
  ## Print intersection of set files stored in paths
  var hts: seq[SetFile]
  for path in paths:
    hts.add initSetFile(path)
    if hts[^1].size == 0: return
  for e in hts[0]:
    var inAll = true
    for hto in hts[1..^1]:
      if e notin hto:
        inAll = false
        break
    if inAll: echo e

proc doStats*(s: SetFile): tuple[load:float,lg:int,mx:int,avg:float,rms:float] =
  var mx, ssq, tot, n: int
  let mask = uint64(s.slots - 1)
  for i in 0u64..mask:
    if s[i.int] != 0:
      let d = depth(hash(s[i.int]), mask, i.int)
      mx = max(mx, d)
      tot += d
      ssq += d*d
      inc(n)
  return (float(n) / float(mask + 1), int(log2(float(mask + 2))), mx,
          float(tot) / float(n), sqrt(float(ssq) / float(n)))

proc stats*(nPaths: seq[string]) =
  ## Print statistics for listed set files
  var s: SetFile
  for path in nPaths:
    try      : s = initSetFile(path)
    except Ce: erru "problem opening ", path, "\n"; raise
    echo path, " ", s.doStats
    s.close

proc list*(nPaths: seq[string]) =
  ## List concise membership of set files in `nPaths`
  var s: SetFile
  for path in nPaths:
    try      : s = initSetFile(path)
    except Ce: erru "problem opening ", path, "\n"; raise
    for e in s: echo e
    s.close

proc print*(nPaths: seq[string]) =
  ## Print verbose textual table representation for listed set files
  var s: SetFile
  for path in nPaths:
    try      : s = initSetFile(path)
    except Ce: erru "problem opening ", path, "\n"; raise
    echo "TABLE: ", path, "  ", s.doStats, "\n", s
    s.close

when isMainModule:
  import cligen; dispatchMulti [make],[isect],[stats],[list],[print]
