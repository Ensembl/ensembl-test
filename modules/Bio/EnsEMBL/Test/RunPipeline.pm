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
  my ($self, $pipeline, $db) = @_;
  my $conf = $self->conf();
  my $cvs_root = $conf->{cvs_root};
  my $species = $self->species();
  my $path = $cvs_root . '/ensembl-hive/scripts';
  $ENV{PATH} = "$ENV{PATH}:$path";
  my $run = "init_pipeline.pl $pipeline -registry " . $self->get_frozen_config_file_path() . " -species $species -pipeline_db -host=" . $conf->{pipeline_host}  . " -pipeline_name=" . $conf->{pipeline_dbname} . " -pass=" . $conf->{pipeline_pass} . " " . $conf->{options};
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
  my $conf = $self->conf();
  my $cvs_root = $conf->{cvs_root};
  my $path = $cvs_root . '/ensembl-hive/scripts';
  $ENV{PATH} = "$ENV{PATH}:$path";
  my $url = "mysql://" . $conf->{pipeline_user} . ":" . $conf->{pipeline_pass} . "\@" . $conf->{pipeline_host} . ":" . $conf->{pipeline_port} . "/" . $ENV{USER} . "_" . $conf->{pipeline_dbname}; 
  my $run = "beekeeper.pl -url $url -reg_conf " . $self->get_frozen_config_file_path() . " -loop -sleep 0.1";
  my $status = system($run);
  if ($status != 0 ) {
      $status = $? >> 8;
  }
  return $status;
}

use constant {
  # Homo sapiens is used if no species is specified
  DEFAULT_SPECIES => 'homo_sapiens',

  # Configuration file extension appended onto species name
  FROZEN_CONF_SUFFIX => 'test.pipeline.frozen.conf',

  CONF_FILE => 'test.pipeline.conf',
  DUMP_DIR  => 'test-genome-DBs'
};


sub new {
  my ($class, $db, $pipeline, $species, $user_submitted_curr_dir, $skip_database_loading) = @_;

  my $self = bless {}, $class;
  
  #If told the current directory where config lives then use it
  if($user_submitted_curr_dir) {
    $self->curr_dir($user_submitted_curr_dir);
  }
  else {
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
  }

  $species ||= DEFAULT_SPECIES;
  $self->species($species);

  if ( -e $self->get_frozen_config_file_path() ) {
      $self->load_config();
  }
  $self->store_config($db);


  my $init = $self->init_pipeline($pipeline, $db);
  if ($init != 0) { throw "init_pipeline failed with error code: ".$init;}
  my $bees = $self->run_beekeeper($pipeline, $db);
  if ($bees != 0) { throw "beekeeper failed with error code: ".$bees;}
  $self->cleanup();

  return $self;
}

#
# Load configuration into $self->{'conf'} hash
#
sub load_config {
  my ($self) = @_;
  my $conf = $self->get_frozen_config_file_path();
  $self->{conf} = $self->_eval_file($conf);
  return;
}

#
# Build the target frozen config path 
#

sub get_frozen_config_file_path {
  my ($self) = @_;
  my $filename = sprintf('%s.%s', $self->species(), FROZEN_CONF_SUFFIX);
  my $conf = catfile($self->curr_dir(), $filename);
  return $conf;
}

sub _eval_file {
  my ($self, $file) = @_;
  my $contents = slurp($file);
  my $v = eval $contents;
  die "Could not read in configuration file '$file': $EVAL_ERROR" if $EVAL_ERROR;
  return $v;
}

