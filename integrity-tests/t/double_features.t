# double_features.t


=head1 double_features

This test checks that there are no duplicated feature lines in the
database. The test is closely based on the remedial script
ensembl/misc-scripts/surgery/prune_double_features.pl.
Should this test fail, prune_double_features.pl might prove useful
in fixing the problem.

=cut

## We start with some black magic to print on failure.
BEGIN { $| = 1; print "1..2\n"; 
	use vars qw($loaded); }
END {print "not ok 1\n" unless $loaded;}

use strict;
use lib 't';
use EnsIntegrityDBAdaptor;
$loaded = 1;
print "ok 1\n";		# 1st test passes.

my $dbh = EnsIntegrityDBAdaptor->new();

my $sth = $dbh->prepare( "select internal_id from contig" );
$sth->execute;
my $prune = 0;
my $read = 0;
my @contigs;

while( my $arrref = $sth->fetchrow_arrayref() ) {
  push( @contigs, $arrref->[0] );
}

$sth = $dbh->prepare( "select  id, contig, seq_start, seq_end, score, strand,
                                 analysis, name, hstart, hend, hid, evalue, perc_id, phase, end_phase
                            from feature where contig = ? ");

OUTER:
for( my $i = 0; $i <= $#contigs; $i++ ) {
  my $contig = $contigs[$i];
  my %linehash = ();
  
  $sth->execute( $contig );
  while( my $arrref = $sth->fetchrow_arrayref ) {
    $read++;

    my $hashkey = join( "\t", ((@$arrref)[1..14]) );

    if( exists $linehash{$hashkey} ) {
      $prune++;
      last OUTER;
    } else {
      $linehash{$hashkey} = $arrref->[0];
    }
  }
}

$sth->finish;

if ($prune == 0) {
  print "ok 2\n";
} else {
  print "not ok 2\n";
}
