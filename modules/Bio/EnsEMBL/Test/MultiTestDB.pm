=head1 LICENSE

Copyright [2016] EMBL-European Bioinformatics Institute
Copyright [2016] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

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

You can also use the env variable C<RUNTESTS_HARNESS_NORESTORE> which avoids
the running of restore() when C<RUNTESTS_HARNESS> is active. B<ONLY> use this
when you are going to destory a MultiTestDB but DBs should not be cleaned up
or restored e.g. threads. See dbEntries.t for an example of how to use it.

=cut

use strict;
use warnings;

use DBI;
use Data::Dumper;
use English qw(-no_match_vars);
use File::Basename;
use File::Copy;
use File::Spec::Functions;
use IO::File;
use IO::Dir;
use POSIX qw(strftime);

use Bio::EnsEMBL::Utils::IO qw/slurp work_with_file/;
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
  DEFAULT_CONF_FILE => 'MultiTestDB.conf.default',
  DUMP_DIR  => 'test-genome-DBs',
  ALTERNATIVE_DUMP_DIR => 'test-Genome-DBs',
};

sub get_db_conf {
  my ($class, $current_directory) = @_;
  # Create database from local config file
  my $conf_file = catfile( $current_directory, CONF_FILE );
  my $db_conf = $class->_eval_file($conf_file);
  die "Error while loading config file" if ! defined $db_conf;
  
  #Get the default if defined
  my $default_conf_file = catfile( $current_directory, DEFAULT_CONF_FILE );
  my $default_db_conf;
  if(-f $default_conf_file) {
    $default_db_conf = $class->_eval_file($default_conf_file);
  }
  else {
    my $tmpl = 'Cannot find the default config file at "%s"; if things do not work then this might be why';
    $class->note(sprintf($tmpl, $default_conf_file));
    $default_db_conf = {};
  }
  
  my %merged = (
    %{$default_db_conf},
    %{$db_conf},
  );
  
  return \%merged;
}

sub base_dump_dir {
  my ($class, $current_directory) = @_;
  my $dir = catdir( $current_directory, DUMP_DIR);
  if(! -d $dir) {
    my $alternative_dir = catdir($current_directory, ALTERNATIVE_DUMP_DIR);
    if(-d $alternative_dir) {
      $dir = $alternative_dir;
    }
  }
  return $dir;
}

sub new {
  my ($class, $species, $user_submitted_curr_dir, $skip_database_loading) = @_;

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
  $self->_rebless;

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
    if(!$skip_database_loading) {
      # Load the databases and generate the conf hash
      $self->load_databases();
      # Freeze configuration in a file
      $self->store_config();
    }
    else {
      $self->{conf} = {};
    }
  }

  # Generate the db_adaptors from the $self->{'conf'} hash
  if(!$skip_database_loading) {
    $self->create_adaptors();
  }

  return $self;
}

#
# Rebless based on driver
#
sub _rebless {
    my ($self) = @_;
    my $driver = $self->db_conf->{driver};
    my $new_class = ref($self) . '::' . $driver;
    eval "require $new_class";
    if ($EVAL_ERROR) {
        $self->diag("Could not rebless to '$new_class': $EVAL_ERROR");
    } else {
        bless $self, $new_class;
        $self->note("Reblessed to '$new_class'");
    }
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
  if ( !-e $file ) {
    throw("Required configuration file '$file' does not exist");
  }
  my $contents = slurp($file);
  my $v = eval $contents;
  die "Could not read in configuration file '$file': $EVAL_ERROR" if $EVAL_ERROR;
  return $v;
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
    $self->create_adaptor($dbtype);
  }
  return;
}

