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

# Currently, the only important test performed is a check that the
# supporting hit for an exon fragment is not outrageously larger than
# the supported exon fragment. More code will be added soon.
#
# Note: sticky exons are ignored at the moment.


## We start with some black magic to print on failure.
BEGIN { $| = 1; print "1..3\n"; 
	use vars qw($loaded); }
END {print "not ok 1\n" unless $loaded;}

use strict;
use lib 't';
use EnsIntegrityDBAdaptor;
$loaded = 1;
print "ok 1\n";		# 1st test passes.

# fail when exon evidence length exceeds feature length by this factor:
my $cutoff = 6.0;	# I just guessed a reasonable number - DB

my $db = EnsIntegrityDBAdaptor->new();
print "ok 2\n";		# 2nd test passes.

my $failed = "false";	# "true" if main test fails.
my @clone_ids = $db->get_all_Clone_id;

OUTER:
foreach my $clone_id (@clone_ids)
{
    my $clone = $db->get_Clone($clone_id);
    my @contigs = $clone->get_all_Contigs;
    foreach my $contig (@contigs)
    {
        my @genes = $contig->get_all_Genes;
        foreach my $gene (@genes)
        {
            my @exons = $gene->each_unique_Exon;
            foreach my $exon (@exons)
            {
                if (!($exon->isa('Bio::EnsEMBL::StickyExon')))
                {
		    $db->gene_Obj->get_supporting_evidence_direct($exon);
                    my @features = $exon->each_Supporting_Feature;
                    foreach my $feature (@features)
                    {
                        my $exon_bases_hit = $feature->length;
                        my $hit_bases_hit = $feature->hend - $feature->hstart;
			if ($hit_bases_hit > ($cutoff * $exon_bases_hit))
			{
			    print "not ok 3\n";
			    $failed = "true";
			    last OUTER;
			}
                    }
                }
            }
        }
    }
}

if ($failed eq "false")
{
    print "ok 3\n";
}
