package Bio::EnsEMBL::Test::MultiTestDB;

=pod

=head1 NAME

Bio::EnsEMBL::Test::MultiTestDB

=head1 SYNOPSIS

  my $test = Bio::EnsEMBL::Test::MultiTestDB->new(); #uses homo_sapiens by default
  my $dba = $test->get_DBAdaptor(); #uses core by default
  
  my $dros = Bio::EnsEMBL::Test::MultiTestDB->new('drosophila_melanogaster');
  my $dros_rnaseq_dba = $dros->get_DBAdaptor('rnaseq');

=head1 DESCRIPTION

This module automatically builds the specified database on demand and provides
a number of methods for saving, restoring and hiding databases tables in 
that database.

If the environment variable C<RUNTESTS_HARNESS> is set then this code will
not attempt a cleanup of the database when the object is destroyed. When used
in conjunction with C<runtests.pl> this means we create 1 database and reuse
it for all tests at the expense of test isolation. Your tests should leave the
database in a consistent state for the next test case and never assume
perfect isolation.

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

use Bio::EnsEMBL::Utils::IO qw/work_with_file/;
use Bio::EnsEMBL::Utils::Exception qw( warning throw );

use base 'Test::Builder::Module';

$OUTPUT_AUTOFLUSH = 1;

sub diag {
  my ($self, @args) = @_;
  $self->builder()->diag(@args);
  return;
}

sub note {
  my ($self, @args) = @_;
  $self->builder()->note(@args);
  return;
}

use constant {
  # Homo sapiens is used if no species is specified
  DEFAULT_SPECIES => 'homo_sapiens',

  # Configuration file extension appended onto species name
  FROZEN_CONF_SUFFIX => 'MultiTestDB.frozen.conf',

  CONF_FILE => 'MultiTestDB.conf',
  DUMP_DIR  => 'test-genome-DBs'
};

sub new {
  my ($class, $species) = @_;

  my $self = bless {}, $class;

  # Go and grab the current directory and store it away
  my ( $package, $file, $line ) = caller;
  my $curr_dir = ( File::Spec->splitpath($file) )[1];
  if (!defined($curr_dir) || $curr_dir eq q{}) {
    $curr_dir = curdir();
  }
  $self->curr_dir($curr_dir);

  if($ENV{'RUNTESTS_HARNESS'}) {
    my $target_file = catfile($self->curr_dir() , 'CLEAN.t');
    if (! -e $target_file) {
      my $clean_file = catfile( ( File::Spec->splitpath(__FILE__) )[1], 'CLEAN.pl' );
      copy($clean_file, $target_file ) or warning("# !! Could not copy $clean_file to $target_file\n");
    }
  }

  $species ||= DEFAULT_SPECIES;
  $self->species($species);

  if ( -e $self->get_frozen_config_file_path() ) {
      $self->load_config();
  }
  else {
    # Load the databases and generate the conf hash
    $self->load_databases();
    # Freeze configuration in a file
    $self->store_config();
  }

  # Generate the db_adaptors from the $self->{'conf'} hash
  $self->create_adaptors();

  return $self;
}

