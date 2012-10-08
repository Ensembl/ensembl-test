#!/usr/bin/env perl

=pod
my $json = <<'JSON';
{
  "human" : {
    "core" : {
      "regions" : [
        ["6", 1000000, 2000000],
        ["X", 1, 3000000],
        ["Y", 1, 100000],
        ["Y", 2649521, 4000000]
      ],
      "adaptors" : [
        { "name" : "gene", "method" : "fetch_all_by_Slice", "args" : [] },
        { "name" : "repeatfeature" }
      ]
    }
  }
}
JSON
=cut

use strict;
use warnings;

use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::DBSQL::DBConnection;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Test::DumpDatabase;
use Bio::EnsEMBL::Utils::IO qw/slurp/;
use File::Temp qw/tempfile/;
use Getopt::Long qw/:config no_ignore_case/;
use JSON;
use Pod::Usage;
use POSIX;
use Scalar::Util qw/looks_like_number/;

run();

sub run {
  my $self = bless({}, __PACKAGE__);
  $self->parse_options();
  $self->load_registry();
  $self->load_json();
  $self->process();
}

sub parse_options {
  my ($self) = @_;
  my $opts = {
    port => 3306,
    user => 'ensro',
    dest_port => 3306
  };
  
  GetOptions($opts, qw/
    host|hostname|h=s
    port|P=i
    user|username|u=s
    pass|password|p=s
    dbname|database|db=s
    species=s
    
    dest_host|dest_hostname|dh=s
    dest_port|dP=i
    dest_user|dest_username|du=s
    dest_pass|dest_password|dp=s
    
    registry|reg_conf=s
    
    json=s
    
    directory=s
    drop_database
  /) or pod2usage(-msg => 'Misconfigured options given', -verbose => 1, -exitval => 1);
  return $self->{opts} = $opts;
}

sub load_registry {
  my ($self) = @_;
  my $opts = $self->{opts};
  if($opts->{registry}) {
    print STDERR "Loading from registry\n";
    Bio::EnsEMBL::Registry->load_all($opts->{registry});
  }
  elsif($opts->{host} && $opts->{port} && $opts->{user} && $opts->{dbname}) {
    my %args = (
      -HOST => $opts->{host}, -PORT => $opts->{port},
      -USER => $opts->{user}, -DBNAME => $opts->{dbname},
      -SPECIES => $opts->{species}
    );
    $args{-PASS} = $opts->{pass};
    Bio::EnsEMBL::DBSQL::DBAdaptor->new(%args);
  }
  else {
    pod2usage(-msg => 'Misconfigured source database. Please give a -registry file or -host, -port, -user, -dbname and -species', -verbose => 1, -exitval => 1);
  }
  return;
}

sub target_dbc {
  my ($self) = @_;
  my $opts = $self->{opts};
  if(!$opts->{dest_host} && !$opts->{dest_user}) {
    pod2usage(-msg => 'Misconfigured target database. Please give a -dest_host, -dest_port, -dest_user ', -verbose => 1, -exitval => 1);
  }
  my %args = (
    -HOST => $opts->{dest_host}, -PORT => $opts->{dest_port},
    -USER => $opts->{dest_user}
  );
  $args{-PASS} = $opts->{dest_pass} if $opts->{dest_pass};
  return $self->{dbc} = Bio::EnsEMBL::DBSQL::DBConnection->new(%args);
}

sub load_json {
  my ($self) = @_;
  my $json = $self->{opts}->{json};
  pod2usage(-msg => 'No -json configuration given', -verbose => 1, -exitval => 1) unless $json;
  pod2usage(-msg => "JSON location $json does not exist", -verbose => 1, -exitval => 1) unless -f $json;
  my $slurp = slurp($json);
  return $self->{json} = decode_json($slurp);
}

sub process {
  my ($self) = @_;
  my $dbc = $self->target_dbc();
  my $config_hash = $self->{json};
  
  foreach my $species (keys %{$config_hash}) {
    foreach my $group (keys %{$config_hash->{$species}}) {
      my $from = Bio::EnsEMBL::Registry->get_DBAdaptor($species, $group);
      my $info = $config_hash->{$species}->{$group};
      my $regions = $info->{regions};
      my $adaptors = $info->{adaptors};
      my $to = $self->copy_database_structure($species, $group, $dbc);
      $self->copy_globals($from, $to);
      my $slices = $self->copy_regions($from, $to, $regions);
      foreach my $adaptor_info (@{$adaptors}) {
        $self->copy_features($from, $to, $slices, $adaptor_info);
      }
      $self->dump_database($to);
      $self->drop_database($to);
    }
  }
}

sub dump_database {
  my ($self, $dba) = @_;
  my $dir = $self->{opts}->{directory}; 
  if($dir) {
    print STDERR "Directory given; will dump database to this location\n";
    my $dumper = Bio::EnsEMBL::Test::DumpDatabase->new($dba, $dir);
    $dumper->dump();
  }
  return;
}

