#
# EnsEMBL module for ContigGenesChecker
#
# Cared for by Steve Searle <searle@sanger.ac.uk>
#
# Copyright EMBL/EBI 2001
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=pod 

=head1 NAME

Bio::EnsEMBL::Test::ContigGenesChecker 


=head1 SYNOPSIS
Module to check the validity of a transcript

=head1 DESCRIPTION
Performs various checks on the Genes in a Bio::EnsEMBL::Contig object. These 
should only be checks which are not internal to a particular Gene but instead
dependant on the arrangement of genes on the Contig. These include:
  1. Genes have been clustered correctly
  2. Interlocking Genes
  3. Genes on both strands with overlapping exons.

This class does not use stable_ids but instead dbIDs because stable_ids are
not set until after the gene build.

=head1 CONTACT

  Steve Searle <searle@sanger.ac.uk>

=head1 APPENDIX

The rest of the documentation details each of the object methods. Internal methods are usually preceded with a _

=cut


# Let the code begin...


package Bio::EnsEMBL::Test::ContigGenesChecker;
use vars qw(@ISA $AUTOLOAD);
use strict;

use Bio::EnsEMBL::DBSQL::ExonAdaptor;
use Bio::EnsEMBL::Test::CheckerI;
use Bio::EnsEMBL::Intron;
use Bio::EnsEMBL::Utils::TranscriptCluster;



@ISA = qw( Bio::EnsEMBL::Test::CheckerI );


sub new {
  my ($class, @args) = @_;

  my $self = bless {},$class;

  my ( $contig, $genes, $ignorewarnings, $adaptor, 
       $vc, $genomestats  ) = $self->_rearrange
	 ( [ qw { CONTIG
                  GENES
                  IGNOREWARNINGS
                  ADAPTOR
                  VC 
		  GENOMESTATS
	      }], @args );

  
  if( !defined $contig ) { 
    $self->throw("Contig must be set in new for ContigGenesChecker")
  }
  $self->contig($contig);

  if( !defined $genes ) { 
    $self->throw("Genes must be set in new for ContigGenesChecker")
  }
  $self->genes($genes);

  if( defined $ignorewarnings) { $self->ignorewarnings($ignorewarnings); } 
  if( defined $vc) { $self->vc($vc); } 
  if( defined $genomestats ) { $self->genomestats( $genomestats )} 
  if( defined $adaptor ) { $self->adaptor( $adaptor )}

  $self->{_errors} = [];
  $self->{_warnings} = [];

  return $self;
}


sub genomestats {
  my ( $self, $arg ) = @_;
  if (defined $arg) {
    $self->{_genomestats} = $arg;
  }
  return $self->{_genomestats};
}


=head2 contig
 
 Title   : contig
 Usage   : $obj->contig($newval)
 Function:
 Returns : value of contig
 Args    : newvalue (optional)
 
=cut
 
sub contig {
   my $self = shift;
   if( @_ ) {
      my $value = shift;
      if (!($value->isa('Bio::EnsEMBL::DB::ContigI'))) {
         $self->throw("contig passed a non Bio::EnsEMBL::DB::ContigI object\n");
      }
      $self->{_contig} = $value;
    }
    return $self->{_contig};
 
}

sub vc {
   my $self = shift;
   if( @_ ) {
      my $value = shift;
      if (!($value->isa('Bio::EnsEMBL::Virtual::Contig'))) {
         $self->throw("vc passed a non Bio::EnsEMBL::Virtual::Contig object\n");
      }
      $self->{_vc} = $value;
    }
    return $self->{_vc};
 
}

sub adaptor {
  my ( $self, $arg ) = @_;
  if( defined $arg ) {
    $self->{_adaptor} = $arg;
  }
  return $self->{_adaptor};
}                                                                               

sub genes {
  my ( $self, $arg ) = @_;
  if( defined $arg ) {
    $self->{_genes} = $arg;
  }
  return $self->{_genes};
}                                                                               


sub output {
  my $self = shift;


  $self->SUPER::output;

}


sub check {
  my $self = shift;


  my $corrected_clusters = $self->check_Clustering();

  $self->find_StrandOverlaps();

  $self->find_Interlocks($corrected_clusters);
}

