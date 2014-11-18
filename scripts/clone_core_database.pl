#!/usr/bin/env perl
# Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


use strict;
use warnings;

use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::DBSQL::DBConnection;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Funcgen::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Test::DumpDatabase;
use Bio::EnsEMBL::Utils::IO qw/slurp/;
use Bio::EnsEMBL::Utils::Scalar qw/scope_guard/;
use File::Temp qw/tempfile/;
use Getopt::Long qw/:config no_ignore_case/;
use JSON;
use Pod::Usage;
use POSIX;
use Scalar::Util qw/looks_like_number/;

my %global_tables = (
  core => [qw/attrib_type meta coord_system external_db misc_attrib unmapped_reason/],
  funcgen => [qw/feature_set/],
);

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
    
    help
    man
  /) or pod2usage(-msg => 'Misconfigured options given', -verbose => 1, -exitval => 1);
  pod2usage(-verbose => 1, -exitval => 0) if $opts->{help};
  pod2usage(-verbose => 2, -exitval => 0) if $opts->{man};
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
  my $json_location = $self->{opts}->{json};
  pod2usage(-msg => 'No -json configuration given', -verbose => 1, -exitval => 1) unless $json_location;
  pod2usage(-msg => "JSON location $json_location does not exist", -verbose => 1, -exitval => 1) unless -f $json_location;
  my $slurp = slurp($json_location);
  my $json = JSON->new()->relaxed(1);
  return $self->{json} = $json->decode($slurp);
}

