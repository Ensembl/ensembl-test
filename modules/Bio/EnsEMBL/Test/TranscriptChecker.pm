#
# EnsEMBL module for TranscriptChecker
#
# Cared for by Steve Searle <searle@sanger.ac.uk>
#
# Copyright EMBL/EBI 2001
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=pod 

=head1 NAME

Bio::EnsEMBL::Test::TranscriptChecker - Module to check the validity of
a transcript

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 CONTACT

  Steve Searle <searle@sanger.ac.uk>

=head1 APPENDIX

The rest of the documentation details each of the object methods. Internal methods are usually preceded with a _

=cut


# Let the code begin...


package Bio::EnsEMBL::Test::TranscriptChecker;
use vars qw(@ISA $AUTOLOAD);
use strict;

use Bio::EnsEMBL::DBSQL::ExonAdaptor;


@ISA = qw( Bio::Root::RootI );


sub new {
  my ($class, @args) = @_;

  my $self = bless {},$class;

  my ( $transcript, $minshortintronlen, $maxshortintronlen, $minlongintronlen,
       $minshortexonlen, $maxshortexonlen, $minlongexonlen, $maxexonstranscript,
       $mintranslationlen, $ignorewarnings, $vc, $adaptor, 
       $genomestats  ) = $self->_rearrange
	 ( [ qw { TRANSCRIPT  
		  MINSHORTINTRONLEN
		  MAXSHORTINTRONLEN
		  MINLONGINTRONLEN
		  MINSHORTEXONLEN
		  MAXSHORTEXONLEN
		  MINLONGEXONLEN
                  MAXEXONTRANSCRIPT
                  MINTRANSLATIONLEN
                  IGNOREWARNINGS
                  VC
                  ADAPTOR
		  GENOMESTATS
	      }], @args );

  
  if( !defined $transcript ) { 
    $self->throw("Transcript must be set in new for TranscriptChecker")
  }
  $self->transcript($transcript);

  if( defined $minshortintronlen ) { 
    $self->minshortintronlen( $minshortintronlen ); 
  } else {
    $self->minshortintronlen(3); 
  } 
  if( defined $maxshortintronlen ) { 
    $self->maxshortintronlen( $maxshortintronlen ); 
  } else {
    $self->maxshortintronlen(50); 
  } 
  if( defined $minlongintronlen ) { 
    $self->minlongintronlen( $minlongintronlen );
  } else {
    $self->minlongintronlen(100000); 
  } 

  if( defined $minshortexonlen ) { 
    $self->minshortexonlen( $minshortexonlen ); 
  } else {
    $self->minshortexonlen(3); 
  } 
  if( defined $maxshortexonlen ) { 
    $self->maxshortexonlen( $maxshortexonlen ); 
  } else {
    $self->maxshortexonlen(10); 
  } 
  if( defined $minlongexonlen ) { 
    $self->minlongexonlen( $minlongexonlen ); 
  } else {
    $self->minlongexonlen(50000); 
  } 

  if( defined $mintranslationlen ) { 
    $self->mintranslationlen( $mintranslationlen ); 
  } else {
    $self->mintranslationlen(10); 
  } 

  if( defined $maxexonstranscript) { 
    $self->maxexonstranscript( $maxexonstranscript );
  } else {
    $self->maxexonstranscript(150);
  }
  if( defined $ignorewarnings) { $self->ignorewarnings($ignorewarnings); } 
  if( defined $vc) { $self->vc($vc); } 
  if( defined $genomestats ) { $self->genomestats( $genomestats )} 
  if( defined $adaptor ) { $self->adaptor( $adaptor )}

  $self->{_errors} = [];
  $self->{_warnings} = [];

  return $self;
}


sub ignorewarnings {
  my ( $self, $arg ) = @_;
  if( defined $arg ) {
    $self->{_ignorewarnings} = $arg;
  }
  return $self->{_ignorewarnings};
}                                                                               

sub mintranslationlen {
  my ( $self, $arg ) = @_;
  if (defined $arg) {
    $self->{_mintranslationlen} = $arg;
  }
  return $self->{_mintranslationlen};
}

sub maxshortintronlen {
  my ( $self, $arg ) = @_;
  if (defined $arg) {
    $self->{_maxshortintronlen} = $arg;
  }
  return $self->{_maxshortintronlen};
}

sub minshortintronlen {
  my ( $self, $arg ) = @_;
  if (defined $arg) {
    $self->{_minshortintronlen} = $arg;
  }
  return $self->{_minshortintronlen};
}