sub check_Clustering {
  my $self = shift;

  my @transcripts_unsorted;
# reject non-translating transcripts
  my $genes = $self->{'_genes'};
  foreach my $gene (@$genes) {
    foreach my $tran ($gene->each_Transcript) {
      push(@transcripts_unsorted, $tran);
    }
  }

  my @transcripts = sort by_transcript_high @transcripts_unsorted;
 
 
  my @clusters;
# clusters transcripts by whether or not any exon overlaps with an exon in 
# another transcript (came from prune in GeneBuilder)
  foreach my $tran (@transcripts) {
    my @matching_clusters;
    my ($trans_start, $trans_end) = $self->_get_start_end($tran);

    # print "transcript limits: $trans_start $trans_end \n";

    CLUSTER: foreach my $cluster (@clusters) {

      #print "Testing against cluster with limits " . $cluster->start .
      #      " to " . $cluster->end . "\n";

      if (!($trans_start > $cluster->end ||
           $trans_end < $cluster->start)) {
        # print "In range\n";
        foreach my $cluster_transcript ($cluster->get_Transcripts()) {
          foreach my $exon1 ($tran->get_all_Exons) {
 
            foreach my $cluster_exon ($cluster_transcript->get_all_Exons) {
              if ($exon1->overlaps($cluster_exon) &&
                  $exon1->strand == $cluster_exon->strand) {
                push (@matching_clusters, $cluster);
                next CLUSTER;
              }
            }
          }
        }
      }
    }                                   

    if (scalar(@matching_clusters) == 0) {
      print STDERR "Found new cluster for " . $tran->dbID . "\n";
      my $newcluster = new Bio::EnsEMBL::Utils::TranscriptCluster;
      $newcluster->put_Transcripts($tran);
      push(@clusters,$newcluster);

    } elsif (scalar(@matching_clusters) == 1) {
      print STDERR "Adding to cluster for " . $tran->dbID . "\n";
      $matching_clusters[0]->put_Transcripts($tran);

    } else {

# Merge the matching clusters into a single cluster
      print STDERR "Merging clusters for " . $tran->dbID . "\n";
      my @new_clusters;
      my $merged_cluster = new Bio::EnsEMBL::Utils::TranscriptCluster;
      foreach my $clust (@matching_clusters) {
        $merged_cluster->put_Transcripts($clust->get_Transcripts);
      }
      $merged_cluster->put_Transcripts($tran);
      push @new_clusters,$merged_cluster;
# Add back non matching clusters
      foreach my $clust (@clusters) {
        my $found = 0;
        MATCHING: foreach my $m_clust (@matching_clusters) {
          if ($clust == $m_clust) {
            $found = 1;
            last MATCHING;
          }
        }
        if (!$found) {
          push @new_clusters,$clust;
        }
      }
      @clusters = @new_clusters;
    }        
  }
  
#Safety checks
  my $ntrans = 0;
  my %trans_check_hash;
  foreach my $cluster (@clusters) {
    $ntrans += scalar($cluster->get_Transcripts);
    foreach my $trans ($cluster->get_Transcripts) {
      if (defined($trans_check_hash{"$trans"})) {
        $self->throw("Transcript " . $trans->dbID . " added twice to clusters\n");
      }
      $trans_check_hash{"$trans"} = 1;
    }
    if (!scalar($cluster->get_Transcripts)) {
      $self->throw("Empty cluster");
    }
  }
  if ($ntrans != scalar(@transcripts)) {
    $self->throw("Not all transcripts have been added into clusters $ntrans and " . scalar(@transcripts). " \n");
  } 
#end safety checks
  
  if (scalar(@clusters) < scalar(@$genes)) {
    $self->add_Error("Reclustering reduced number of genes from " . 
                     scalar(@$genes) . " to " . scalar(@clusters). "\n");
  } elsif (scalar(@clusters) > scalar(@$genes)) {
    $self->add_Error("Reclustering increased number of genes from " . 
                     scalar(@$genes) . " to " . scalar(@clusters). "\n");
  }
  return \@clusters;
}