sub drop_database {
  my ($self, $dba) = @_;
  if($self->{opts}->{drop_database}) {
    print STDERR "Dropping the database\n";
    my $dbc = $dba->dbc();
    my $db = $dbc->dbname;
    $dbc->do('drop database '.$db);
    delete $dbc->{dbname};
    $dbc->disconnect_if_idle();
  }
  return;
}

sub copy_globals {
  my ($self, $from, $to) = @_;
  my @tables = qw/attrib_type meta coord_system external_db/;
  $self->copy_all_data($from, $to, $_) for @tables;
  return;
}

# Starts the copy across of Slices
sub copy_regions {
  my ($self, $from, $to, $regions) = @_;
  my $coord_sql = "select name, coord_system_id from coord_system";
  my $coord_systems = $to->dbc->sql_helper()->execute_into_hash(-SQL => $coord_sql);

  my $slice_adaptor = $from->get_adaptor("Slice");
  my $seq_region_names;

  # Grab all toplevel slices and record those IDs which need to be
  # transferred for the  
  my @toplevel_slices;
  my %seq_region_id_list;
  foreach my $region (@{$regions}) {
    my ($name, $start, $end) = @{$region};
    #Make the assumption that the core API is OK and that the 3 levels of assembly are chromosome, supercontig and contig
    my $slice = $slice_adaptor->fetch_by_region('toplevel', $name, $start, $end);
    if(! defined $slice) {
      print STDERR "Could not find a slice for $name .. $start .. $end\n";
    }
    push(@toplevel_slices, $slice);

    my $supercontigs;

    #May not always have supercontigs
    if ( $coord_systems->{'supercontig'} ) {
      $supercontigs = $slice->project('supercontig');
      foreach my $supercontig (@$supercontigs) {
        my $supercontig_slice = $supercontig->[2];
        $seq_region_id_list{$supercontig_slice->get_seq_region_id} = 1;
      }
    }

    #Assume always have contigs
    my $contigs = $slice->project('contig');
    foreach my $contig (@$contigs) {
      my $contig_slice = $contig->[2];
      $seq_region_id_list{$contig_slice->get_seq_region_id} = 1;
    }
    
  }
  
  #Copy the information about each contig/supercontig's assembly 
  my $seq_region_ids = join(q{,}, keys %seq_region_id_list);
  my $sr_query = "SELECT a.* FROM seq_region s JOIN assembly a ON (s.seq_region_id = a.cmp_seq_region_id) WHERE seq_region_id IN ($seq_region_ids)";
  $self->copy_data($from, $to, "assembly", $sr_query);
  
  #Grab the copied IDs from the target DB & use this to drive the copy of assembly exceptions
  my $asm_sr_ids = $self->get_ids($to, 'asm_seq_region_id','assembly');
  my $cmp_sr_ids = $self->get_ids($to, 'cmp_seq_region_id','assembly');
  my $asm_cmp_ids = join(q{,}, @{$asm_sr_ids}, @{$cmp_sr_ids});
  $self->copy_data($from, $to, 'assembly_exception', "SELECT * FROM assembly_exception WHERE seq_region_id in ($asm_cmp_ids)");
  
  #Now transfer all seq_regions from seq_region into the new DB
  my @seq_regions_to_copy = (@{$asm_sr_ids}, @{$cmp_sr_ids}), map { $_->get_seq_region_id() } @toplevel_slices;
  my $seq_regions_to_copy_in = join(q{,}, @seq_regions_to_copy);
  $self->copy_data($from, $to, 'seq_region', "SELECT * FROM seq_region WHERE seq_region_id in ($seq_regions_to_copy_in)");
  $self->copy_data($from, $to, 'seq_region_attrib', "SELECT * FROM seq_region_attrib WHERE seq_region_id in ($seq_regions_to_copy_in)");
  $self->copy_data($from, $to, 'dna', "SELECT * FROM dna WHERE seq_region_id in ($seq_regions_to_copy_in)");
  
  return \@toplevel_slices;
}

sub copy_features {
  my ($self, $from, $to, $slices, $adaptor_info) = @_;
  my $name = $adaptor_info->{name};
  print STDERR "Copying $name features\n";
  my $from_adaptor = $from->get_adaptor($name);
  my $to_adaptor = $to->get_adaptor($name);
  my $method = $adaptor_info->{method} || 'fetch_all_by_Slice';
  my $args = $adaptor_info->{args} || [];
  foreach my $slice (@{$slices}) {
    my $features = $from_adaptor->$method($slice, @{$args});
    my $total_features = scalar(@{$features});
    my $count = 0;
    foreach my $f (@{$features}) {
      if($f->can('stable_id')) {
        print STDERR sprintf('Processing %s'."\n", $f->stable_id());
      }
      else {
        if($count != 0 && ($count % 100 == 0)) {
          print STDERR sprintf('Processing %d out of %d'."\n", $count, $total_features);
        }
      }
      
      $self->post_process_feature($f);
      
      $to_adaptor->store($f);
      $count++;
    }
  }
  return;
}

