## Bioperl Test Harness Script for Modules
##

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.t'

#-----------------------------------------------------------------------
## perl test harness expects the following output syntax only!
## 1..3
## ok 1  [not ok 1 (if test fails)]
## 2..3
## ok 2  [not ok 2 (if test fails)]
## 3..3
## ok 3  [not ok 3 (if test fails)]
##
## etc. etc. etc. (continue on for each tested function in the .t file)
#-----------------------------------------------------------------------

# exon.t - tests for exons

# Note: sticky exons are not tested. They should be!

## We start with some black magic to print on failure.
BEGIN { $| = 1; print "1..6\n"; 
	use vars qw($loaded); }
END {print "not ok 1\n" unless $loaded;}

use strict;
use lib 't';
use EnsIntegrityDBAdaptor;
$loaded = 1;
print "ok 1\n";		# 1st test passes.

# Test 3 fails when evidence length exceeds feat. length by this much:
my $margin = 40;	# No special provision is made for protein evidence.
			# This just means that protein evidence that is up to
			# approx. 3 times too long will slip through our net!

my $db = EnsIntegrityDBAdaptor->new();
print "ok 2\n";		# 2nd test passes.

my $first_loop_test = 3;	# Test 3 is the first test in the main loops.
my @failed;	# For tests in main loops, failed[i] "true" if test i failed.

my @contig_ids = $db->get_all_Contig_id;

# Store all nonsticky exon IDs, in a hash of arrays, keyed by contig ID.
# Also store them separately in a contiguous array.

my @nonsticky_exon_id_arr = ();	# array of all non-sticky exon IDs
my $current_exon_id = 0;	# cursor for @nonsticky_exon_id_arr
my $exon_id_cursor = 0;		# Index to @exon_id_arr
my %nonsticky_exon_ids;		# per-contig arrays of nonsticky exon IDs
foreach my $contig_id (@contig_ids)
{
    $nonsticky_exon_ids{$contig_id} = [ () ];	# clear the array of exon IDs
    my $contig;		# current nonvirtual contig object

    # Test 3: each contig must be retrievable.
    # This is not an exon test but we want all contigs and have to trap
    # failure in an eval for the script to continue, so we might as well
    # report on it.
    eval
    {
	$contig = $db->get_Contig($contig_id);
    };
    if ($@)
    {
	$failed[3] = "true";
    }
    else
    {
	my @current_exons = $contig->get_all_Exons;
	foreach my $exon (@current_exons)
	{
	    unless ($exon->isa('Bio::EnsEMBL::StickyExon'))
	    {
		push @{ $nonsticky_exon_ids{$contig_id} }, $exon->id;
		$nonsticky_exon_id_arr[$current_exon_id++] = $exon->id;
	    }
	}
    }
}

# Contig-based test loop. Failure does not prompt early exit, since there are
# several tests and we want to know whether each of these passes or fails.

foreach my $contig_id (@contig_ids)
{
    foreach my $exon_id (@{ $nonsticky_exon_ids{$contig_id} })
    {
	my $exon = $db->gene_Obj->get_Exon($exon_id);

	# Test 4: supporting evidence mustn't be much
	# longer than the evidence it supports.
	$db->gene_Obj->get_supporting_evidence_direct($exon);
	my @features = $exon->each_Supporting_Feature;
	foreach my $feature (@features)
	{
	    my $exon_bases_hit = $feature->length;
	    my $hit_bases_hit = $feature->hend - $feature->hstart;
	    if ($hit_bases_hit > ($exon_bases_hit + $margin))
	    {
		$failed[4] = "true";
	    }
	}

	# Test 5: exon length must be at least 3.
	if ($exon->length < 3)
	{
	    $failed[5] = "true";
	}
    }
}

# Test 6: exon IDs must be unique.
my @sorted_exon_ids = sort @nonsticky_exon_id_arr;
for my $i (1 .. $#sorted_exon_ids)
{
    if ($sorted_exon_ids[$i - 1] eq $sorted_exon_ids[$i])
    {
	$failed[6] = "true";
	last;
    }
}

# Report on test results from main loop.

for my $i ($first_loop_test .. $#failed)
{
    if ($failed[$i])
    {
	print "not ok $i\n";
    }
    else
    {
	print "ok $i\n";
    }
}