sub by_transcript_high {
  my $alow;
  my $blow;
  my $ahigh;
  my $bhigh;

  if ($a->start_exon->strand == 1) {
    $alow = $a->start_exon->start;
    $ahigh = $a->end_exon->end;
  } else {
    $alow = $a->end_exon->start;
    $ahigh = $a->start_exon->end;
  }

  if ($b->start_exon->strand == 1) {
    $blow = $b->start_exon->start;
    $bhigh = $b->end_exon->end;
  } else {
    $blow = $b->end_exon->start;
    $bhigh = $b->start_exon->end;
  }

  if ($ahigh != $bhigh) {
    return $ahigh <=> $bhigh;
  } else {
    return $alow <=> $blow;
  }
}

sub by_transcript_low {
  my $alow;
  my $blow;
  my $ahigh;
  my $bhigh;

  if ($a->start_exon->strand == 1) {
    $alow = $a->start_exon->start;
    $ahigh = $a->end_exon->end;
  } else {
    $alow = $a->end_exon->start;
    $ahigh = $a->start_exon->end;
  }

  if ($b->start_exon->strand == 1) {
    $blow = $b->start_exon->start;
    $bhigh = $b->end_exon->end;
  } else {
    $blow = $b->end_exon->start;
    $bhigh = $b->start_exon->end;
  }

  if ($alow != $blow) {
    return $alow <=> $blow;
  } else {
    return $bhigh <=> $ahigh;
  }
}


sub find_Interlocks {
  my $self = shift;
  my $clusters = shift;
  
  my @forward_clusters;
  my @reverse_clusters;

  foreach my $cluster (@$clusters) {
    if ($cluster->strand == 1) { 
      push (@forward_clusters,$cluster);
    } else {
      push (@reverse_clusters,$cluster);
    }
  }

# Now check whether any bounds overlap
  
  for (my $i = 0; $i < scalar(@forward_clusters)-1; $i++) {
    my $cluster1 = $forward_clusters[$i]; 
    for (my $j = $i+1; $j < scalar(@forward_clusters); $j++) {
      my $cluster2 = $forward_clusters[$j]; 
      $self->check_for_interlock($cluster1,$cluster2,"forward");
    }
  }
  for (my $i = 0; $i < scalar(@reverse_clusters)-1; $i++) {
    my $cluster1 = $reverse_clusters[$i]; 
    for (my $j = $i+1; $j < scalar(@reverse_clusters); $j++) {
      my $cluster2 = $reverse_clusters[$j]; 
      $self->check_for_interlock($cluster1,$cluster2,"reverse");
    }
  }
}

