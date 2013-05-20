package Bio::EnsEMBL::Test::RunPipeline;

=pod

=head1 NAME

Bio::EnsEMBL::Test::RunPipeline

=head1 SYNOPSIS

  my $test = Bio::EnsEMBL::Test::MultiTestDB->new(); #uses homo_sapiens by default
  my $dba = $test->get_DBAdaptor('pipeline');
  my $pipeline = Bio::EnsEMBL::Test::RunPipeline($dba, $module);

=head1 DESCRIPTION

This module automatically runs the specified pipeline on a test database

=cut

use strict;
use warnings;

use DBI;
use Data::Dumper;
use English qw(-no_match_vars);
use File::Copy;
use File::Spec::Functions;
use IO::File;
use IO::Dir;
use POSIX qw(strftime);

use Bio::EnsEMBL::Utils::IO qw/slurp work_with_file/;
use Bio::EnsEMBL::Utils::Exception qw( warning throw );

use Bio::EnsEMBL::Registry;

use base 'Test::Builder::Module';

$OUTPUT_AUTOFLUSH = 1;


sub init_pipeline {
  my ($self, $pipeline) = @_;
  my $path = $ENV{CVS_ROOT} . '/ensembl-hive/scripts';
  my $dba = $self->pipe_db();
  
  $ENV{PATH} = "$ENV{PATH}:$path";
  my $run = sprintf("init_pipeline.pl %s -registry %s -species %s -pipeline_db -host=%s -pipeline_db -port=%s -pipeline_name=%s -pass=%s %s",
                    $pipeline, $self->reg_file(), $self->species(), $dba->dbc->host(), $dba->dbc->port(), $dba->dbc->dbname(), $dba->dbc->password(), $self->pipe_options 
  );
  print $run . " initiating pipeline\n" ;
  my $status = system($run);
  if ($? != 0 ) {
      $status = $? >> 8;
      return $status;
  }
  return $status;
}

sub run_beekeeper {
  my ($self, $pipeline) = @_;
  my $path = $ENV{CVS_ROOT}. '/ensembl-hive/scripts';
  my $dba = $self->pipe_db();
  $ENV{PATH} = "$ENV{PATH}:$path";
  my $url = sprintf("mysql://%s:%s@%s:%s/%s_%s",$dba->dbc->username(), $dba->dbc->password(), $dba->dbc->host(), $dba->dbc->port(),$ENV{USER},$dba->dbc->dbname()); 
  my $run = "beekeeper.pl -url $url -reg_conf " . $self->reg_file() . " -loop -sleep 0.1 > beekeeper.log";
  my $status = system($run);
  if ($status != 0 ) {
      $status = $CHILD_ERROR >> 8;
  }
  return $status;
}

use constant {
  # Homo sapiens is used if no species is specified
  DEFAULT_SPECIES => 'homo_sapiens',

  DUMP_DIR  => 'test-genome-DBs',
};


sub new {
  my ($class, $dba, $pipeline, $species, $options) = @_;

  my $self = bless {}, $class;
  
  # Go and grab the current directory and store it away
  my ( $package, $file, $line ) = caller;
  my $curr_dir = ( File::Spec->splitpath($file) )[1];
  if (!defined($curr_dir) || $curr_dir eq q{}) {
    $curr_dir = curdir();
  }
  else {
    $curr_dir = File::Spec->rel2abs($curr_dir);
  }
  $self->curr_dir($curr_dir);

  $species ||= DEFAULT_SPECIES;
  $self->species($species);
  
  $self->pipe_options($options);

  $self->pipe_db($dba);
  $self->store_config();


  my $init = $self->init_pipeline($pipeline);
  if ($init != 0) { throw "init_pipeline failed with error code: ".$init;}
  my $bees = $self->run_beekeeper($pipeline);
  if ($bees != 0) { throw "beekeeper failed with error code: ".$bees;}
  
  return $self;
}

sub store_config {
  my ($self, $dba) = @_;
  my $file_conf = $self->curr_dir."/hive_registry";
  $self->reg_file($file_conf);
  work_with_file($file_conf, 'w', sub {
    my ($fh) = @_;
    
    print $fh "use Bio::EnsEMBL::DBSQL::DBAdaptor;\n";
    
    print $fh "{\n";
    
    my $adaptors = Bio::EnsEMBL::Registry->get_all_DBAdaptors();
    foreach my $adaptor (@$adaptors) {
        my $namespace = ref($adaptor);
        print $fh "$namespace->new(\n";
        print $fh "-HOST => '".$adaptor->dbc->host."',\n";
        print $fh "-PORT => '".$adaptor->dbc->port."',\n";
        print $fh "-USER => '".$adaptor->dbc->username."',\n";
        print $fh "-PASS => '".$adaptor->dbc->password."',\n";
        print $fh "-DBNAME => '" . $adaptor->dbc->dbname . "',\n";
        print $fh "-SPECIES => '" . $adaptor->species . "',\n";
        print $fh "-GROUP => '". $adaptor->group."',\n";
        print $fh ");\n";
    }

    print $fh "}\n";
    print $fh "1;\n";
    return;
  });
  return;
}

sub reg_file {
    my ($self, $reg) = @_;
    $self->{registry_file} = $reg if $reg;
    return $self->{registry_file}; 
}

sub pipe_db {
    my ($self, $db) = @_;
    $self->{pipe_db} = $db if $db;
    return $self->{pipe_db};
}

sub pipe_options {
    my ( $self, $options ) = @_;
    $self->{options} = $options if $options;
    return $self->{options};
}

sub species {
  my ( $self, $species ) = @_;
  $self->{species} = $species if $species;
  return $self->{species};
}

sub curr_dir {
  my ( $self, $cdir ) = @_;
  $self->{'_curr_dir'} = $cdir if $cdir;
  return $self->{'_curr_dir'};
}

sub cleanup {
  my ($self) = @_;
  my $dba = $self->pipe_db;
  
  my $locator = sprintf("DBI:%s:%s:%s",$dba->dbc->driver(),$dba->dbc->host,$dba->dbc->port);
  my $db = DBI->connect($locator ,$dba->dbc->username,$dba->dbc->password(),{RaiseError => 1} );
  $self->diag("Can't connect to database '$locator': ". $DBI::errstr) if !$db;
  
  $self->note("Dropping database ".$dba->dbc->dbname);
  eval($db->do("DROP DATABASE ".$dba->dbc->dbname));
  $self->diag("Could not drop database: $EVAL_ERROR") if $EVAL_ERROR;

  # Remove all of the handles on db_adaptors
  %{$self->{db_adaptors}} = (); # Not sure if this does anything

  # Delete the frozen configuration file
  my $conf_file = $self->reg_file();
  if ( -e $conf_file && -f $conf_file ) {
    $self->note("Deleting $conf_file");
    unlink $conf_file;
  }
  return;
}





sub DESTROY {
  my ($self) = @_;

  if ( $ENV{'RUNTESTS_HARNESS'} ) {
    $self->note('Leaving database intact on server');
  } else {
    $self->note('Cleaning up...');
    $self->cleanup();
  }
  return;
}

sub note {
  my ($self, @args) = @_;
  $self->builder()->note(@args);
  return;
}

sub diag {
  my ($self, @args) = @_;
  $self->builder()->diag(@args);
  return;
}

1;
