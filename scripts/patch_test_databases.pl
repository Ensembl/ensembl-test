#!/usr/bin/env perl

use strict;
use warnings;

use Bio::EnsEMBL::Test::DumpDatabase;
use Bio::EnsEMBL::Test::MultiTestDB;
use File::Spec;
use File::Basename;
use Getopt::Long;
use Pod::Usage;

#local $ENV{RUNTESTS_HARNESS} = 1;

sub run {
  my ($class) = @_;
  my $self = bless({}, 'main');
  $self->args();
  $self->process();
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

sub process {
  my ($self) = @_;
  my $dir = $self->{opts}->{curr_dir};
  my $config = $self->get_config();
  foreach my $species (keys %{$config->{databases}}) {
    print STDOUT '='x80; print STDOUT "\n";
    my $multi = Bio::EnsEMBL::Test::MultiTestDB->new($species, $dir);
    foreach my $group (keys %{$config->{databases}->{$species}}) {
      print STDOUT "INFO: Processing species '$species' and group '$group'\n";
      my $dba = $multi->get_DBAdaptor($group);
      $self->patch_db($dba);
      $self->dump_db($dba);
    }
    $multi = undef;
    print STDOUT "INFO: Finished working with species '$species'\n";
    print STDOUT '='x80; print STDOUT "\n";
  }
  return;
}

sub patch_db {
  my ($self, $dba) = @_;
  my $dbc = $dba->dbc();
  my %args_hash = (
    host => $dbc->host(),
    port => $dbc->port(),
    user => $dbc->username(),
    pass => $dbc->password(),
    database => $dbc->dbname(),
  );
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
  my ($self, $dba) = @_;
  my $dir = Bio::EnsEMBL::Test::MultiTestDB->base_dump_dir($self->{opts}->{curr_dir});
  print STDERR "Will dump database to root of $dir\n";
  my $dumper = Bio::EnsEMBL::Test::DumpDatabase->new($dba, $dir);
  $dumper->dump();
  return;
}

sub get_config {
  my ($self) = @_;
  my $dir = $self->{opts}->{curr_dir};
  return Bio::EnsEMBL::Test::MultiTestDB->get_db_conf($dir);
}

run();

1;