sub copy_database_structure {
  my ($self, $species, $group, $target_dbc) = @_;
  my $dba = Bio::EnsEMBL::Registry->get_DBAdaptor($species, $group);
  my $dbc = $dba->dbc();
  my $target_name = $self->new_dbname($dba->dbc()->dbname());
  my $source_name = $dba->dbc->dbname();
  print STDERR "Copying schema from ${source_name} into '${target_name}'\n";
  $target_dbc->do('drop database if exists '.$target_name);
  $target_dbc->do('create database '.$target_name);
  my $cmd_tmpl = 'mysqldump --host=%s --port=%d --user=%s --no-data --skip-add-locks --skip-lock-tables %s | mysql --host=%s --port=%d --user=%s --password=%s %s';
  my @src_args = map { $dbc->$_() } qw/host port username dbname/;
  my @trg_args = ((map { $target_dbc->$_() } qw/host port username password/), $target_name);  
  my $cmd = sprintf($cmd_tmpl, @src_args, @trg_args);
  system($cmd);
  my $rc = $? >> 8;
  if($rc != 0 ) {
    die "Could not execute command '$cmd'; got return code of $rc";
  }
  $target_dbc->dbname($target_name);
  $target_dbc->do('use '.$target_name);
  print STDERR "Finished population\n";
  return Bio::EnsEMBL::DBSQL::DBAdaptor->new(
    -DBCONN => $target_dbc,
    -GROUP => $group,
    -SPECIES => $target_name,
  );
}

sub get_ids {
  my ($self, $dba, $id, $table ) = @_;
  my $sql = "SELECT distinct($id) FROM $table";
  my $ids = $dba->dbc->sql_helper->execute_simple( -SQL => $sql );
  return $ids;
}

sub copy_all_data {
  my ($self, $from, $to, $table) = @_;
  my $query = "select * from $table";
  return $self->copy_data($from, $to, $table, $query);
}

sub copy_data {
  my ($self, $from, $to, $table, $query) = @_;
  print STDERR "Copying to $table\n\tQuery : '${query}'\n";
  my ($fh, $filename) = tempfile();
  $from->dbc->sql_helper()->execute_no_return(
    -SQL => $query,
    -CALLBACK => sub {
      my ($row) = @_;
      my @copy;
      foreach my $e (@{$row}) {
        if(!defined $e) {
          $e = '\N';
        }
        elsif(!looks_like_number($e)) {
          $e =~ s/\n/\\\n/g;
          $e =~ s/\t/\\\t/g; 
        }
        push(@copy, $e);
      }
      my $line = join(qq{\t}, @copy);
      print $fh $line, "\n";
    }
  );
  close $fh;
  my $target_load_sql = "LOAD DATA LOCAL INFILE '$filename' INTO TABLE $table";
  return $to->dbc->do($target_load_sql);
}

sub new_dbname {
  my ($self, $dbname) = @_;
  my @localtime = localtime();
  my $date      = strftime '%Y%m%d', @localtime;
  my $time      = strftime '%H%M%S', @localtime;
  return sprintf('%s_%s_%s_%s',$ENV{'USER'}, $date, $time, $dbname);
}

sub post_process_feature {
  my ($self, $f) = @_;
  if($f->isa('Bio::EnsEMBL::Gene')) {
    $self->_load_gene($f);
  }
  elsif($f->isa('Bio::EnsEMBL::Transcript')) {
    $self->_load_transcript($f);
  }
  return;
}

sub _load_gene {
  my ($self, $f) = @_;
  foreach my $t (@{$f->get_all_Transcripts}){
    $self->_load_transcript($t);
  }
  $f->$_() for qw/analysis get_all_DBEntries get_all_Attributes stable_id canonical_transcript/;
  return;
}

sub _load_transcript {
  my ($self, $f) = @_;
  my $tr = $f->translation();
  if ($tr) {
    $f->get_all_alternative_translations();
    $f->translate;
    $tr->$_() for qw/get_all_Attributes get_all_DBEntries get_all_ProteinFeatures get_all_SeqEdits/;
  }
  foreach my $e (@{$f->get_all_Exons}){
    $e->$_() for qw/analysis stable_id get_all_supporting_features/;
  }
  $f->$_() for qw/analysis stable_id get_all_supporting_features get_all_Attributes get_all_DBEntries get_all_alternative_translations get_all_SeqEdits/;
  return;
}
