package Bio::EnsEMBL::Test::RunPipeline;

=pod

=head1 NAME

Bio::EnsEMBL::Test::RunPipeline

=head1 SYNOPSIS

use Bio::EnsEMBL::Test::MultiTestDB;
use Bio::EnsEMBL::Test::RunPipeline;

my $hive = Bio::EnsEMBL::Test::MultiTestDB->new('hive');
my $pipeline = Bio::EnsEMBL::Test::RunPipeline->new(
  $hive->get_DBAdaptor('hive'), 'Bio::EnsEMBL::PipeConfig::My_conf', '-options');

$pipeline->run();

=head1 DESCRIPTION

This module automatically runs the specified pipeline on a test database. The module 
is responsible for

=over 8

=item Setting up ENSEMBL_CVS_ROOT_DIR

=item Setting up PATH to point to ensembl-hive/scripts

=item Writing the contents of Bio::EnsEMBL::Registry to a tmp file

=item Initalising the pipeline (can cause entire pipeline bail out)

=item Running beekeeper locally (can cause entire pipeline bail out)

=back

You are expected to provide

=over 8

=item A DBAdaptor instance pointing to a possible hive DB

=item Any options required for init_pipeline.pl to run (including target tmp dirs)

=item The module to run

=item Any fake binaries already on the PATH before running the pipeline

=back

=cut

use strict;
use warnings;

use English qw(-no_match_vars);
use File::Temp;
use File::Spec;

use Bio::EnsEMBL::Registry;

use base 'Test::Builder::Module';

$OUTPUT_AUTOFLUSH = 1;

=head2 init_pipeline

Runs init_pipeline.pl creating the hive DB

=cut

sub init_pipeline {
  my ($self, $pipeline) = @_;
  
  my $dba = $self->pipe_db();
  my $dbc = $dba->dbc();
  my $run = sprintf(
    "init_pipeline.pl %s -registry %s -pipeline_db -host=%s -pipeline_db -port=%s -pipeline_name=%s -pass=%s -pipeline_db -dbname=%s %s",
    $pipeline, $self->reg_file(), $dbc->host(), $dbc->port(), $dbc->dbname(), $dbc->password(), $dbc->dbname, $self->pipe_options 
  );
  $self->builder()->note("Initiating pipeline");
  $self->builder()->note($run);
  my $status = system($run);
  if ($? != 0 ) {
    $status = $? >> 8;
    return $status;
  }
  return $status;
}

=head2 run_beekeeper_loop

Runs beekeeper in a loop. You can control the sleep time using

  $self->beekeeper_sleep()

=cut

sub run_beekeeper_loop {
  my ($self) = @_;
  my $sleep = $self->beekeeper_sleep();
  return $self->run_beekeeper('-no_analysis_stats -loop -sleep '.$sleep);
}

=head2 run_beekeeper_final_status

Runs beekeeper to print out the final analysis status

  $self->run_beekeeper_final_status()

=cut

sub run_beekeeper_final_status {
  my ($self) = @_;
  return $self->run_beekeeper();
}

=head2 run_beekeeper_sync

Syncs the hive

=cut

sub run_beekeeper_sync {
  my ($self) = @_;
  return $self->run_beekeeper('-sync');
}

=head2 run_beekeeper

Runs beekeeper with any given cmd line options. Meadow and max workers are controlled via

  $self->meadow()
  $self->max_workers()

=cut

sub run_beekeeper {
  my ($self, $cmd_line_options) = @_;
  $cmd_line_options ||= q{};
  my $dba = $self->pipe_db();
  my $url = $self->hive_url();
  my $meadow = $self->meadow();
  my $max_workers = $self->max_workers();
  my $run = "beekeeper.pl -url $url -meadow $meadow -total_running_workers_max $max_workers -reg_conf " . 
    $self->reg_file() . ' '. $cmd_line_options;
  $self->builder()->note("Starting pipeline");
  $self->builder()->note($run);
  my $status = system($run);
  if ($status != 0 ) {
    $status = $CHILD_ERROR >> 8;
  }
  return $status;
}

=head2 new

Create a new module. See SYNOPSIS for details on how to use

=cut

sub new {
  my ($class, $pipeline, $options) = @_;

  $class = ref($class) || $class;
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
  $self->pipeline($pipeline);
  $self->pipe_options($options);

  $self->setup_environment();

  #Intalise the hive database
  $self->hive_multi_test_db();

  return $self;
}

=head2 add_fake_binaries

Allows you to add directories held in the ensembl-xxxx/modules/t directory 
(held in curr_dir()) which hold fake binaries for a pipeline.

=cut

sub add_fake_binaries {
  my ($self, $fake_binary_dir) = @_;
  my $binary_dir = File::Spec->catdir($self->curr_dir(), $fake_binary_dir);
  $ENV{PATH} = join(q{:}, $ENV{PATH}, $binary_dir);
  $self->builder->note('Fake binary dir added. PATH is now: '.$ENV{PATH});
  return;
}

=head2 run

Sets the pipeline going. This includes registry writing, initalisation, syncing, and running. See 
SYNPOSIS for more information.

=cut

sub run {
  my ($self) = @_;

  my $pipeline = $self->pipeline();

  #Write the registry out
  $self->write_registry();

  #Run the init
  my $init = $self->init_pipeline($pipeline);
  if ($init != 0) { $self->builder()->BAIL_OUT("init_pipeline.pl failed with error code: ".$init); }

  #Sync and loop the pipeline
  my $bees_sync = $self->run_beekeeper_sync();
  if ($bees_sync != 0) { $self->builder()->BAIL_OUT("beekeeper.pl sync failed with error code: ".$bees_sync); }
  my $bees_loop = $self->run_beekeeper_loop();
  if ($bees_loop != 0) { $self->builder()->BAIL_OUT("beekeeper.pl loop failed with error code: ".$bees_loop); }
  
  return $self;
}

