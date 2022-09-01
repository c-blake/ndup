Overview
--------

Finding strictly duplicate files is a pretty straightforward problem with most
optimization opportunities being just filesystem size filtering and IO things.
Finding only "near duplicate" files is far more subtle, but there are many
applications - plagiarism detection, automatic related work finding, clean up
of chaotically duplicated files, probably with human inspection in the loop.

Choices
-------

Choices to define "near" abound.  Each has various false positive|negative rates
in various settings.  Here "false" itself is relative to other, possibly "know
it when I see it"/subjective assessments.  Computational complexity of nearness
definitions, such as edit distance, can present new challenges.  Since answers
to these questions are unclear & likely very context dependent, this package is
more a toolkit/framework to research methods on various collections rather than
a "turn key solution".

Core Idea
---------

[The rsync/Spam Sum algorithm](https://rsync.samba.org/tech_report/) relates to
the core idea.  That & [LBFS](http://www.sosp.org/2001/papers/mazieres.pdf) was
my personal inspiration. { There is also this 2006 paper by [Jesse Kornblum I
read](https://www.sciencedirect.com/science/article/pii/S1742287606000764) that
I found around 10 years ago when I first worked on this.  I haven't really dived
into more recent academic work.  References are welcome. }

The core idea of all the above is context-sensitive variable size frames (rather
than fixed size blocks) decided by when the lower N bits of a [rolling
hash](https://en.wikipedia.org/wiki/Rolling_hash) (I use Bob Uzgalis' BuzHash
for its extreme simplicity) matches some fixed value.  A more collision-resistant
hash is used for frame identity hash once boundaries have been decided this way.
There are fine points to the digesting process like minimum block/file sizes,
but this core digesting idea is simple & powerful.  It is elaborated upon in the
papers referred to above, but what it prevents is effects like "edit the first
byte & shift everything" that come up in fixed length block-oriented ideas.

Depending upon "how near" files in a collection are, you will get more or fewer
exact frame matches for "similar" files.  Set intersection thresholds (roughly
[Jaccard similarity](https://en.wikipedia.org/wiki/Jaccard_index)) alone are
pretty good, but one can also do slower edit distances {TODO: need to port or
just maybe just call `cligen/textUt.distDamerau`}.  Similarity thresholds/knobs
need to be user-driven/tunable since use cases determine desirability of false
positive-negative trade-offs.

Maybe Novel Wrinkle
-------------------

One thing I came up with myself (but may have prior work somewhere) that is
more|less unique to the near duplicate use-case is *multiple statistically
independent framings*.  This is essentially a mitigation for "unlucky" framing.
Concretely, you can pick different values or different seeds for the BuzHash
Sbox to get entirely independent frames.  Then you can consider two or more
files (with *the same* framing rules) according to N samples (5..12 work ok).
Only files considered "related" according to some "vote" among the samples are
deemed actually related.  Of course, one can also have *un*lucky framing.  So, a
vote threshold of 4/5 or something makes more sense than requiring unanimity.
Depending upon the vote threshold, this seems to boost the sensitivity (lower
false negatives) without adverse false positive creation. { TODO: I automated
this in a C version, and almost all bits & pieces are present in the Nim port,
but I must close a few loops to finish this. }  This really needs a reference
solution in an organic context for proper evaluation {TODO}.

Evaluation
----------

While no test data set is perfect, an ArpaNet/InterNet Request For Comment (RFC)
collection is nice for many reasons.  It's a public dataset with clear right to
distribute.  It is just small enough to perhaps be humanly manageable.  Spanning
a half century, it exhibits fairly organic chaos.  On the other hand, textual
patterns like '^Obsoletes: NUMBERS', cross-refs, some standards showing up as
drafts earlier all afford defining results which "should" be found by "sensitive
enough" near duplicate detectors (false negative rates).  Meanwhile, in a weak
sense, the entire set notionally relates "somehow" (being about the same "super
topic").  This topical similarity affords studying false discovery rate controls
from "tight similarity" all the way to "very loose".  The 9200 document set size
is small enough to enable rapid idea iteration yet also large enough to be
relevant for performance on larger data sets.  E.g. 9200^2/2=43e6 naive file
comparisons which show off the power of the inverted index optimization which is
over 500X less work with default parameters.

As mentioned in "Choices" and "Core Idea" above, evaluation is hard since there
is neither a fully objective answer and there may be several axes of degrees of
similarity.