sub check_for_interlock {
  my $self = shift;
  my $cluster1 = shift;
  my $cluster2 = shift;
  my $strand_name = shift;

#Check for overlap
  if ($cluster1->overlaps($cluster2)) {

    if (($cluster1->start < $cluster2->start && $cluster1->end < $cluster2->end) ||
        ($cluster1->start > $cluster2->start && $cluster1->end > $cluster2->end)) {
      $self->add_Error("Interlocking genes on the $strand_name strand (bounds ".
                       $cluster1->start . "-" . $cluster1->end . " and ". 
                       $cluster2->start . "-" . $cluster2->end . ")\n");
    } else {
# One of the genes is fully contained within the other, but they can still
# be interlocked if not all of the exons of one gene are contained within
# a single intron in the containing gene
      if ($cluster1->start > $cluster2->start) {
        my $tmp = $cluster1; 
        $cluster1 = $cluster2; 
        $cluster2 = $tmp;
      }
      
      foreach my $trans ($cluster1->get_Transcripts) {
        print "Cluster1 transcript = " . $trans->dbID . "\n";
      }
      foreach my $trans ($cluster2->get_Transcripts) {
        print "Cluster2 transcript = " . $trans->dbID . "\n";
      }
      my @containing_exons_unsort = $self->get_cluster_Exons($cluster1);
      my @contained_exons_unsort = $self->get_cluster_Exons($cluster2);
      my @containing_exons = sort {$a->start <=> $b->start} 
                                @containing_exons_unsort;
      my @contained_exons = sort {$a->start <=> $b->start}
                                @contained_exons_unsort;

      my ($left_exon_first, $right_exon_first) = 
        $self->find_enclosing_Exons(\@containing_exons, $contained_exons[0]);
      my ($left_exon_last, $right_exon_last) = 
        $self->find_enclosing_Exons(\@containing_exons, 
                                    $contained_exons[$#contained_exons]);
      if ($left_exon_first != $left_exon_last || 
          $right_exon_first != $right_exon_last) {
        $self->add_Error("Interlocking enclosed gene on the $strand_name strand (bounds ".
                         $cluster1->start . "-" . $cluster1->end . " and ". 
                         $cluster2->start . "-" . $cluster2->end . ")\n");
      } else {
        $self->add_Warning("Enclosed gene on the $strand_name strand (bounds ".
                         $cluster1->start . "-" . $cluster1->end . " and ". 
                         $cluster2->start . "-" . $cluster2->end . ")\n");
      }
    }
  }
}

sub find_enclosing_Exons {
  my $self = shift;
  my $containing_exons = shift; 
  my $contained_exon = shift; 
  my $left_exon;
  my $right_exon;
  my $left_exon_rank;
  my $right_exon_rank;

  print "Looking for enclosing exons for exon (range " . $contained_exon->start 
        . " to " . $contained_exon->end .")\n";
  my $rank = 0;
  CEXON: foreach my $exon (@$containing_exons) {
    print "Comparing to exon (range " . $exon->start." to ". $exon->end .")\n";
    if ($exon->end < $contained_exon->start) {
      $left_exon = $exon;
      $left_exon_rank = $rank;
      print "Found left\n"; 
    } elsif ($exon->start > $contained_exon->end) {
      $right_exon = $exon;
      $right_exon_rank = $rank;
      print "Found right\n"; 
      last CEXON; 
    } 
    $rank++;
  } 

  if (!defined($left_exon) || !defined($right_exon)) {
    $self->throw("Didn't find enclosing exons - should not be possible\n");
  }
  if ($right_exon_rank != $left_exon_rank+1) {
    $self->throw("Left and right ranks not consecutive - should not be possible\n");
  }
  return ($left_exon, $right_exon);
}

sub get_cluster_Exons {
  my $self = shift;
  my $cluster = shift;
  my %h;

  foreach my $trans ($cluster->get_Transcripts) {
    foreach my $exon ( $trans->get_all_Exons ) {
      $h{"$exon"} = $exon;
    }
  }

  return values %h;
}


sub find_StrandOverlaps {
  my $self = shift;

#Get all the exons in all the genes
#Split into two arrays on strand
#Sort low to high in both
#Look for overlaps

  my @forward_exons; 
  my @reverse_exons; 
  my $genes = $self->{'_genes'};
  foreach my $gene (@$genes) {
    my @gene_exons = $gene->get_all_Exons;
    if (scalar(@gene_exons)) {
      my $strand = $gene_exons[0]->strand;
      foreach my $exon (@gene_exons) {
        if ($strand != $exon->strand) {
          $self->add_Error("Gene ". $gene->dbID . 
                           " has exons on different strands\n");
        }
        if ($exon->strand == 1) { 
          push (@forward_exons,$exon);
        } elsif ($exon->strand == -1) { 
          push (@reverse_exons,$exon);
        } else {
          $self->add_Error("Gene ". $gene->dbID . 
                           " has an unstranded exon (" . $exon->dbID . ")\n");
        }
      }
    } else {
      $self->add_Error("Gene ". $gene->dbID . " has no exons\n");
    }
  }

  my @sorted_forward_exons = sort { $a->start <=> $b->start } @forward_exons;
  my @sorted_reverse_exons = sort { $a->start <=> $b->start } @reverse_exons;

#This can be optimised further
  FEXON: foreach my $f_exon (@sorted_forward_exons) {
    foreach my $r_exon (@sorted_reverse_exons) {
      if ($r_exon->overlaps($f_exon)) {
        $self->add_Error("Overlapping exons on two strands for exons ". 
                          $f_exon->dbID . " and " . $r_exon->dbID ."\n");
      }
      if ($r_exon->start > $f_exon->end) {
        next FEXON;
      } 
    }
  }
}

sub _get_start_end {
  my ($self, $transcript) = @_;
  my $start;
  my $end;
 
  my $start_exon = $transcript->start_exon;
  my $end_exon = $transcript->end_exon;
 
  if ($start_exon->strand == 1) {
    $start = $start_exon->start;
    $end   = $end_exon->end;
  } else {
    $end   = $start_exon->end;
    $start = $end_exon->start;
  }
  return ($start, $end);
}   