#
# Load configuration into $self->{'conf'} hash
#
sub load_config {
  my ($self) = @_;
  my $conf = $self->get_frozen_config_file_path();
  eval {$self->{'conf'} = do $conf; };
  die "Could not read frozen configuration file '$conf': $EVAL_ERROR" if $EVAL_ERROR;
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

#
# Store $self->{'conf'} hash into a file
#
sub store_config {
  my ($self) = @_;
  my $conf = $self->get_frozen_config_file_path();
  work_with_file($conf, 'w', sub {
    my ($fh) = @_;
    local $Data::Dumper::Indent    = 2;  # we want everything on one line
    local $Data::Dumper::Terse     = 1;  # and we want it without dummy variable names
    local $Data::Dumper::Sortkeys  = 1;  # make stringification more deterministic
    local $Data::Dumper::Quotekeys = 1;  # conserve some space
    local $Data::Dumper::Useqq     = 1;  # escape the \n and \t correctly
    print $fh Dumper($self->{conf});
    return;
  });
  return;
}

#
# Create a set of adaptors based on the $self->{'conf'} hash
#

sub create_adaptors {
  my ($self) = @_;

  foreach my $dbtype (keys %{$self->{conf}}) {
    my $db = $self->{conf}->{$dbtype};
    my $module = $db->{module};
    my %dnadb_params;
    if($dbtype eq 'funcgen') {
      %dnadb_params = map { ("-dnadb_${_}", $db->{"dnadb_${_}"}) } qw/host user pass port name/;
    }
    if(eval "require $module") {
      my %args = map { ( "-${_}", $db->{$_} ) } qw/dbname user pass port host driver species/;
      my $adaptor = eval{ $module->new(%args) };
      if($EVAL_ERROR) {
        $self->diag("!! Could not instantiate $dbtype DBAdaptor: $EVAL_ERROR");
      }
      else {
        $self->{db_adaptors}->{$dbtype} = $adaptor;
      }
    }
  }

  return;
}

sub load_databases {
  my ($self) = shift; 
  my $species = $self->species();

  $self->note("Trying to load [$species] databases");

  # Create database from conf and from zip files
  my $conf_file = catfile( $self->curr_dir(), CONF_FILE );

  if ( !-e $conf_file ) {
      throw("Required conf file '$conf_file' does not exist");
  }

  my $db_conf = eval {do $conf_file};
  die "Could not eval '$conf_file': $EVAL_ERROR" if $EVAL_ERROR;
  die("Error while loading config file") if ! defined $db_conf;

  # Create a configuration hash which will be frozen to a file
  $self->{'conf'} = {};

  # Connect to the database
  my $db = $self->_db_conf_to_dbi($db_conf, {mysql_local_infile => 1});
  if ( ! defined $db ) {
    $self->diag("!! Can't connect to database: ".$DBI::errstr);
    return;
  }

  my $databases = $db_conf->{databases};
  my $preloaded = $db_conf->{preloaded} || {};

  if(! $databases->{$species}) {
    die "Requested a database for specis $species but the MultiTestDB.conf knows nothing about this";
  }

  my @db_types = keys %{$databases->{$species}};

  foreach my $dbtype (@db_types) {
    my $config_hash = { %$db_conf };
    delete $config_hash->{databases};

    $config_hash->{module} = $databases->{$species}->{$dbtype};

    $self->{conf}->{$dbtype} = $config_hash;

    my $dbname = $preloaded->{$species}->{$dbtype};
    if($dbname && $self->_db_exists($db, $dbname)) {
      $config_hash->{dbname} = $dbname;
      $config_hash->{preloaded} = 1;
    }
    else {
      if(! $dbname) {
        $dbname = $self->_create_db_name($dbtype);
        delete $config_hash->{preloaded};
      }
      else {
        $config_hash->{preloaded} = 1;
      }

      $config_hash->{dbname} = $dbname;
      $self->note("Creating database $dbname");

      my $create_db = $db->do("CREATE DATABASE $dbname");
      if(! $create_db) {
        $self->note("!! Could not create database [$dbname]");
        return;
      }

      $db->do('use '.$dbname);
      my $dir_name = catdir( $self->curr_dir(), DUMP_DIR, $species,  $dbtype );
      $self->load_sql($dir_name, $db);
      $self->load_txt_dumps($dir_name, $dbname, $db);
      $self->note("Loaded database '$dbname'");
    }
  }

  $db->disconnect();
  return;
}

#
# Loads a DB from a single table.sql file or a set of *.sql files
#

sub load_sql {
  my ($self, $dir_name, $db) = @_;
  my $dir = IO::Dir->new($dir_name);
  if(! defined $dir) {
    $self->diag(" !! Could not open dump directory '$dir_name'");
    return;
  }
  my @files = grep { $_ =~ /\.sql$/ } $dir->read();
  $dir->close();

  my ($all_tables_sql) = grep { $_ eq 'table.sql' } @files;

  my $sql_com = q{};
  if($all_tables_sql) {
    @files = ($all_tables_sql);
  }
  foreach my $sql_file (@files) {
    my $sql_file = catfile( $dir_name, $sql_file );
    work_with_file($sql_file, 'r', sub {
      my ($fh) = @_;
      while(my $line = <$fh>) {
        #ignore comments and white-space lines
        if($line !~ /^#/ && $line =~ /\S/) {
          $sql_com .= $line;
        }
      }
      return;
    });

  }

  $sql_com =~ s/;$//;
  my @statements = split( /;/, $sql_com );
  foreach my $sql (@statements) {
    $db->do($sql);
  }

  return;
}

sub load_txt_dumps {
  my ($self, $dir_name, $dbname, $db) = @_;
  my $tables = $self->tables($db, $dbname);
  foreach my $tablename (@{$tables}) {
    my $txt_file = catfile($dir_name, $tablename.'.txt');
    if(! -f $txt_file || ! -r $txt_file) {
      $self->note("!! Could not read data file '$txt_file'");
      next;
    }
    my $load = sprintf(q{LOAD DATA LOCAL INFILE '%s' INTO TABLE `%s` FIELDS ESCAPED BY '\\\\'}, $txt_file, $tablename);
    $db->do($load);
  }
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

sub get_DBAdaptor {
  my ($self, $type, $die_if_not_found) = @_;
  die "No type specified" if ! $type;
  if(!$self->{db_adaptors}->{$type}) {
    $self->diag("!! Database adaptor of type $type is not available");
    if($die_if_not_found) {
      die "daptor for $type is not available";
    }
    return;
  }
  return $self->{db_adaptors}->{$type};
}

=head2 hide

  Arg [1]    : string $dbtype
               The type of the database containing the temporary table
  Arg [2]    : string $table
               The name of the table to hide
  Example    : $multi_test_db->hide('core', 'gene', 'transcript', 'exon');
  Description: Hides the contents of specific table(s) in the specified
               database.  The table(s) are first renamed and an empty
               table are created in their place by reading the table
               schema file.
  Returntype : none
  Exceptions : Thrown if the adaptor for dbtype is not available
               Thrown if both arguments are not defined
               Warning if there is already a temporary ("hidden")
               version of the table
               Warning if a temporary ("hidden") version of the table
               Cannot be created because its schema file cannot be read
  Caller     : general

=cut

sub hide {
  my ( $self, $dbtype, @tables ) = @_;

  die("dbtype and table args must be defined\n") if ! $dbtype || !@tables;
  my $adaptor = $self->get_DBAdaptor($dbtype, 1);

  foreach my $table (@tables) {
    if ( $self->{'conf'}->{$dbtype}->{'hidden'}->{$table} ) {
      $self->diag("!! Table '$table' is already hidden and cannot be hidden again");
      next;
    }

    my $hidden_name = "_hidden_$table";
    # Copy contents of table into a temporary table
    $adaptor->dbc->do("CREATE TABLE $hidden_name SELECT * FROM $table");
    # Delete the contents of the original table
    $adaptor->dbc->do("DELETE FROM $table");
    # Update the temporary table configuration
    $self->{'conf'}->{$dbtype}->{'hidden'}->{$table} = $hidden_name;
  }
  return;
}

=head2 restore

  Arg [1]    : (optional) $dbtype 
               The dbtype of the table(s) to be restored. If not
               specified all hidden tables in all the databases are
               restored.
  Arg [2]    : (optional) @tables
               The name(s) of the table to be restored.  If not
               specified all hidden tables in the database $dbtype are
               restored.
  Example    : $self->restore('core', 'gene', 'transcript', 'exon');
  Description: Restores a list of hidden tables. The current version of
               the table is discarded and the hidden table is renamed.
  Returntype : none
  Exceptions : Thrown if the adaptor for a dbtype cannot be obtained
  Caller     : general

=cut

sub restore {
  my ( $self, $dbtype, @tables ) = @_;

  if ( !$dbtype ) {
    # Restore all of the tables in every dbtype
    foreach my $dbtype ( keys %{ $self->{'conf'} } ) {
        $self->restore($dbtype);
    }

    # Lose the hidden table details
    delete $self->{'conf'}->{'hidden'};

    return;
  }

  my $adaptor = $self->get_DBAdaptor($dbtype, 1);

  if ( !@tables ) {
    # Restore all of the tables for this database
    @tables = keys %{ $self->{'conf'}->{$dbtype}->{'hidden'} };
  }

  foreach my $table (@tables) {
    my $hidden_name = $self->{'conf'}->{$dbtype}->{'hidden'}->{$table};

    # Delete current contents of table
    $adaptor->dbc->do("DELETE FROM $table");
    # Copy contents of tmp table back into main table
    $adaptor->dbc->do("INSERT INTO $table SELECT * FROM $hidden_name");
    # Drop temp table
    $adaptor->dbc->do("DROP TABLE $hidden_name");
    # Delete value from hidden table configuration
    delete $self->{'conf'}->{$dbtype}->{'hidden'}->{$table};
  }
  return;
}

=head2 save

  Arg [1]    : string $dbtype
               The type of the database containing the hidden/saved table
  Arg [2]    : string $table
               The name of the table to save
  Example    : $multi_test_db->save('core', 'gene', 'transcript', 'exon');
  Description: Saves the contents of specific table(s) in the specified db.
               The table(s) are first renamed and an empty table are created 
               in their place by reading the table schema file.  The contents
               of the renamed table(s) are then copied back into the newly
               created tables.  The method piggy-backs on the hide method
               and simply adds in the copying/insertion call.
  Returntype : none
  Exceptions : thrown if the adaptor for dbtype is not available
               warning if a table cannot be copied if the hidden table does not 
               exist
  Caller     : general

=cut

sub save {
  my ( $self, $dbtype, @tables ) = @_;

  # Use the hide method to build the basic tables
  $self->hide( $dbtype, @tables );

  my $adaptor = $self->get_DBAdaptor($dbtype, 1);

  foreach my $table (@tables) {
    my $hidden_name = '';
    # Only do if the hidden table exists
    if ( $self->{'conf'}->{$dbtype}->{'hidden'}->{$table} ) {
      $hidden_name = "_hidden_$table";
      # Copy the data from the hidden table into the new table
      $adaptor->dbc->do("insert into $table select * from $hidden_name");
    } 
    else {
      $self->diag("!! Hidden table '$hidden_name' does not exist so saving is not possible");
    }
  }
  return;
}

=head2 save_permanent

  Arg [1]    : string $dbtype
               The type of the database containing the hidden/saved table
  Arg [2-N]  : string $table
               The name of the table to save
  Example    : $multi_test_db->save_permanent('core', 'gene', 'transcript');
  Description: Saves the contents of specific table(s) in the specified db.
               The backup tables are not deleted by restore() or cleanup(), so
               this is mainly useful for debugging.
  Returntype : none
  Exceptions : thrown if the adaptor for dbtype is not available
               warning if a table cannot be copied if the hidden table does not 
               exist
  Caller     : general

=cut

sub save_permanent {
  my ( $self, $dbtype, @tables ) = @_;

  if ( !( $dbtype && @tables ) ) {
      die("dbtype and table args must be defined\n");
  }

  my $adaptor = $self->get_DBAdaptor($dbtype, 1);

  $self->{'conf'}->{$dbtype}->{'_counter'}++;

  foreach my $table (@tables) {
    my $hidden_name = "_bak_$table" . "_" . $self->{'conf'}->{$dbtype}->{'_counter'};
    $adaptor->dbc->do("CREATE TABLE $hidden_name SELECT * FROM $table");
  }
  return;
}

sub _db_exists {
  my ( $self, $db, $db_name ) = @_;
  return 0 if ! $db_name;
  my $db_names = $db->selectall_arrayref('SHOW DATABASES');
  foreach my $db_name_ref (@{$db_names}) {
    return 1 if $db_name_ref->[0] eq $db_name;
  }
  return 0;
}

sub compare {
  my ( $self, $dbtype, $table ) = @_;
  $self->diag('!! Compare method not yet implemented');
  return;
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

sub _create_db_name {
  my ( $self, $dbtype ) = @_;

  my @localtime = localtime();
  my $date      = strftime '%Y%m%d', @localtime;
  my $time      = strftime '%H%M%S', @localtime;

  my $species = $self->species();

  # Create a unique name using host and date / time info
  my $db_name = sprintf(
      '%s_test_db_%s_%s_%s_%s',
      ( exists $ENV{'LOGNAME'} ? $ENV{'LOGNAME'} : $ENV{'USER'} ),
      $species, $dbtype, $date, $time
  );

  return $db_name;
}

sub cleanup {
  my ($self) = @_;

  # Remove all of the handles on db_adaptors
  %{$self->{db_adaptors}} = ();

  # Delete each of the created temporary databases
  foreach my $dbtype ( keys %{ $self->{conf} } ) {
    my $db_conf = $self->{conf}->{$dbtype};
    next if $db_conf->{preloaded};
    my $db = $self->_db_conf_to_dbi($db_conf);
    my $dbname  = $db_conf->{'dbname'};
    $self->note("Dropping database $dbname");
    eval {$db->do("DROP DATABASE $dbname");};
    $self->diag("Could not drop datbaase $dbname: $EVAL_ERROR") if $EVAL_ERROR;
    $db->disconnect();
  }

  my $conf_file = $self->get_frozen_config_file_path();
  # Delete the frozen configuration file
  if ( -e $conf_file && -f $conf_file ) {
    $self->note("Deleting $conf_file");
    unlink $conf_file;
  }
  return;
}

sub _db_conf_to_dbi {
  my ($self, $db_conf, $options) = @_;
  my %params = (host => $db_conf->{host}, port => $db_conf->{port});
  %params = (%params, %{$options}) if $options;
  my $param_str = join(q{;}, map { $_.'='.$params{$_} } keys %params);
  my $locator = sprintf('DBI:%s:%s', $db_conf->{driver}, $param_str);
  my $db = DBI->connect( $locator, $db_conf->{user}, $db_conf->{pass}, { RaiseError => 1 } );
  return $db if $db;
  $self->diag("Can't connect to database '$locator': ". $DBI::errstr);
  return;
}

sub DESTROY {
  my ($self) = @_;

  if ( $ENV{'RUNTESTS_HARNESS'} ) {
    # Restore tables, do nothing else we want to use the database
    # for the other tests as well
    $self->note('Leaving database intact on server');
    $self->restore();
  } else {
    # We are runnning a stand-alone test, cleanup created databases
    $self->note('Cleaning up...');

    # Restore database state since we may not actually delete it in
    # the cleanup - it may be defined as a preloaded database
    $self->restore();
    $self->cleanup();
  }
  return;
}

1;