sub store_config {
  my ($self, $db) = @_;
  my $file_conf = $self->get_frozen_config_file_path();
  my $conf = $self->conf();
  work_with_file($file_conf, 'w', sub {
    my ($fh) = @_;
    print $fh "#!/usr/local/bin/perl\n\n";
    print $fh "use Bio::EnsEMBL::DBSQL::DBAdaptor;\n";
    print $fh "use Bio::EnsEMBL::Registry;\n\n";
    print $fh "{\n";
    print $fh "Bio::EnsEMBL::DBSQL::DBAdaptor->new(\n";
    print $fh "-HOST => '" . $db->dbc()->host() . "',\n";
    print $fh "-PORT => '" . $db->dbc()->port() . "',\n";
    print $fh "-USER => '" . $db->dbc()->username() . "',\n";
    print $fh "-PASS => '" . $db->dbc()->password() . "',\n";
    print $fh "-DBNAME => '" . $db->dbc()->dbname() . "',\n";
    print $fh "-SPECIES => '" . $db->species() . "',\n";
    print $fh "-GROUP => 'core',\n";
    print $fh ");\n";
    print $fh "Bio::EnsEMBL::DBSQL::DBAdaptor->new(\n";
    print $fh "-HOST => '" . $db->dbc()->host() . "',\n";
    print $fh "-PORT => '" . $db->dbc()->port() . "',\n";
    print $fh "-USER => '" . $db->dbc()->username() . "',\n";
    print $fh "-PASS => '" . $db->dbc()->password() . "',\n";
    print $fh "-DBNAME => '" . $db->dbc()->dbname() . "',\n";
    print $fh "-SPECIES => '" . $db->species() . "',\n";
    print $fh "-GROUP => 'vega',\n";
    print $fh ");\n";
    print $fh "Bio::EnsEMBL::DBSQL::DBAdaptor->new(\n";
    print $fh "-HOST => '" . $conf->{prod_host} . "',\n";
    print $fh "-PORT => '" . $conf->{prod_port} . "',\n";
    print $fh "-USER => '" . $conf->{prod_user} . "',\n";
    print $fh "-DBNAME => '" . $conf->{prod_dbname} . "',\n";
    print $fh "-SPECIES => 'multi',\n";
    print $fh "-GROUP => 'production',\n";
    print $fh ");\n";
    ## only for web DBs
    
    if ( Bio::EnsEMBL::Registry->get_DBAdaptor('multi', 'web', 1)  ) {
        my $web_adaptor = Bio::EnsEMBL::Registry->get_DBAdaptor('multi','web');
        
        print $fh "Bio::EnsEMBL::DBSQL::DBAdaptor->new(\n";
        print $fh "-HOST => '" . $web_adaptor->dbc->host . "',\n";
        print $fh "-PORT => '" . $web_adaptor->dbc->port . "',\n";
        print $fh "-USER => '" . $web_adaptor->dbc->username . "',\n";
        print $fh "-DBNAME => '" . $web_adaptor->dbc->dbname . "',\n";
        print $fh "-PASS => '" . $web_adaptor->dbc->password() ."',\n";
        print $fh "-SPECIES => 'multi',\n";
        print $fh "-GROUP => 'web',\n";
        print $fh ");\n";
        
       
        print $fh "}\n";
        print $fh "1;\n";
    }
    return;
  });
  return;
}


sub tables {
  my ($self, $db, $dbname) = @_;
  my @tables;
  my $sth = $db->table_info(undef, $dbname, q{%}, 'TABLE');
  while(my $array = $sth->fetchrow_arrayref()) {
    push(@tables, $array->[2]);
  }
  return \@tables;
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

sub get_conf {
  my ($class, $current_directory) = @_;
  my $conf_file = catfile( $current_directory, CONF_FILE );

  if ( !-e $conf_file ) {
    throw("Required conf file '$conf_file' does not exist");
  }

  my $conf = $class->_eval_file($conf_file);
  die "Error while loading config file" if ! defined $conf;

  return $conf;
}

sub conf {
  my ($self) = @_;
  if(! $self->{conf}) {
    $self->{conf} = $self->get_conf($self->curr_dir());
  }
  return $self->{conf};
}

sub cleanup {
  my ($self) = @_;
  my $conf = $self->conf();

  # Remove all of the handles on db_adaptors
  %{$self->{db_adaptors}} = ();

  # Delete the pipeline db
  my $dbname = $ENV{USER} . "_" . $conf->{pipeline_dbname};
  my $db = $self->_db_conf_to_dbi($conf);
  $self->note("Dropping database $dbname");
  eval($db->do("DROP DATABASE $dbname"));
  $self->diag("Could not drop database $dbname: $EVAL_ERROR") if $EVAL_ERROR;

  # Delete the frozen configuration file
  my $conf_file = $self->get_frozen_config_file_path();
  if ( -e $conf_file && -f $conf_file ) {
    $self->note("Deleting $conf_file");
    unlink $conf_file;
  }
  return;
}


sub _db_conf_to_dbi {
  my ($self, $conf) = @_;
  my %params = (host => $conf->{pipeline_host}, port => $conf->{pipeline_port});
  my $param_str = join(q{;}, map { $_.'='.$params{$_} } keys %params);
  my $locator = sprintf('DBI:%s:%s', $conf->{pipeline_driver}, $param_str);
  my $db = DBI->connect( $locator, $conf->{pipeline_user}, $conf->{pipeline_pass}, { RaiseError => 1 } );
  return $db if $db;
  $self->diag("Can't connect to database '$locator': ". $DBI::errstr);
  return;

}



sub DESTROY {
  my ($self) = @_;

  if ( $ENV{'RUNTESTS_HARNESS'} ) {
    $self->note('Leaving database intact on server');
  } else {
    $self->note('Cleaning up...');
#    $self->cleanup();
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
