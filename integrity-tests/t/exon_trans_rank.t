# exon_trans_rank.t      Michael Kirk    2001
#

=head1 exon_tran_rank;

This test is intended as a check on the "rank" field
in the exon_transcript table. This field is supposed
to give the 5' to 3' ordering of exons within a transcript.

A corollary of these semantics are that for any
exons in the same transcript and the same contig, the ordering
given by the exon:seq_start field should match that given
by the exon_transcript:rank field.

Of course if errors are detected, the fault could be
in the exon:seq_start values as well.

=cut


## We start with some black magic to print on failure.
BEGIN { $| = 1; print "1..2\n"; 
	use vars qw($loaded); }
END {print "not ok 1\n" unless $loaded;}

use lib 't';
use TestSupport;
$loaded = 1;
print "ok 1\n";		# 1st test passes.

# commented code calls zero_count_test in such a way that it is highly
# likely to pass, and this may be useful for testing purposes
#TestSupport::zero_count_test("
#    select count(*)
#    from   exon
#    where  id = 'moses'", 2);

TestSupport::zero_count_test("
    select count(*)
    from   exon_transcript et1, exon_transcript et2, exon e1, exon e2
    where  et1.exon = e1.id and et2.exon = e2.id
      and  et1.transcript = et2.transcript
      and  et2.rank = et1.rank + 1
      and  e1.contig = e2.contig
      and  (e1.strand * e1.seq_start) >= (e1.strand * e2.seq_start)
    ", 2);
