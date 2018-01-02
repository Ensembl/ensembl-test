#!/usr/bin/env perl
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2018] EMBL-European Bioinformatics Institute
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

use Bio::EnsEMBL::Test::MultiTestDB;
use Getopt::Long;
use Pod::Usage;

local $ENV{RUNTESTS_HARNESS} = 1;

sub run {
  my ($class) = @_;
  my $self = bless({}, 'main');
  $self->args();
  $self->load();
  $self->report_mysql_cmdline();
  $self->report_patch_cmdline();
  $self->report_dumper_cmdline();
  $self->report_mysqladmin_cmdline();
  return;
}

sub args {
  my ($self) = @_;
  my $opts = {};
  GetOptions(
    $opts, qw/
      curr_dir=s
      species=s
      type=s
      help
      man
      /
  ) or pod2usage(-verbose => 1, -exitval => 1);
  pod2usage(-verbose => 1, -exitval => 0) if $opts->{help};
  pod2usage(-verbose => 2, -exitval => 0) if $opts->{man};
  $self->{opts} = $opts;
  return;
}

sub load {
  my ($self) = @_;
  my $mdb = Bio::EnsEMBL::Test::MultiTestDB->new($self->{opts}->{species}, $self->{opts}->{curr_dir}, 1);
  if ($self->{opts}->{type} eq 'funcgen') {
    ## Need to load core db as well
    $mdb->load_database('core');
    $mdb->create_adaptor('core');
  }
  $mdb->load_database($self->{opts}->{type});
  $mdb->create_adaptor($self->{opts}->{type});
  $self->{mdb} = $mdb;
  return;
}

sub report_mysql_cmdline {
  my ($self) = @_;
  my $dbc = $self->{mdb}->get_DBAdaptor($self->{opts}->{type})->dbc();
  my $password = ($dbc->password()) ? '--password='.$dbc->password() : q{};
  printf "MySQL command line: mysql --host=%s --port=%d --user=%s %s %s\n", 
    $dbc->host(), $dbc->port(), $dbc->username(), $password, $dbc->dbname();
}

sub report_patch_cmdline {
  my ($self) = @_;
  my $dbc = $self->{mdb}->get_DBAdaptor($self->{opts}->{type})->dbc();
  my $password = ($dbc->password()) ? '--pass '.$dbc->password() : q{};
  printf "Schema Patcher command line: schema_patcher.pl --host %s --port %d --user %s %s --database %s --verbose --fixlast --dryrun\n", 
    $dbc->host(), $dbc->port(), $dbc->username(), $password, $dbc->dbname();
}

sub report_dumper_cmdline {
  my ($self) = @_;
  my $dbc = $self->{mdb}->get_DBAdaptor($self->{opts}->{type})->dbc();
  my $password = ($dbc->password()) ? '--pass '.$dbc->password() : q{};
  printf "Database dumper command line: dump_mysql.pl --host %s --port %d --user %s %s --database %s --verbose --testcompatible --directory $HOME\n", 
    $dbc->host(), $dbc->port(), $dbc->username(), $password, $dbc->dbname();
}

sub report_mysqladmin_cmdline {
  my ($self) = @_;
  my $dbc = $self->{mdb}->get_DBAdaptor($self->{opts}->{type})->dbc();
  my $password = ($dbc->password()) ? '--password='.$dbc->password() : q{};
  printf "mysqladmin removal command line: mysqladmin --host=%s --port=%d --user=%s %s drop %s\n", 
    $dbc->host(), $dbc->port(), $dbc->username(), $password, $dbc->dbname();
}


run();

1;
__END__

=head1 NAME

  load_database.pl

=head1 SYNOPSIS

  ./load_database.pl --curr_dir ensembl/modules/t --species homo_sapiens --type core

=head1 DESCRIPTION

Attempts to load a test database and to leave it available on the specified
test server for patching and re-dumping.

=head1 OPTIONS

=over 8

=item B<--curr_dir>

Current directory. Should be set to the directory which has your configuration files

=item B<--species>

Specify the species to load

=item B<--type>

Specify the type to load

=back

=cut