sub process {
  my ($self) = @_;
  my $dbc = $self->target_dbc();
  my $config_hash = $self->{json};
  my $is_dna = 1;
  
  foreach my $species (keys %{$config_hash}) {
    foreach my $group (keys %{$config_hash->{$species}}) {
      $is_dna = 0 if $group eq 'funcgen';
      my $registry = 'Bio::EnsEMBL::Registry';
      my $from = $registry->get_DBAdaptor($species, $group);
      my $info = $config_hash->{$species}->{$group};
      my $regions = $info->{regions};
      my $adaptors = $info->{adaptors};
      my $to = $self->copy_database_structure($species, $group, $dbc);
      $self->copy_globals($from, $to);
      my $slices = $self->copy_regions($from, $to, $regions, $is_dna);
      my $filter_exceptions = $info->{filter_exceptions};
      foreach my $adaptor_info (@{$adaptors}) {
        $self->copy_features($from, $to, $slices, $adaptor_info, $filter_exceptions);
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
  my $schema = $from->get_MetaContainer()->single_value_by_key('schema_type');
  $schema ||= $from->group();
  my $tables = $global_tables{$schema};
  $self->copy_all_data($from, $to, $_) for @{$tables};
  return;
}

# Starts the copy across of Slices
sub copy_regions {
  my ($self, $from, $to, $regions, $is_dna) = @_;
  my $coord_sql = "select name, coord_system_id from coord_system";
  my $coord_systems = $to->dbc->sql_helper()->execute_into_hash(-SQL => $coord_sql);

  my $slice_adaptor = $from->get_adaptor("Slice");
  my $seq_region_names;

  # Grab all toplevel slices and record those IDs which need to be
  # transferred for the  
  my @toplevel_slices;
  my %seq_region_id_list;
  foreach my $region (@{$regions}) {
    my ($name, $start, $end, $coord_system, $version) = @{$region};
    my $strand = undef;
    $coord_system ||= 'toplevel';
    #Make the assumption that the core API is OK and that the 3 levels of assembly are chromosome, supercontig and contig
    #Also only get those slices which are unique
    my $slice = $slice_adaptor->fetch_by_region($coord_system, $name, $start, $end, $strand, $version);
    if(! $slice) {
      print STDERR "Could not find a slice for $name .. $start .. $end\n";
      next;
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
  if ($is_dna) {
    my $sr_query = "SELECT a.* FROM seq_region s JOIN assembly a ON (s.seq_region_id = a.cmp_seq_region_id) WHERE seq_region_id IN ($seq_region_ids)";
    $self->copy_data($from, $to, "assembly", $sr_query);
  }
  
  
  # Once we've got the original list of slices we have to know if one is an 
  # assembly what it maps to & bring that seq_region along (toplevel def). If
  # seq is wanted then user has to specify that region
  my @seq_region_exception_ids;
  foreach my $slice (@toplevel_slices) {
    next if $slice->is_reference();
    my $exception_features = $slice->get_all_AssemblyExceptionFeatures();
    foreach my $exception (@{$exception_features}) {
      push(@seq_region_exception_ids, $slice_adaptor->get_seq_region_id($exception->slice()));
      push(@seq_region_exception_ids, $slice_adaptor->get_seq_region_id($exception->alternate_slice()));
    }
  }
  
  #Grab the copied IDs from the target DB & use this to drive the copy of assembly exceptions
  my $asm_cmp_ids = join(q{,}, @seq_region_exception_ids);
  if (scalar(@seq_region_exception_ids) > 0) {
    $self->copy_data($from, $to, 'assembly_exception', "SELECT * FROM assembly_exception WHERE seq_region_id in ($asm_cmp_ids)");
  }
  
  #Now transfer all seq_regions from seq_region into the new DB
  my @seq_regions_to_copy = (@seq_region_exception_ids, (map { $slice_adaptor->get_seq_region_id($_) } @toplevel_slices), keys %seq_region_id_list);
  my $seq_regions_to_copy_in = join(q{,}, @seq_regions_to_copy);
  $self->copy_data($from, $to, 'seq_region', "SELECT * FROM seq_region WHERE seq_region_id in ($seq_regions_to_copy_in)");
  $self->copy_data($from, $to, 'seq_region_attrib', "SELECT * FROM seq_region_attrib WHERE seq_region_id in ($seq_regions_to_copy_in)") if $is_dna;
  $self->copy_data($from, $to, 'dna', "SELECT * FROM dna WHERE seq_region_id in ($seq_regions_to_copy_in)") if $is_dna;
  
  return \@toplevel_slices;
}

sub copy_features {
  my ($self, $from, $to, $slices, $adaptor_info) = @_;
  my $name = $adaptor_info->{name};
  my $suppress_warnings = $adaptor_info->{suppress_warnings};
  my $sig_warn;
  my $sig_warn_guard;
  if($suppress_warnings) {
    $sig_warn = $SIG{__WARN__};
    $sig_warn_guard = scope_guard(sub { $SIG{__WARN__} = $sig_warn });
    $SIG{__WARN__} = sub {}; #ignore everything
  }  
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
      
      $f = $self->post_process_feature($f, $slice);
      next unless $f; # means we decided not to store it
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
  my $dbadaptor;
  if ($group eq 'funcgen') {
    $dbadaptor = Bio::EnsEMBL::Funcgen::DBSQL::DBAdaptor->new(
      -DBCONN => $target_dbc,
      -GROUP => $group,
      -SPECIES => $target_name,
      -DNADB => $dba->dnadb(),
    );
  } else {
    $dbadaptor = Bio::EnsEMBL::DBSQL::DBAdaptor->new(
    -DBCONN => $target_dbc,
    -GROUP => $group,
    -SPECIES => $target_name,
  );
  }
  return $dbadaptor;
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
  my ($self, $f, $slice, $filter_exception) = @_;
  my $filter = $self->filter_on_exception($f, $slice, $filter_exception);
  return if $filter;
  
  #Core objects
  if($f->can('load')) {
    $f->load();
  }
  elsif($f->isa('Bio::EnsEMBL::RepeatFeature')) {
    $self->_load_repeat($f);
  }
  
  
  return $f;
}

sub filter_on_exception {
  my ($self, $f, $slice) = @_;
  if($f->start() < 1) {
    return 1;
  }
  if($f->start() > $slice->end()) {
    return 1;
  }
  return 0;
}

sub _load_repeat {
  my ($self, $f) = @_;
  delete $f->repeat_consensus()->{dbID};
  delete $f->repeat_consensus()->{adaptor};
  return;
}

__END__

=head1 NAME

  clone_core_database.pl

=head1 SYNOPSIS

  clone_core_database.pl  -host HOST [-port PORT] -user USER [-pass PASS] -dbname DBNAME \
                          [-registry REG] \
                          -species SPECIES \
                          -dest_host HOST -dest_port PORT -dest_user USER -dest_pass PASS \
                          -json JSON \
                          -directory DIR \
                          [-drop_database]

=head1 DESCRIPTION

This script will take a JSON file of regions and adaptor calls and translates
this into a dump of a core database of controlled content. This gives
you as realistic a core database as we can provide perfect for testing.

=head1 PARAMETERS

=over 8

=item B<--host | --hostname | -h>

Host of the server to use as a source. Not required if you are using a registry file

=item B<--port | --P>

Port of the server to use as a source. Not required if you are using a registry file

=item B<--user | --username | -u>

Username of the server to use as a source. Not required if you are using a registry file

=item B<--pass | --password | -p>

Password of the server to use as a source. Not required if you are using a registry file

=item B<--dbname | --database | --db>

Database name of the server to use as a source. Not required if you are using a registry file

=item B<--species>

Species name to use. Not required if you are using a registry file

=item B<--registry | --reg_conf>

Registry file to load data from

=item B<--dest_host | --dest_hostname | --dh>

Target host for the database. Required parameter

=item B<--dest_port | --dP>

Target port for the database. Required parameter

=item B<--dest_user | --dest_username | --du>

Target user for the database. Required parameter

=item B<--dest_pass | --dest_password | --dp>

Target password for the database.

=item B<--json>

JSON configuration file which informs this script of the regions of data
to grab, from which species/group and what adaptors should be called to
fetch data for. If just a name is given to the adaptor array we assume
a call to C<fetch_all_by_Slice()> is wanted. Otherwise we will use the
method and the given arguments and store that data.

An example configuration is given below. JSON is in relaxed mode so
inline shell comments (#) and trailing commas are allowed.

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

=item B<--directory>

The directory to dump the data into. You will get 1 TXT file per table and
1 SQL file for the entire schema.

=item B<--drop_database>

Indicates if you wish to drop the database from the server post flat file
generation. If not you will have to manually drop the database.

=item B<--help>

Print help messages

=item B<--man>

Print the man page for this script

=back