=head2 setup_environment

When run this will setup the ENSEMBL_CVS_ROOT_DIR if not already set and
will add the PATH to ensembl-hive/scripts

=cut

sub setup_environment {
  my ($self) = @_;
  my $curr_dir = $self->curr_dir();
  my $up = File::Spec->updir();
  
  my $cvs_root_dir;
  #Setup the CVS ROOT DIR ENV if not already there
  if(! exists $ENV{ENSEMBL_CVS_ROOT_DIR}) {
    #Curr dir will be a t dir so the original will be CVS_ROOT/ensembl-production/modules/t
    $cvs_root_dir = File::Spec->catdir($self->curr_dir(), $up, $up, $up);
    $ENV{ENSEMBL_CVS_ROOT_DIR} = $cvs_root_dir;
  }
  else {
    $cvs_root_dir = $ENV{ENSEMBL_CVS_ROOT_DIR};
  }

  #Set the PATH
  my $hive_script_dir = File::Spec->catdir($self->curr_dir(), $up, $up, $up, 'ensembl-hive', 'scripts');
  $ENV{PATH} = join(q{:}, $hive_script_dir, $ENV{PATH});
  $self->builder->note('Setting up hive. PATH is now: '.$ENV{PATH});

  #Stop registry from moaning
  Bio::EnsEMBL::Registry->no_version_check(1);

  return;
}

=head2 write_registry

Write the current contents of the Registry out to a Perl file

=cut

sub write_registry {
  my ($self, $dba) = @_;
  my $fh = File::Temp->new();
  $fh->unlink_on_destroy(1);
  $self->registry_file($fh);
  my %used_namespaces;
  
  print $fh "{\n";
  
  my $adaptors = Bio::EnsEMBL::Registry->get_all_DBAdaptors();
  foreach my $adaptor (@{$adaptors}) {
    next if $adaptor->group() eq 'hive';
    my $namespace = ref($adaptor);
    if(! exists $used_namespaces{$namespace}) {
      print $fh "use $namespace;\n";
      $used_namespaces{$namespace} = 1;
    }
    my $dbc = $adaptor->dbc();
    print $fh "$namespace->new(\n";
    print $fh "-HOST => '".$dbc->host."',\n";
    print $fh "-PORT => '".$dbc->port."',\n";
    print $fh "-USER => '".$dbc->username."',\n";
    print $fh "-PASS => '".$dbc->password."',\n";
    print $fh "-DBNAME => '" . $dbc->dbname . "',\n";
    print $fh "-SPECIES => '" . $adaptor->species . "',\n";
    print $fh "-GROUP => '". $adaptor->group."',\n";
    print $fh ");\n";
  }

  print $fh "}\n";
  print $fh "1;\n";

  $fh->close();
  return;
}

=head2 _drop_hive_database

Remove the current hive DB

=cut

sub _drop_hive_database {
  my ($self) = @_;
  my $dba = $self->pipe_db();
  my $dbc = $dba->dbc();
  $dbc->do('drop database '.$dbc->dbname());
  return;
}

=head2 hive_url

Generate a hive compatible URL from the object's hive dbadaptor

=cut

sub hive_url {
  my ($self) = @_;
  my $dba = $self->pipe_db();
  my $dbc = $dba->dbc();
  my $url = sprintf(
    "mysql://%s:%s@%s:%s/%s",
    $dbc->username(), $dbc->password(), $dbc->host(), $dbc->port(), $dbc->dbname()
  ); 
  return $url;
}

sub reg_file {
  my ($self) = @_;
  return $self->registry_file()->filename();
}

sub registry_file {
  my ($self, $registry_file) = @_;
  $self->{registry_file} = $registry_file if $registry_file;
  return $self->{registry_file}; 
}

sub pipe_db {
  my ($self, $db) = @_;
  return $self->hive_multi_test_db->get_DBAdaptor('hive');
}

sub pipeline {
  my ( $self, $pipeline ) = @_;
  $self->{pipeline} = $pipeline if $pipeline;
  return $self->{pipeline};
}

sub pipe_options {
  my ( $self, $options ) = @_;
  $self->{options} = $options if $options;
  return $self->{options} || q{};
}

sub curr_dir {
  my ( $self, $cdir ) = @_;
  $self->{'_curr_dir'} = $cdir if $cdir;
  return $self->{'_curr_dir'};
}

sub meadow {
  my ($self, $meadow) = @_;
  $self->{meadow} = $meadow if $meadow;
  return $self->{meadow} || 'LOCAL';
}

sub beekeeper_sleep {
  my ($self, $beekeeper_sleep) = @_;
  $self->{beekeeper_sleep} = $beekeeper_sleep if $beekeeper_sleep;
  return $self->{beekeeper_sleep} || 0.1;
}

sub max_workers {
  my ($self, $max_workers) = @_;
  $self->{max_workers} = $max_workers if $max_workers;
  return $self->{max_workers} || 2;
}

sub hive_multi_test_db {
  my ($self) = @_;
  if(! $self->{hive_multi_test_db}) {
    $self->{hive_multi_test_db} = Bio::EnsEMBL::Test::MultiTestDB->new('hive', $self->curr_dir());
    #have to drop the hive DB first. Bit backwards tbh but hive needs to create the DB
    $self->_drop_hive_database();
  }
  return $self->{hive_multi_test_db};
}

1;
