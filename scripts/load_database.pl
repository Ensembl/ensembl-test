#!/usr/bin/env perl

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
  $mdb->load_database($self->{opts}->{type});
  $mdb->create_adaptor($self->{opts}->{type});
  $self->{mdb} = $mdb;
  return;
}

sub report_mysql_cmdline {
  my ($self) = @_;
  my $dbc = $self->{mdb}->get_DBAdaptor($self->{opts}->{type})->dbc();
  printf "MySQL command line: mysql --host=%s --port=%d --user=%s --password=%s %s\n", 
    $dbc->host(), $dbc->port(), $dbc->username(), $dbc->password(), $dbc->dbname();
}

sub report_patch_cmdline {
  my ($self) = @_;
  my $dbc = $self->{mdb}->get_DBAdaptor($self->{opts}->{type})->dbc();
  printf "Schema Patcher command line: schema_patcher.pl --host %s --port %d --user %s --pass %s --database %s --verbose --fixlast --dryrun\n", 
    $dbc->host(), $dbc->port(), $dbc->username(), $dbc->password(), $dbc->dbname();
}

sub report_dumper_cmdline {
  my ($self) = @_;
  my $dbc = $self->{mdb}->get_DBAdaptor($self->{opts}->{type})->dbc();
  printf "Database dumper command line: dump_mysql.pl --host %s --port %d --user %s --pass %s --database %s --verbose --testcompatible --directory /tmp\n", 
    $dbc->host(), $dbc->port(), $dbc->username(), $dbc->password(), $dbc->dbname();
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