sub minlongintronlen {
  my ( $self, $arg ) = @_;
  if (defined $arg) {
    $self->{_minlongintronlen} = $arg;
  }
  return $self->{_minlongintronlen};
}

sub maxexonstranscript {
  my ( $self, $arg ) = @_;
  if (defined $arg) {
    $self->{_maxexonstranscript} = $arg;
  }
  return $self->{_maxexonstranscript};
}

sub maxshortexonlen {
  my ( $self, $arg ) = @_;
  if (defined $arg) {
    $self->{_maxshortexonlen} = $arg;
  }
  return $self->{_maxshortexonlen};
}

sub minshortexonlen {
  my ( $self, $arg ) = @_;
  if (defined $arg) {
    $self->{_minshortexonlen} = $arg;
  }
  return $self->{_minshortexonlen};
}

sub minlongexonlen {
  my ( $self, $arg ) = @_;
  if (defined $arg) {
    $self->{_minlongexonlen} = $arg;
  }
  return $self->{_minlongexonlen};
}


sub genomestats {
  my ( $self, $arg ) = @_;
  if (defined $arg) {
    $self->{_genomestats} = $arg;
  }
  return $self->{_genomestats};
}


=head2 transcript
 
 Title   : transcript
 Usage   : $obj->transcript($newval)
 Function:
 Returns : value of transcript
 Args    : newvalue (optional)
 
=cut
 