sub create_adaptor {
  my ($self, $dbtype) = @_;
  my $db = $self->{conf}->{$dbtype};
  my $module = $db->{module};
  if(eval "require $module") {
    my %args = map { ( "-${_}", $db->{$_} ) } qw(dbname user pass port host driver species group);
    if($dbtype eq 'hive') {
      $args{"-no_sql_schema_version_check"} = 1;
      $args{'-url'} = 'mysql://' . $args{'-user'} . ':' . $args{'-pass'} . '@' . $args{'-host'} . ':' . $args{'-port'} . '/' . $args{'-dbname'};
    }
    if($dbtype eq 'funcgen') {
      %args = (%args, map { ("-dnadb_${_}", $db->{${_}}) } qw/host user pass port/);
      # We wish to select the most recent core database generated by this user's test scripts.
      # This amounts to searching for the datase with the same prefix as the funcgen one, with the 
      # highest timestamp in suffix, i.e. the first element of the set of candidate name in reverse 
      # alphabetical order.
      my $mysql_out;
      if ($args{'-pass'}) {
        $mysql_out = `mysql -NB -u $args{'-user'} -p$args{'-pass'} -h $args{'-host'} -P $args{'-port'} -e 'show databases'`;
      } else {
        $mysql_out = `mysql -NB -u $args{'-user'} -h $args{'-host'} -P $args{'-port'} -e 'show databases'`;
      }
      my @databases = split(/^/, $mysql_out);
      my $dnadb_pattern = $args{'-dbname'};
      $dnadb_pattern =~ s/_funcgen_.*/_core_/;
      my @core_databases = grep /^$dnadb_pattern/, @databases;
      scalar(@core_databases) > 0 || die "Did not find any core database with pattern $dnadb_pattern:\n".join("\n", @databases);
      my @sorted_core_databases = sort {$b cmp $a} @core_databases;
      my $chosen_database = shift(@sorted_core_databases);
      chomp $chosen_database;
      $args{'-dnadb_name'} = $chosen_database; 
    }
    my $adaptor = eval{ $module->new(%args) };
    if($EVAL_ERROR) {
      $self->diag("!! Could not instantiate $dbtype DBAdaptor: $EVAL_ERROR");
    }
    else {
      $self->{db_adaptors}->{$dbtype} = $adaptor;
    }
  }
  return;
}

sub db_conf {
  my ($self) = @_;
  if(! $self->{db_conf}) {
    $self->{db_conf} = $self->get_db_conf($self->curr_dir());
  }
  return $self->{db_conf};
}

sub dbi_connection {
  my ($self) = @_;
  if(!$self->{dbi_connection}) {
    my $db = $self->_db_conf_to_dbi($self->db_conf(), $self->_dbi_options);
    if ( ! defined $db ) {
      $self->diag("!! Can't connect to database: ".$DBI::errstr);
      return;
    }
    $self->{dbi_connection} = $db;
  }
  return $self->{dbi_connection};
}

sub disconnect_dbi_connection {
  my ($self) = @_;
  if($self->{dbi_connection}) {
    $self->do_disconnect;
    delete $self->{dbi_connection};
  }
  return;
}

sub load_database {
  my ($self, $dbtype) = @_;
  my $db_conf = $self->db_conf();
  my $databases = $db_conf->{databases};
  my $preloaded = $db_conf->{preloaded} || {};
  my $species = $self->species();
  
  if(! $databases->{$species}) {
    die "Requested a database for species $species but the MultiTestDB.conf knows nothing about this";
  }
  
  my $config_hash = { %$db_conf };
  delete $config_hash->{databases};
  $config_hash->{module} = $databases->{$species}->{$dbtype};
  $config_hash->{species} = $species;
  $config_hash->{group} = $dbtype;
  $self->{conf}->{$dbtype} = $config_hash;
  my $dbname = $preloaded->{$species}->{$dbtype};
  my $driver_handle = $self->dbi_connection();
  if($dbname && $self->_db_exists($driver_handle, $dbname)) {
    $config_hash->{dbname} = $dbname;
    $config_hash->{preloaded} = 1;
  }
  else {
    if(! $dbname) {
      $dbname = $self->create_db_name($dbtype);
      delete $config_hash->{preloaded};
    }
    else {
      $config_hash->{preloaded} = 1;
    }

    $config_hash->{dbname} = $dbname;
    $self->note("Creating database $dbname");
    my %limits = ( 'mysql' => 64, 'pg' => 63 );
    if (my $l = $limits{lc $self->db_conf->{driver}}) {
        if (length($dbname) > $l) {
            die "Cannot create the database because its name is longer than the maximum the driver allows ($l characters)";
        }
    }
    my $db = $self->create_and_use_db($driver_handle, $dbname);

    my $base_dir = $self->base_dump_dir($self->curr_dir());
    my $dir_name = catdir( $base_dir, $species,  $dbtype );
    $self->load_sql($dir_name, $db, 'table.sql', 'sql');
    $self->load_txt_dumps($dir_name, $dbname, $db);
    $self->note("Loaded database '$dbname'");
  }
  return;
}

