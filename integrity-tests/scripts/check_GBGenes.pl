#!/usr/local/bin/perl5.6.1 -w

# Script to check the integrity of the genes in an Ensembl database 
# or a subset of them.

# Maintained by:  Steve Searle (searle@sanger.ac.uk)

use strict;
use Bio::SeqIO;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Transcript;
use Bio::EnsEMBL::Test::TranscriptChecker;

use Getopt::Long;

BEGIN {
    require "Bio/EnsEMBL/Pipeline/GB_conf.pl";
} 


$| = 1;

my $dbhost = $::db_conf{'finaldbhost'} || undef;
my $dbname = $::db_conf{'finaldbname'} || undef;
my $dbuser = $::db_conf{'dbuser'} || 'ensro';
my $dbpass = $::db_conf{'dbpass'} || ''; 

my $gpname = $::db_conf{'golden_path'} || undef; 

#Should be length of segments in which genes are built
my $vclen = $::scripts_conf{'size'} || 5000000;

my $maxshortintronlen =  $::verify_conf{'maxshortintronlen'} || 50;
my $minshortintronlen =  $::verify_conf{'minshortintronlen'} || 3;
my $minlongintronlen  =  $::verify_conf{'minlongintronlen'} || 100000;

my $maxexonstranscript =  $::verify_conf{'maxexonstranscript'} || 150;

my $maxshortexonlen  =  $::verify_conf{'maxshortexonlen'} || 10;
my $minshortexonlen  =  $::verify_conf{'minshortexonlen'} || 3;
my $minlongexonlen   =  $::verify_conf{'minlongexonlen'} || 50000;

my $maxtranscripts =  $::verify_conf{'maxtranscripts'} || 10; 

my $mintranslationlen =  $::verify_conf{'mintranslationlen'} || 10; 

my $ignorewarnings =  $::verify_conf{'ignorewarnings'} || 0; 
my @chromosomes;

my $chrstart = 1;

my $dnadbname = "";
my $dnadbhost = "";

&GetOptions(
            'dbhost:s'         => \$dbhost,
            'dbuser:s'         => \$dbuser,
            'dbpass:s'         => \$dbpass,
            'dbname:s'         => \$dbname,
            'dnadbhost:s'      => \$dnadbhost,
            'dnadbname:s'      => \$dnadbname,
            'goldenpath:s'     => \$gpname,
            'vclen:n'          => \$vclen,
            'ignorewarnings:n' => \$ignorewarnings,
            'chromosomes:s'    => \@chromosomes,
            'start:n'          => \$chrstart 
           );

if (!defined($dbhost) || !defined($dbname) || !defined($gpname)) {
  die "ERROR: Must at least set dbhost (-dbhost), dbname (-dbname) and golden path type (-goldenpath)\n".
      "       (options can also be set in GB_conf.pl)\n";
}

if (scalar(@chromosomes)) {
  @chromosomes = split(/,/,join(',',@chromosomes));
}


my $db = new Bio::EnsEMBL::DBSQL::DBAdaptor(-host => $dbhost,
                                            -user => $dbuser,
                                            -dbname => $dbname,
                                            -dbpass => $dbpass);
                                            

$db->static_golden_path_type($gpname);
if ($dnadbname ne "") {

  my $host = $dnadbhost;
  if ($host eq "") {
    $host = $dbhost;
  }

  my $dnadbase = new Bio::EnsEMBL::DBSQL::DBAdaptor(
                                                -host             => $host,
                                                -user             => $dbuser,
                                                -dbname           => $dnadbname,
                                                -pass             => $dbpass,
                                                );
  $db->dnadb($dnadbase);
}

my $sgp = $db->get_StaticGoldenPathAdaptor();

my $chrhash = get_chrlengths($dbhost,$dbuser,$dbname);

#hackery 
if (scalar(@chromosomes)) {
  foreach my $chr (@chromosomes) {
    if (!defined($chrhash->{$chr})) {
      die "Didn't find chromosome named $chr in database $dbname\n";
    }
  }
  HASH: foreach my $chr_from_hash (keys %$chrhash) {
    foreach my $chr (@chromosomes) {
      if ($chr_from_hash eq $chr) {next HASH;}
    }
    delete($chrhash->{$chr_from_hash});
  }
}

my @failed_transcripts;

my $total_transcripts_with_errors = 0;
my $total_genes_with_errors = 0;
my $total_genes = 0;
my $total_transcripts = 0;

