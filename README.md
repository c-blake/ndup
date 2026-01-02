# Overview
Finding strictly duplicate files is [a pretty
straightforward](https://github.com/c-blake/cligen/blob/master/examples/dups.nim)
problem with most optimization opportunities being just filesystem size
filtering and IO things.  Finding only "near duplicate" files is far more
subtle, but there are many applications - plagiarism detection, automatic
related work finding, clean up of chaotically duplicated files, probably with
human inspection in the loop.

# Choices
Choices to define "near" abound.  Each has various false positive|negative rates
in various settings.  Here "false" itself is relative to other, possibly "know
it when I see it"/subjective assessments.  Computational complexity of nearness
definitions, such as edit distance, can present new challenges.  Since answers
to these questions are unclear & likely very context dependent, this package is
more a toolkit/framework to research methods on various collections rather than
a "turn key solution".

# Core Idea
The idea here relates to the less well known [Udi
Manber](https://en.wikipedia.org/wiki/Udi_Manber) 1993/94
[`sif`](https://dl.acm.org/doi/abs/10.5555/1267074.1267076) tool which was
quickly followed by the [rsync/Spam Sum
algorithm](https://rsync.samba.org/tech_report/).  My personal inspiration was
[LBFS](http://www.sosp.org/2001/papers/mazieres.pdf).  { There is also a [2006
paper](https://www.sciencedirect.com/science/article/pii/S1742287606000764) by
Jesse Kornblum that I found around 2012 when I first worked on this.  I haven't
looked into more recent academic work.  References are welcome. }

The core idea of all the above is context-sensitive variable size frames (rather
than fixed size blocks) decided by when the lower N bits of a [rolling
hash](https://en.wikipedia.org/wiki/Rolling_hash) (I use Bob Uzgalis' BuzHash
for its extreme simplicity) matches some fixed value.  Once framing has been so
decided, a more collision-resistant hash is used for frame identity.  There are
fine points to the digesting process like minimum block/file sizes, but this
core digesting idea is simple & powerful.  It is elaborated upon in the papers
mentioned above.  What it prevents is effects like "edit the first byte & shift
everything" that come up in fixed length block-oriented ideas.  Sometimes this
is now called "Content-Defined Chunking" or CDC.

Depending upon "how near" files in a collection are, you will get more or fewer
exact frame matches for "similar" files.  Set intersection thresholds (roughly
[Jaccard similarity](https://en.wikipedia.org/wiki/Jaccard_index)) alone are
pretty good, but one can also do slower edit distances {TODO: need to port or
just maybe just call `cligen/textUt.distDamerau`}.  Similarity thresholds/knobs
need to be user-driven/tunable since use cases determine desirability of false
positive-negative trade-offs.

# Maybe Novel & Interesting Wrinkle
Unlike a fully automated context, near duplicate systems may be able to have
"iterated by a human in the loop" deployment.  One thing I came up with myself
(but may have prior work somewhere) is *multiple statistically independent
framings*.  This can mitigate "unlucky framing".  Concretely, you can pick
different matching values (or different seeds for BuzHash Sboxes) to get
entirely independent framings.  Then you can consider two or more files (with
*the same* framing rules) according to N samples (5..12 work ok).  This idea is
more salient to the near duplicate use-case where an end-user may want to tune
false positive rates.

Of course, one can also get "lucky framing" & want to automate multiple trials
with voting, say a threshold of 4/5 or something.  Depending upon thresholds,
this seems to boost sensitivity (fewer false negatives) without much adverse
false positive creation. {TODO: I automated this in a C version, and almost all
bits & pieces are present in the Nim port, but I must close a few loops to
finish this.}  This really needs a reference solution in an organic context for
proper evaluation {TODO}.

# Evaluation
While no test data set is perfect, an ArpaNet/InterNet Request For Comment (RFC)
collection is nice for many reasons.  It's a public dataset with clear right to
distribute.  It is just small enough to perhaps be humanly manageable.  Spanning
a half century, it exhibits fairly organic chaos.  On the other hand, textual
patterns like '^Obsoletes: NUMBERS', cross-refs, some standards showing up as
drafts earlier all afford defining results which "should" be found by "sensitive
enough" near duplicate detectors (false negative rates).

Meanwhile, in a weak sense, the entire document set notionally relates "somehow"
(being "About The Internet").  This topical similarity enables studying false
discovery rate controls from "tight similarity" all the way to "very loose".
9200 documents is small enough to enable rapid idea iteration yet big enough to
be performance-relevant.  E.g. 9200^2/2=43e6 naive file comparisons shows off
the inverted index optimization (over 500X less work with default parameters).

As mentioned in "Choices" and "Core Idea" above, evaluation is hard since there
is neither a fully objective answer and there may be several axes of degrees of
similarity.