sub transcript {
   my $self = shift;
   if( @_ ) {
      my $value = shift;
      if (!($value->isa('Bio::EnsEMBL::Transcript'))) {
         $self->throw("transcript passed a non Bio::EnsEMBL::Transcript object\n");
      }
      $self->{_transcript} = $value;
    }
    return $self->{_transcript};
 
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

#Side effect of setting exon adaptor
sub adaptor {
  my ( $self, $arg ) = @_;
  if( defined $arg ) {
    $self->{_adaptor} = $arg;
    $self->exonadaptor(new Bio::EnsEMBL::DBSQL::ExonAdaptor($self->{_adaptor}));
  }
  return $self->{_adaptor};
}                                                                               

sub exonadaptor {
  my ( $self, $arg ) = @_;
  if( defined $arg ) {
    $self->{_exonadaptor} = $arg;
  }
  return $self->{_exonadaptor};
}
 
=head2 add_Error 
 
 Title   : add_Error
 Usage   : $obj->add_Error($newval)
 Function:
 Returns : value of errors
 
 
=cut
 
sub add_Error {
   my $self = shift;
   if( @_ ) {
      my $value = shift;
      push @{$self->{_errors}},$value;
    }
    return @{$self->{_errors}};
}      

sub get_all_Errors {
   my $self = shift;
   if (!defined($self->{_errors})) {
     @{$self->{_errors}} = ();
   }
   return @{$self->{_errors}};
}      

sub add_Warning {
   my $self = shift;
   if( @_ ) {
      my $value = shift;
      push @{$self->{_warnings}},$value;
    }
    return @{$self->{_warnings}};
}      

sub get_all_Warnings {
   my $self = shift;
   if (!defined($self->{_warnings})) {
     @{$self->{_warnings}} = ();
   }
   return @{$self->{_warnings}};
}      

sub has_Errors {
  my $self = shift;

  if (scalar($self->get_all_Errors) || 
      (scalar($self->get_all_Warnings) && !$self->ignorewarnings)) {
    return 1;
  } 
  return 0;
} 

sub output {
  my $self = shift;

  my $transcript = $self->transcript;

  print "\n===\n";
  print "Transcript " . $transcript->dbID . "\n";
  
  my $vcoffset = 0;
  if ($self->vc) {
    $vcoffset = $self->vc->_global_start - 1;
  }

  printf "       %9s %9s %9s\n", "dbID","Start","End";
  foreach my $exon ($transcript->get_all_Exons()) {
    printf "  Exon %9d %9d %9d", $exon->dbID, $exon->start + $vcoffset, $exon->end + $vcoffset;
    if ($exon->isa('Bio::EnsEMBL::StickyExon')) {
      print " STICKY";
    }
    print "\n";
  }

  if (scalar($self->get_all_Errors)) {
    print "\nErrors:\n";
    foreach my $error ($self->get_all_Errors()) {
      print "  " . $error;
    }
  }
  if (scalar($self->get_all_Warnings)) {
    print "\nWarnings:\n";
    foreach my $warning ($self->get_all_Warnings) {
      print "  " . $warning;
    }
  }
  if ($self->adaptor) {
    $self->print_raw_data;
  }
}

sub print_raw_data {
  my $self = shift;

  my $dbId = $self->transcript->dbID;
  my $sgp_type = $self->adaptor->static_golden_path_type;

  my $q = qq(
  SELECT e.exon_id,
         if(sgp.raw_ori=1,(e.seq_start-sgp.raw_start+sgp.chr_start), 
            (sgp.chr_start+sgp.raw_end-e.seq_end)) as start,
         if(sgp.raw_ori=1,(e.seq_end-sgp.raw_start+sgp.chr_start), 
            (sgp.chr_start+sgp.raw_end-e.seq_start)) as end,
         if (sgp.raw_ori=1,e.strand,(-e.strand)) as strand,
         sgp.chr_name,
         abs(e.seq_end-e.seq_start)+1 as length,
         et.rank,
         if(e.exon_id=tl.start_exon_id, (concat(tl.seq_start," (start)",
            if(e.exon_id=tl.end_exon_id,(concat(" ",tl.seq_end," (end)")),
            ("")))),if (e.exon_id=tl.end_exon_id,
            (concat(tl.seq_end," (end)")),(""))) as transcoord,
         if(e.sticky_rank>1,(concat("sticky (rank = ",e.sticky_rank,")")),
            ("")) as sticky
   FROM  translation tl, exon e, transcript tr, exon_transcript et, 
         static_golden_path sgp
   WHERE e.exon_id=et.exon_id AND
         et.transcript_id=tr.transcript_id AND
         sgp.raw_id=e.contig_id AND sgp.type = '$sgp_type' AND
         tr.transcript_id = $dbId AND
         tr.translation_id=tl.translation_id
   ORDER BY et.rank
  );
  my $sth = $self->adaptor->prepare($q) || $self->throw("can't prepare: $q");
  my $res = $sth->execute || $self->throw("can't execute: $q");

  print "\nTranscript data from SQL query:\n";
  printf "%-9s: %-9s %-9s %-15s %-6s %-6s %-4s %-16s %-11s\n",
         "Exon ID", "Start", "End", "Chromosome", "Strand", "Length", 
         "Rank", "Translation_Info", "Sticky_Info";
  while( my ($id, $start, $end, $strand, $chrname, $length, 
             $rank, $transstr, $stickystr)= $sth->fetchrow_array) {
    printf "%9d: %9d %9d %-15s %6d %6d %4d %16s %11s\n",$id, $start, $end, 
           $chrname, $strand, $length, $rank, $transstr, $stickystr;
  }
}


sub check {
  #print "Transcript " . $transcript->dbID . " ";
  my $self = shift;

  my $transcript = $self->transcript; 
  my @exons = $transcript->get_all_Exons();

  my $numexon = scalar(@exons);

  if ($numexon == 0) {
    $self->add_Error("No exons\n", 'noexons');
    return;

  } elsif ($numexon > $self->maxexonstranscript) {
    $self->add_Error("Unusually large number of exons (" . 
                     $numexon . ")\n", 'manyexons');
  }

  
# Sorting is needed because rank is flacky
# This allows other tests to be performed even if ranks are wrong
  my @sortedexons;

  my $transstart;
  my $transend;
  my $vcoffset = 0;
  if ($self->vc) {
    $vcoffset = $self->vc->_global_start - 1;
  }

  if ($exons[0]->strand == 1) {
    @sortedexons = sort {$a->start <=> $b->start} @exons ;
    $transstart = ($sortedexons[0]->start+$vcoffset);
    $transend   = ($sortedexons[$#sortedexons]->end+$vcoffset);
  } else {
    @sortedexons = sort {$b->start <=> $a->start} @exons;
    $transstart = ($sortedexons[$#sortedexons]->start+$vcoffset);
    $transend   = ($sortedexons[0]->end+$vcoffset);
  }

# Check for rank errors
  my $exnum = 0;
  EXON: foreach my $exon (@sortedexons) {
    if ($exon != $exons[$exnum++]) {
      $self->add_Error("Incorrect exon ranks (first at exon " .
                       $exons[$exnum++]->dbID . ")\n".
                       "NOTE: Further error checking (except translations) " . 
                       "done with resorted exons.\n" ,'exonrank');
      last EXON;
    }
  }


  $self->check_Structure(\@sortedexons);

  $self->check_Translation;

  $self->check_UTRs(\@sortedexons);

  #$self->check_Supporting_Evidence(\@sortedexons);
}

sub check_Translation {
  my $self = shift;
  my $pepseq = undef;
  eval {
    $pepseq = $self->transcript->translate; 
  };
  if (defined($pepseq)) {
    my $pepseqstr = $pepseq->seq;
    my $peplen = length($pepseqstr);
    # print "Pep seq = $pepseqstr\n";
    if ($pepseqstr =~ /\*/) {
      $self->add_Error("Translation failed - Translation contains stop codons\n",'transstop');
      return 1; 
    } elsif ($peplen == 0) {
      $self->add_Error("Translation failed - Translation has zero length\n",'transzerolen');
      return 1; 
    } elsif ($peplen < $self->mintranslationlen) {
      $self->add_Error("Short (" . $peplen . " residue) translation\n",'transminlen');
    }
    return 0;
  } else {
    $self->add_Error("Translation failed.\n",'transfail');
    return 1; 
  }
}

sub check_Structure {
  my $self = shift;
  my $sortedexons = shift;

  my $prev_exon = undef;
  foreach my $exon (@$sortedexons) {
    my $exlen = $exon->length;

    if ($exlen >= $self->minshortexonlen && 
        $exlen <= $self->maxshortexonlen) {
      $self->add_Error("Short exon (" . $exlen . 
                       " bases) for exon " . $exon->dbID . "\n", 'shortexon');
    } elsif ($exon->length >= $self->minlongexonlen) {
      $self->add_Error("Long exon (" . $exlen . 
                       " bases) for exon " . $exon->dbID . "\n", 'longexon');
    }  
    if (defined $prev_exon) {
      if ($exon->strand != $prev_exon->strand) {
        $self->add_Error("Exons on different strands\n",'mixedstrands');

      } elsif (($exon->strand == 1 && $exon->start < $prev_exon->end) ||
               ($exon->strand == -1 && $exon->end > $prev_exon->start)) {
        $self->add_Error("Incorrect exon ordering (maybe duplicate exons or embedded exons)\n", 'exonorder');

      } else {
        $self->check_Intron($prev_exon, $exon);
      }
    }
    $prev_exon = $exon;
  }
}

sub check_UTRs {
  my $self = shift;
  my $exons = shift;

  my $translation = $self->transcript->translation;
  my $rank = 0;
  my $trans_start_exon = $translation->start_exon;
  my $found = 0;
  EXON: foreach my $exon (@$exons) {
    if ($exon == $trans_start_exon) {
      $found = 1;
      if ($translation->start > 3 || $rank > 0) {
        my $startcodon = substr($exon->seq->seq,$translation->start-1,3); 
        if ($startcodon ne "ATG") {
          $self->add_Warning("No ATG at five prime of transcript with UTR (has $startcodon)\n");
        } 
      }
      last EXON;
    }
    $rank++;
  }
  if (!$found) {
    $self->add_Error("Didn't find translation->start_exon (" . 
                     $trans_start_exon->dbID .  ")\n");
  }
}

sub check_Supporting_Evidence {
  my $self = shift;
  my $exons = shift;

  if ($self->exonadaptor) {
    my $ea = $self->exonadaptor;
  
    EXON: foreach my $exon (@$exons) {
      $ea->fetch_evidence_by_Exon($exon);
      if (!scalar($exon->each_Supporting_Feature())) {
        $self->add_Error("No supporting evidence for exon ".$exon->dbID ."\n");
      }
    }
  }
}

sub check_Intron {
  my $self = shift;
  my $prev_exon = shift || $self->throw("Prev_exon must be passed");
  my $exon = shift || $self->throw("Exon must be passed");

  my $intron = new Bio::EnsEMBL::Intron();

  $intron->upstream_Exon($prev_exon);
  $intron->downstream_Exon($exon);

  my $intlen = $intron->seq->length;

  if ($intlen >= $self->minshortintronlen && 
      $intlen <= $self->maxshortintronlen) {
    $self->add_Error("Short intron (" . $intlen . 
                     " bases) between exons " . $prev_exon->dbID .
                     " and " . $exon->dbID . "\n", 'shortintron');
  } elsif ($intlen >= $self->minlongintronlen) {
    $self->add_Error("Long intron (" . $intlen . ") between exons " . 
                     $prev_exon->dbID . " and " . $exon->dbID . 
                     "\n", 'longintron');
  }

  if ($intlen >= $self->minshortintronlen) {
    my $intseq = $intron->seq->seq;
    if (substr($intseq,0,2) ne "GT") {
      $self->add_Warning("Non consensus 5' intron splice site sequence (".
                         substr($intseq,0,2) . ") after exon " . 
                         $prev_exon->dbID . "\n", 'noncons5');
    }
    if (substr($intseq,-2,2) ne "AG") {
      $self->add_Warning("Non consensus 3' intron splice site sequence (".
                         substr($intseq,-2,2) . 
                         ") before exon " .  $exon->dbID . "\n", 'noncons3');
    }
  } 
}
