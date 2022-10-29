import std/[hashes, tables, algorithm, os, math]
when not declared(stderr): import std/syncio
type
  InvIdx*[Key,Id] = object ## Inverted Index tailored for ndup.  Specifically, a
    ## space-optimized `Table` from "mostly but not exactly" unique keys (think
    ## `uint64` hashes) to `seq[Id]`.  Packs as many `Id` as fit in one `Key` by
    ## it & then overflow to a `Table`.  Internally, a key pair is stored (so
    ## must have `Key.sizeof >= Id.sizeof` & maybe an even multiple).
    data: seq[Key]              # Really a seq of K,V pairs where V=inline Ids
    ovflow: Table[Key, seq[Id]] # Overflow Table augmenting the inline list
    shifts: seq[int]            # shift of each inline Id element
    mask: Key                   # mask to get an Id out of a Key type
    pop: int                    # population

proc invIdxSpace*(capacity: uint64): uint64 = ## Base space (`Key` units)
  2u64*(capacity.int + 1).nextPowerOfTwo.uint64

proc initInvIdx*[Key,Id](capacity: uint64): InvIdx[Key,Id] =
  result.data = newSeq[Key](capacity.invIdxSpace)
  result.ovflow = initTable[Key, seq[Id]](4)
  result.mask = (1 shl (8 * Id.sizeof)) - 1
  result.shifts = newSeq[int](0)
  for shf in 0 ..< Key.sizeof div Id.sizeof:
    result.shifts.add(8 * Id.sizeof * shf)
  result.shifts.reverse                 # So earlier elts read left2right in hex

func len*[Key,Id](ii: var InvIdx[Key,Id]): int = ii.pop

func depth(h, mask, i: int): int = (i + mask + 1 - (h and mask)) and mask

var maxProbes = 1000

proc maybeAdd[Id](s: var seq[Id], id: Id, cmax: int) =
  if s.len < cmax and id notin s: s.add id  # Mem dense but SLOW for big cmax

proc add*[Key,Id](ii: var InvIdx[Key,Id], key: Key, id: Id, cmax=100) =
  ## add/update Ids for key; id == 0 is not allowed as it signifies "missing".
  let mask = len(ii.data) div 2 - 1
  var i = hash(key.uint64) and mask     # Linear Probing w/Robin Hood Re-org
  var d = 0
  while ii.data[2*i] != 0 and d <= depth(hash(ii.data[2*i].uint64), mask, i):
    if ii.data[2*i] == key:             # Found => edit
      for shift in ii.shifts:
        let x = Key(ii.data[2*i + 1])
        if Id((x shr shift) and ii.mask) == 0:
          ii.data[2*i + 1] = Key(x or (id.Key shl shift))
          return
      ii.ovflow.mgetOrPut(key, @[]).maybeAdd id, cmax - ii.shifts.len
      return
    i = (i + 1) and mask
    inc d
    if d > maxProbes:
      maxProbes = d; stderr.write "weak hash: ",d," probes in InvIdx.add\n"
  var j = i                             # Not found: add
  inc ii.pop
  if 2*(ii.pop + 1) >= ii.data.len:
    raise newException(ValueError, "too many unique hashes")
  let cellSz = 2 * Key.sizeof
  while ii.data[2*j] != 0: j = (j + 1) and mask
  if j > i:                             # No table wrap around; just shift up
    moveMem(addr ii.data[2*(i + 1)], addr ii.data[2*i], (j - i) * cellSz)
  elif j < i:                           # j wrapped to low idxs; Did >0 j++%sz's
    moveMem(addr ii.data[2*1], addr ii.data[0], j * cellSz)
    ii.data[0] = ii.data[2*mask]; ii.data[1] = ii.data[2*mask + 1]
    moveMem(addr ii.data[2*(i + 1)], addr ii.data[2*i], (mask - i) * cellSz)
  ii.data[2*i] = key                    # Not Found => init slot 0@i
  ii.data[2*i+1] = Key(id.Key shl ii.shifts[0])

iterator pairs*[Key,Id](ii: InvIdx[Key,Id]): (Key, ptr seq[Id]) =
  ## yield the key and seq[Id] pair for each key in the inverted index
  var ids: seq[Id]
  var kIds = (0.Key, ids.addr)          # Non-ptr version seems to copy
  for i in 0 ..< ii.data.len div 2:
    let off = 2 * i
    let key = ii.data[off]
    kIds[0] = key
    let pkd = ii.data[off + 1].Key
    ids.setLen 0
    for shift in ii.shifts:
      let id = Id((pkd shr shift) and ii.mask)
      if id != 0:
        ids.add id
    if ids.len == ii.shifts.len and key in ii.ovflow:
      ids.add ii.ovflow[key]
    yield kIds
