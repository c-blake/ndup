import std/[syncio, os, tables, strutils, strformat, algorithm, math, sugar],
       cligen/[sysUt, osUt, mfile, mslice], cligen  # Sections: /[A-Z]{5}.*
type Id = uint32        # TYPES         # <= 4-gibi-toks should be plenty
type If = tuple[id: Id, v: float32]     # Int tokenId, float weight pair
type V  = seq[If]; const V0: V = @[]    # Sparse Id,weight vector type

var Pre* = ""           # GLOBALS       # Preprocessor; e.g. "catz $1"
var Dir* = ".like"                      # Where to put .tok, foo.NIf metadata
var Tok* = ".tok.Dn"                    # \n-termd token file (\n NOT IN tokens)
var tId: Table[MSlice, Id]              # tokenData -> tokenId table
var fToks: File; var tO: int            # To append new tokens as discovered

proc populateTId =      # DOCUMENT PROCESSING (to end of `proc tf`)
  mkdirP Dir                            # Ensure location for binary files
  let mf = mopen(Dir/Tok, err=nil)      # Extant tokens mmap()d at start
  if not mf.mem.isNil:                  # Just a flat list of \0-term strings
    for t in mf.mSlices: tId[t] = Id(t.mem -! mf.mem) # 0-origin tok-offset
    tO = mf.len                         # Running token offset for any new data
  fToks = open(Dir/Tok, fmAppend)       # Append mode for new tokens

when defined stem:   # Could also auto-probe; Wrap snowball-stemmer for English
  {.passl: "/usr/lib64/libstemmer.so".} # YOU MAY NEED TO ADJUST THIS!
  type sb_stemmer {.bycopy.} = object
  proc sb_stemmer_new(algo:cstring; encode:cstring): ptr sb_stemmer {.importc.}
  proc sb_stemmer_stem(s:ptr sb_stemmer; w:pointer; n:cint): pointer {.importc.}
  proc sb_stemmer_length(s:ptr sb_stemmer): cint {.importc.}
  let st = sb_stemmer_new("english", "UTF_8") # or "ISO_8859_1"

proc toId(ms: var MSlice): Id =         # Retrieve Id or ingest a token.
  when declared st:                                   # _stem() -> mem owned by
    ms.mem = st.sb_stemmer_stem(ms.mem, ms.len.cint)  #..stemmer,but either done
    ms.len = st.sb_stemmer_length.int                 #..post[]|write/dup here.
  try: return tId[ms]                   #NOTE This DOES NOT guard .tok against
  except:                               #     corrupting concurrent updates.
    fToks.urite ms, '\n'; ms.dup        # Add new token to the .tok file & mem
    tId[ms] = tO.Id                     #..table with *intended prog-lifetime*.
    result = tO.Id                      # Non-0 Id is old len
    tO += ms.len + 1                    # Update running token offset to new EOF

var wordCs*: set[char] = {'A'..'Z', 'a'..'z', '0'..'9', '\''}
const upAsc = {'A'..'Z'}                # Insist uppercase in-token; ~10% faster
iterator toks(nm: string): Id =         # Pre-process & tokenize input files
  try:
    let f = Pre.popenr(nm)
    var s = f.readAll; f.close          # Assume any *individual* doc << RAM
    var ms = MSlice(mem: s[0].addr, len: 0)
    var inWord = false                  # Very simple in-word CharSet tokenizer
    for i in 0 ..< s.len:               #..which lowercases as it goes.
      if inWord:                        # Maybe continue word, maybe yield
        if   s[i] in upAsc : s[i] = char(ord(s[i]) + 32); ms.len.inc # -> Lower
        elif s[i] in wordCs: ms.len.inc
        else: inWord = false; yield toId ms
      else:                             # Maybe new word, maybe more ignored
        if s[i] in wordCs:
          inWord = true; s[i] = s[i].toLowerAscii; ms.mem = s[i].addr; ms.len=1
    if inWord: yield toId ms            # Input may end in a valid token
  except: erru &"skipping \"{nm}\": cannot open\n"

proc tf(nm: string): V =                # Map extant tok histo|Parse&count input
  let tfNm = &"{Dir}/{nm}.NIf"          # Extant just mmap()d/demand-paged
  if (let mf = mopen(tfNm, err=nil); mf.mem != nil and      # Binary exists & is
      mf.fi.lastWriteTime > getFileInfo(nm).lastWriteTime): #..newer than src.
    let n = mf.mslc.len div If.sizeof           # Could RO mmap to avoid 1 copy
    result.setLen n                             #..BUT tfIdf unitizes V's & also
    copyMem result[0].addr, mf.mem, n*If.sizeof #..this allocs/returns centroid.
    mf.close                            # Done with file memory
  else:                                 # No ingested file: histogram toks
    var tc: Table[Id, uint32]           # uint32 gives more Ctr saturation range
    for id in nm.toks: tc.mgetOrPut(id, 0u32).inc       # Weight is token count
    for id, c in tc: result.add (id, ln(c.float32) + 1) # Unsure +1 belongs HERE
    result.sort                         # Sort & save data to never parse again
    mkdirTo tfNm; let f = open(tfNm, fmWrite)
    discard f.writeBuffer(result[0].addr, result.len*If.sizeof)
    f.close

iterator paired(x, y: V; na=0f32): (Id, float32, float32) = # SPARSE VECTOR MATH
  var i, j: int                         # Loop over pairs in sorted x,y order
  template xi: untyped = x[i]
  template yj: untyped = y[j]
  while i < x.len and j < y.len:        # Ordered merge (like merge sort)
    if   xi.id == yj.id: yield (xi.id, xi.v, yj.v); inc i; inc j # From both
    elif xi.id  < yj.id: yield (xi.id, xi.v, na  ); inc i        # From x
    else               : yield (yj.id, na  , yj.v); inc j        # From y
  while i < x.len: yield (xi.id, xi.v, na); inc i                # Now each tail
  while j < y.len: yield (yj.id, na, yj.v); inc j