foreach my $chr (sort bychrnum keys %$chrhash) {

  for (my $start=$chrstart; $start <= $chrhash->{$chr}; $start+=$vclen) {
    my $end = $start + $vclen - 1;
    if ($end > $chrhash->{$chr}) { $end = $chrhash->{$chr}; }

    print "VC = " . $chr . " " . $start . " " . $end . "\n";
    my $vc = $sgp->fetch_VirtualContig_by_chr_start_end($chr,$start,$end);
  
  
    my $vcoffset = $start-1;
  
    my $genestart = 1000000000;
    my $geneend   = -1;
  
    my @genes = $vc->get_all_Genes();

    GENE: foreach my $gene (@genes) {
  
      my @trans = $gene->each_Transcript();
      $total_genes++;
  
      my $nwitherror = 0;
      if (scalar(@trans) == 0) {
        print_geneheader($gene);
        print "ERROR: Gene " . $gene->dbID . " has no transcripts\n";
        $total_genes_with_errors++;
        $nwitherror=1; 
      } elsif (scalar(@trans) > $maxtranscripts) {
        print_geneheader($gene);
        print "ERROR: Gene " . $gene->dbID . 
              " has an unexpected large number of transcripts (" .
              scalar(@trans) . ")\n";
        $total_genes_with_errors++;
        $nwitherror=1; 
      }
  
      TRANSCRIPT: foreach my $transcript (@trans) {
        $total_transcripts++;
        my $tc = new 
    Bio::EnsEMBL::Pipeline::TranscriptChecker(-transcript => $transcript,
                                     -minshortintronlen => $minshortintronlen,
                                     -maxshortintronlen => $maxshortintronlen,
                                     -minlongintronlen => $minlongintronlen,
                                     -minshortexonlen => $minshortexonlen,
                                     -maxshortexonlen => $maxshortexonlen,
                                     -minlongexonlen => $minlongexonlen,
                                     -mintranslationlen => $mintranslationlen,
                                     -maxexonstranscript => $maxexonstranscript,
                                     -ignorewarnings => $ignorewarnings,
                                     -adaptor => $db, 
                                     -vc => $vc);
        $tc->check;

        if ($tc->has_Errors()) {
          $total_transcripts_with_errors++;
          if (!$nwitherror) {
            print_geneheader($gene);
           $total_genes_with_errors++;
          }
          $tc->output;
          # Don't store for now!!!  push @failed_transcripts,$tc;
          $nwitherror++;
        }
      }
    }
  }
}

print "Summary:\n";
print "Number of genes checked           = $total_genes\n";
print "Number of transcripts checked     = $total_transcripts\n\n";
print "Number of transcripts with errors = $total_transcripts_with_errors\n";
print "Number of genes with errors       = $total_genes_with_errors\n\n";


sub print_geneheader {
  my $gene = shift;

  print "\n++++++++++++++++++++++++++++\n";
  print "Gene " . $gene->dbID . "\n";
}

sub get_chrlengths{
  my $host = shift;
  my $user = shift;
  my $dbname = shift;
  my %chrhash;
  my $db = new Bio::EnsEMBL::DBSQL::DBAdaptor(-host   => $host,
                                              -user   => $user,
                                              -dbname => $dbname
                                             );
  my $q = "SELECT chr_name,max(chr_end) FROM static_golden_path GROUP BY chr_name";
 
  my $sth = $db->prepare($q) || $db->throw("can't prepare: $q");
  my $res = $sth->execute || $db->throw("can't execute: $q");
 
  while( my ($chr, $length) = $sth->fetchrow_array) {
    $chrhash{$chr} = $length;
  }
  return \%chrhash;
}   


sub bychrnum {

  my @awords = split /_/,$a;
  my @bwords = split /_/,$b;

  my $anum = $awords[0];
  my $bnum = $bwords[0];

#  if ($anum !~ /^chr/ || $bnum !~ /^chr/) {
#    die "Chr name doesn't begin with chr for $a or $b";
#  }
   
  $anum =~ s/chr//;
  $bnum =~ s/chr//;

  if ($anum !~ /^[0-9]*$/) {
    if ($bnum !~ /^[0-9]*$/) {
      return $anum cmp $bnum;
    } else {
      return 1;
    }
  }
  if ($bnum !~ /^[0-9]*$/) {
    return -1;
  }

  if ($anum <=> $bnum) {
    return $anum <=> $bnum;
  } else {
    if ($#awords == 0) {
      return -1;
    } elsif ($#bwords == 0) {
      return 1;
    } else {
      return $awords[1] cmp $bwords[1];
    }
  }
}

