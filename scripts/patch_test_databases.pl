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

use Bio::EnsEMBL::Test::DumpDatabase;
use Bio::EnsEMBL::Test::MultiTestDB;
use File::Spec;
use Cwd;
use File::Basename;
use Getopt::Long;
use Pod::Usage;

my %skip_species_list;
my %skip_groups_list = map { $_ => 1} qw/web hive/; 

sub run {
  my ($class) = @_;
  my $self = bless({}, 'main');
  $self->args();
  $self->has_config();
  $self->process();
  $self->cleanup_CLEAN();
  return;
}

sub args {
  my ($self) = @_;
  
  my $ud = File::Spec->updir();
  my $default_patcher = File::Spec->catdir(dirname(__FILE__), $ud, $ud, 'ensembl', 'misc-scripts', 'schema_patcher.pl');
  
  my $opts = {
    schema_patcher => $default_patcher,
  };
  GetOptions(
    $opts, qw/
      curr_dir|current_directory|directory|dir=s
      schema_patcher=s
      help
      man
      /
  ) or pod2usage(-verbose => 1, -exitval => 1);
  pod2usage(-verbose => 1, -exitval => 0) if $opts->{help};
  pod2usage(-verbose => 2, -exitval => 0) if $opts->{man};
  return $self->{opts} = $opts;
}

sub has_config {
  my ($self) = @_;
  my $config = File::Spec->catfile($self->{opts}->{curr_dir}, 'MultiTestDB.conf');
  if(! -f $config) {
    die "Cannot find a MultiTestDB.conf at '${config}'. Check your --curr_dir command line option";
  }
  return;
}

sub process {
  my ($self) = @_;
  my $dir = $self->{opts}->{curr_dir};
  my $config = $self->get_config();
  foreach my $species (keys %{$config->{databases}}) {
    print STDOUT '='x80; print STDOUT "\n";
    if($skip_species_list{lc($species)}) {
      print STDOUT "INFO: Skipping '$species' as it is in the patch ignore list\n";
      next;
    }
    my $multi = Bio::EnsEMBL::Test::MultiTestDB->new($species, $dir);
    foreach my $group (keys %{$config->{databases}->{$species}}) {
      if($skip_groups_list{lc($group)}) {
        print STDOUT "INFO: Skipping '$group' as it is in the patch ignore list\n";
        next;
      }
      print STDOUT "INFO: Processing species '$species' and group '$group'\n";
      my $dba = $multi->get_DBAdaptor($group);
      my $schema_details = $self->schema_details($dba);
      $self->patch_db($dba);
      $self->dump_db($dba, $schema_details);
    }
    $multi = undef;
    print STDOUT "INFO: Finished working with species '$species'\n";
    print STDOUT '='x80; print STDOUT "\n";
  }
  $self->convert_sqllite($dir);
  return;
}

sub schema_details {
  my ($self, $dba) = @_;
  my $h = $dba->dbc()->sql_helper();
  my $tables_sql = q{select TABLE_NAME, TABLE_TYPE from information_schema.TABLES where TABLE_SCHEMA = DATABASE()};
  my $tables = $h->execute(-SQL => $tables_sql);
  my %details;
  foreach my $t (@{$tables}) {
    my ($table_name, $table_type) = @{$t};
    
    my $checksum_sql = sprintf('CHECKSUM TABLE `%s`', $table_name);
    my $checksum = $h->execute(-SQL => $checksum_sql);
    
    my $create_sql = sprintf('SHOW CREATE TABLE `%s`', $table_name);
    my $create = $h->execute(-SQL => $create_sql);
    
    $details{$table_name} = {
      is_table  => ($table_type eq 'BASE TABLE' ? 1 : 0),
      checksum  => $checksum->[0]->[1],
      create    => $create->[0]->[1],
    };
  } 
  return \%details;
}

sub patch_db {
  my ($self, $dba) = @_;
  my $dbc = $dba->dbc();
  my %args_hash = (
    host => $dbc->host(),
    port => $dbc->port(),
    user => $dbc->username(),
    database => $dbc->dbname(),
  );
  $args_hash{pass} = $dbc->password() if $dbc->password();
  my @args = map { "-${_} ".$args_hash{$_} } keys %args_hash;
  push @args, (map { "-${_}"} qw/verbose fixlast nointeractive quiet/);
  
  my $program = $self->{opts}->{schema_patcher};
  my $arguments = join(q{ }, @args);
  my $cmd = "$program $arguments";
  print STDERR "DEBUG: Submitting command '$cmd'\n";
  my $output = `$cmd`;
  print STDERR $output;
  my $rc = $? << 8;
  if($rc != 0) {
    die "Not good! The patch command did not succeed";
  }
  return;
}

sub dump_db {
  my ($self, $dba, $old_schema_details) = @_;
  my $new_schema_details = $self->schema_details($dba);
  my $dir = Bio::EnsEMBL::Test::MultiTestDB->base_dump_dir($self->{opts}->{curr_dir});
  print STDERR "Will dump database to root of $dir\n";
  my $dumper = Bio::EnsEMBL::Test::DumpDatabase->new($dba, $dir, $old_schema_details, $new_schema_details);
  $dumper->dump();
  return;
}

sub convert_sqllite {
  my ($self, $dir) = @_;
  my $ud = File::Spec->updir();
  my $schema_converter = File::Spec->catdir(dirname(__FILE__), 'convert_test_schemas.sh');
  my $cwd = getcwd();
  my $is_absolute = File::Spec->file_name_is_absolute( $self->{opts}->{curr_dir});
  my $curr_dir;
  if ($is_absolute) {
    $curr_dir = File::Spec->catdir($self->{opts}->{curr_dir});
  } else {
    $curr_dir = File::Spec->catdir($cwd, $self->{opts}->{curr_dir} ) ;
  }
  if ($curr_dir !~ /ensembl\/modules\/t/) { return; }
  eval "require MooseX::App::Simple";
  system("$schema_converter $curr_dir") unless ($@);
}

sub cleanup_CLEAN {
  my ($self) = @_;
  my $clean_test = File::Spec->catfile($self->{opts}->{curr_dir}, 'CLEAN.t');
  if(-f $clean_test) {
    unlink $clean_test;
  }
  return;
}

sub get_config {
  my ($self) = @_;
  my $dir = $self->{opts}->{curr_dir};
  return Bio::EnsEMBL::Test::MultiTestDB->get_db_conf($dir);
}

run();

1;
__END__

=head1 NAME

  patch_test_databases.pl

=head1 SYNOPSIS

  ./patch_test_databases.pl --curr_dir ensembl/modules/t [--schema_patcher PATCHER]

=head1 DESCRIPTION

For a given directory where tests are normally run (one with a 
MultiTestDB.conf) this code will iterate through all available databases, 
load them into the target database server, run schema_patcher.pl and then
redump into a single SQL file & multiple txt files. The code will also
ensure that redundant table dumps are cleaned up and will only initate a dump
when a data point has changed.

=head1 OPTIONS

=over 8

=item B<--curr_dir>

Current directory. Should be set to the directory which has your configuration files

=item B<--schema_patcher>

Specify the location of the schema patcher script to use. If not specified we
assume a location of

  dirname(__FILE__)/../../ensembl/misc-scripts/schema_patcher.pl

=back

=cut