proc dot(x, y: V): float32 =            # Sparse dot product
  var s: float                          # Accumulate in double precision
  for (_, xv, yv) in paired(x, y): s += xv*yv
  s.float32

proc add(y: var V, x: V, a=1f32) =      # Sparse addition: y+=a*x (axpy)
  var y1: V
  for (id, xv, yv) in paired(x, y):
    let y = yv + a*xv
    if y != 0: y1.add (id, y)           # Preserve sparsity (NZ only); Epsilon?
  y = move y1

proc sumSq(x: V): float = (for (_, f) in x: result += f*f)  # `paired` unneeded
proc sum4(x: V): float = (for (_, f) in x: result += f*f*f*f) # Rényi-2 entropy

proc unitizeL2(x: var V) =              # Sparse L2-unitization
  if (var s = x.sumSq; s > 0):          # Sum & Scale
    s = 1.0 / sqrt(s)
    for e in mitems x: e.v *= s         # Re-scale elements of vector

var df = initCountTable[Id]()           # TFIDF DocFreq (#docs containing id)
var lNp1: float                         # A common +1 tf-idf normalizer

proc tfIdf(doc: V): V =                 # Term/Token-freq-Inverse-Doc-Freq
  result = doc
  if lNp1 > ln(2.0):                    # lNp1==ln(2) => ln(df[id]{==1 ∀id}+1)
    for e in mitems result: e.v *= lNp1 - ln(df.getOrDefault(e.id).float + 1)
  unitizeL2 result                      # 1 doc gs+bs=>just normlzd histo vector

proc centroid(docs: seq[V]; renyi2=false): V = # Centroid maker
  for doc in docs: # result.add doc.tfIdf # Use `a` to weight by an entropy
    let v = doc.tfIdf; result.add v, (if renyi2: v.sum4.sqrt else: 1f32)
  unitizeL2 result

proc centroidDiff(gs, bs: seq[V]; renyi2=false): V =
  lNp1 = float(gs.len + bs.len + 1).ln  # Document count is num.for centroids
  for g in gs: (for (id, _) in g: df.inc id)
  for b in bs: (for (id, _) in b: df.inc id)
  result = gs.centroid(renyi2); result.add bs.centroid(renyi2), -1'f32 # G - B

proc naiveBayesW(gs, bs: seq[V]): V =   # Something rather different from tfIdf
  var G, B: V
  (for g in gs: G.add g); (for b in bs: B.add b)
  const α = 0.5'f32                     # Discriminative lnCount model over..
  for (id, g, b) in paired(G, B):       #..compressed TF space NOT "probability"
    let w = ln(g + α) - ln(b + α)
    if w != 0'f32: result.add (id, w)
  unitizeL2 result
# DRIVER program
proc like(pre="", dir=".like", tok=".tok.Dn", word="", fmt="",
          gs: seq[string]= @[], bs: seq[string]= @[], qs: seq[string]) =
  Pre = pre; Dir = dir; Tok = tok       # Apply passed args to globals
  if word.len > 0: (wordCs = {}; for c in word: wordCs.incl c)
  populateTId()                         # Populate token table from .tok
  if gs.len + bs.len == 0: (for q in qs: discard q.tf); return # No GB => ingest
  let fmt = if fmt.len > 0: fmt else: "$nb $q"  # Dfl2 Naive Bayes since fastest
  let gs = collect(for g in gs: g.tf); let bs = collect(for b in bs: b.tf)
  let (doTI, doTR, doNB) = ("$ti" in fmt or "${ti}" in fmt,
                            "$tr" in fmt or "${tr}" in fmt,
                            "$nb" in fmt or "${nb}" in fmt)
  let G_B = if doTI: centroidDiff(gs, bs) else: V0 #G - B centroids
  let GBR = if doTR: centroidDiff(gs, bs, true) else: V0 #G - B  Renyi2centroids
  let nbW = if doNB: naiveBayesW(gs, bs) else: V0 #Naive-Bayes oddsRatio propor.
  for qNm in qs:                        # Score the queries various ways
    var q = qNm.tf                      # Early scores need no q.unitizeL2
    let ti=if doTI: formatFloat(G_B.dot(q.tfIdf), ffDecimal,5) else: "0"
    let tr=if doTR: formatFloat(GBR.dot(q.tfIdf), ffDecimal,5) else: "0"
    let nb=if doNB: (q.unitizeL2;formatFloat(nbW.dot(q), ffDecimal,5)) else: "0"
    echo fmt % ["q", qNm, "ti", ti, "tr", tr, "nb", nb]

when isMainModule: include cligen/mergeCfgEnv; dispatch like, help={
  "pre" : "``catz $1`` preprocesses with *catz*",
  "dir" : "place for metadata(`tok`, foo.NIf, ..)",
  "tok" : "file in `dir` to store/update tokens",
  "word": "in-word char class (\"\" => a-z0-9')",
  "fmt":""""" -> "$nb $q", BUT can do any/all of:
 ti: `q.(G-B)`; [GB]=tfIdf centroids
 tr: `q.(G-B)`; [GB]=tfIdf Renyi2wtCentroids
 nb: `q.nbW` naive Bayes discrim. evidence""",
  "gs"  : "goods - upweight vs. centroid(these)",
  "bs"  : "bads - downweight vs. centroid(these)",
  "qs"  : "paths to score"}, doc="""Similar document system.  Stores tokens as
lines in `.tok.Dn` & (tokId, weight) .NIf files (auto-updated as sources are).
Without `g|b`, only ingest args."""