sub load_databases {
  my ($self) = shift; 
  my $species = $self->species();

  $self->note("Trying to load [$species] databases");  
  # Create a configuration hash which will be frozen to a file
  $self->{'conf'} = {};

  my @db_types = keys %{$self->db_conf()->{databases}->{$species}};
  foreach my $dbtype (@db_types) {
    $self->load_database($dbtype);
  }

  $self->disconnect_dbi_connection();
  return;
}

#
# Loads a DB from a single table.sql file or a set of *.sql files
#

sub load_sql {
  my ($self, $dir_name, $db, $override_name, $suffix, $override_must_exist) = @_;
  my @files = $self->driver_dump_files($dir_name, $suffix);

  my ($all_tables_sql) = grep { basename($_) eq $override_name } @files;
  return if $override_must_exist and not $all_tables_sql;

  my $sql_com = q{};
  if($all_tables_sql) {
    @files = ($all_tables_sql);
  }
  foreach my $sql_file (@files) {
    $self->note("Reading SQL from '$sql_file'");
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

sub driver_dump_files {
  my ($self, $dir_name, $suffix) = @_;
  my $dir = IO::Dir->new($dir_name);
  if(! defined $dir) {
    $self->diag(" !! Could not open dump directory '$dir_name'");
    return;
  }
  my $driver_dir_name = catdir($dir_name, $self->db_conf->{driver});
  my $driver_dir = IO::Dir->new($driver_dir_name);
  if ($driver_dir) {
      $dir = $driver_dir;
      $dir_name = $driver_dir_name;
  }
  my @files = map { catfile($dir_name, $_) } grep { $_ =~ /\.${suffix}$/ } $dir->read();
  $dir->close();
  return (@files);
}

sub load_txt_dumps {
  my ($self, $dir_name, $dbname, $db) = @_;
  my $tables = $self->tables($db, $dbname);
  foreach my $tablename (@{$tables}) {
    my $txt_file = catfile($dir_name, $tablename.'.txt');
    if(! -f $txt_file || ! -r $txt_file) {
      next;
    }
    $self->do_pre_sql($dir_name, $tablename, $db);
    $db = $self->load_txt_dump($txt_file, $tablename, $db); # load_txt_dump may re-connect $db!
    $self->do_post_sql($dir_name, $tablename, $db);
  }
  return;
}

sub do_pre_sql {
  my ($self, $dir_name, $tablename, $db) = @_;
  $self->load_sql($dir_name, $db, "$tablename.pre", 'pre', 1);
  return;
}

sub do_post_sql {
  my ($self, $dir_name, $tablename, $db) = @_;
  $self->load_sql($dir_name, $db, "$tablename.post", 'post', 1);
  return;
}

sub tables {
  my ($self, $db, $dbname) = @_;
  my @tables;
  my $sth = $db->table_info(undef, $self->_schema_name($dbname), q{%}, 'TABLE');
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
      die "adaptor for $type is not available";
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
    $adaptor->dbc->do("CREATE TABLE $hidden_name AS SELECT * FROM $table");
    # Delete the contents of the original table
    $adaptor->dbc->do("DELETE FROM $table");
    # Update the temporary table configuration
    $self->{'conf'}->{$dbtype}->{'hidden'}->{$table} = $hidden_name;

    $self->note("The table ${table} has been hidden in ${dbtype}");
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

    $self->note("The table ${table} has been restored in ${dbtype}");    
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
      $self->note("The table ${table} contents has been saved in ${dbtype}");
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
    $adaptor->dbc->do("CREATE TABLE $hidden_name AS SELECT * FROM $table");
    $self->note("The table ${table} has been permanently saved in ${dbtype}");
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

sub create_db_name {
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
  if (my $path = $self->_db_path($self->dbi_connection)) {
      $db_name = catfile($path, $db_name);
  }
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
    $self->_drop_database($db, $dbname);
  }

  my $conf_file = $self->get_frozen_config_file_path();
  # Delete the frozen configuration file
  if ( -e $conf_file && -f $conf_file ) {
    $self->note("Deleting $conf_file");
    unlink $conf_file;
  }
  return;
}

sub DESTROY {
  my ($self) = @_;

  if ( $ENV{'RUNTESTS_HARNESS'} ) {
    # Restore tables, do nothing else we want to use the database
    # for the other tests as well
    $self->note('Leaving database intact on server');
    if(!$ENV{'RUNTESTS_HARNESS_NORESTORE'}) {
      $self->restore();
    }
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
