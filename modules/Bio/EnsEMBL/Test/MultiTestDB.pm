package Bio::EnsEMBL::Test::MultiTestDB;

=pod

=head1 NAME - EnsTestDB

=head1 SYNOPSIS

=head1 DESCRIPTION


=head1 METHODS

=cut

use strict;
use warnings;

use DBI;
use Data::Dumper;
use File::Spec::Functions;
use IO::File;
use IO::Dir;
use POSIX qw(strftime);

use Bio::EnsEMBL::Utils::Exception qw( warning throw );

use base 'Test::Builder::Module';

$| = 1;

sub diag {
  my ($self, @args) = @_;
  $self->builder()->diag(@args);
}

sub note {
  my ($self, @args) = @_;
  $self->builder()->note(@args);
}

use constant {
    # Homo sapiens is used if no species is specified
    DEFAULT_SPECIES => 'homo_sapiens',

    # Configuration file extension appended onto species name
    FROZEN_CONF_SUFFIX => 'MultiTestDB.frozen.conf',

    CONF_FILE => 'MultiTestDB.conf',
    DUMP_DIR  => 'test-genome-DBs'
};

sub new
{
    my ( $class, $species ) = @_;

    my $self = bless {}, $class;

    # Go and grab the current directory and store it away
    my ( $package, $file, $line ) = caller;

    my $curr_dir = ( File::Spec->splitpath($file) )[1];
    if (!defined($curr_dir) || $curr_dir eq '') {
      $curr_dir = curdir();
    }
    $self->curr_dir($curr_dir);
    
    my $target_file = catfile($self->curr_dir() , 'CLEAN.t');

    if (! -e $target_file) {
        my $clean_file =
          catfile( ( File::Spec->splitpath(__FILE__) )[1], 'CLEAN.pl' );

        if ( system( 'cp', $clean_file, $target_file ) ) {
            warning("# !! Could not copy $clean_file to $target_file\n");
        }
    }

    if ( !defined $species ) {
        $species = DEFAULT_SPECIES;
    }

    $self->species($species);

    if ( -e catfile( $curr_dir, $species . '.' . FROZEN_CONF_SUFFIX ) )
    {
        $self->load_config();
    } else {
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
sub load_config
{
    my $self = shift;

    my $conf = catfile( $self->curr_dir(),
                        $self->species() . '.' . FROZEN_CONF_SUFFIX );

    eval {
        # Read file into $self->{'conf'}
        $self->{'conf'} = do $conf;
    };

    if ($@) {
        die("Could not read frozen configuration file '$conf'\n");
    }
}

#
# Store $self->{'conf'} hash into a file
#
sub store_config
{
    my $self = shift;

    my $conf = catfile( $self->curr_dir(),
                        $self->species() . '.' . FROZEN_CONF_SUFFIX );

    my $fh = IO::File->new(">$conf")
      or die "Could not open configuration file '$conf'\n";

    my $string = Dumper( $self->{'conf'} );

    # Strip off leading '$VAR1 = '
    $string =~ s/^[\$]VAR1\s*=//;

    # Store configuration in file
    $fh->print($string);

    $fh->close();
}

#
# Create a set of adaptors based on the $self->{'conf'} hash
#
sub create_adaptors
{
    my $self = shift;

    # Establish a connection to each of the databases in the
    # configuration
    foreach my $dbtype ( keys %{ $self->{'conf'} } ) {

        my $db = $self->{'conf'}->{$dbtype};
        my $adaptor;
        my $module = $db->{'module'};
		my %dnadb_params;

		if($dbtype eq 'funcgen'){
		  #Can specify just host (and user) for auto select
		  %dnadb_params = (
						   -dnadb_host => $db->{dnadb_host},
						   -dnadb_user => $db->{dnadb_user},
						   -dnadb_pass => $db->{dnadb_pass},
						   -dnadb_port => $db->{dnadb_port},
						   -dnadb_name => $db->{dnadb_name},
						  );

		}

        # Try to instantiate an adaptor for this database
        if ( eval "require $module" ) {
		  
		  eval {
                $adaptor = $module->new(
										-dbname  => $db->{'dbname'},
										-user    => $db->{'user'},
										-pass    => $db->{'pass'},
										-port    => $db->{'port'},
										-host    => $db->{'host'},
										-driver  => $db->{'driver'},
										-species => $self->{'species'},
										%dnadb_params,
                );
            };
        }

        if ($@) {
            warning(
                "# !! Could not instantiate $dbtype DBAdaptor:\n$@" );
        } else {
            $self->{'db_adaptors'}->{$dbtype} = $adaptor;
        }
    }
}

sub load_databases
{
    my ($self) = shift;

    $self->note("Trying to load [$self->{'species'}] databases");

    # Create database from conf and from zip files
    my $conf_file = catfile( $self->curr_dir(), CONF_FILE );

    if ( !-e $conf_file ) {
        throw("Required conf file '$conf_file' does not exist");
    }

    my $db_conf = do $conf_file;
    if ( !defined($db_conf) ) {
      die("Error while loading config file");
    }

    my $port   = $db_conf->{'port'};
    my $driver = $db_conf->{'driver'};
    my $host   = $db_conf->{'host'};
    my $pass   = $db_conf->{'pass'};
    my $user   = $db_conf->{'user'};
    my $zip    = $db_conf->{'zip'};

    # Create a configuration hash which will be frozen to a file
    $self->{'conf'} = {};

    # Connect to the database
    my $locator =
      sprintf( "DBI:%s:host=%s;port=%s;mysql_local_infile=1",
        $driver, $host, $port );

    my $db =
      DBI->connect( $locator, $user, $pass, { RaiseError => 1 } );

    if ( !defined $db ) {
        warning( "# !! Can't connect to database '$locator': "
              . $DBI::errstr );
        return;
    }

    # Only unzip if there are non-preloaded datbases
  UNZIP:
    foreach my $dbtype (
						keys %{ $db_conf->{'databases'}->{ $self->{'species'} } } )
    {
	  if (( ! exists $db_conf->{'preloaded'}->{ $self->{'species'} }->{$dbtype}) || 
		  ( !_db_exists(
						$db,
						$db_conf->{'preloaded'}->{ $self->{'species'} }
						->{$dbtype}
					   )
		  )
		 )
        {
		  # Unzip database files
		  $self->unzip_test_dbs( catfile( $self->curr_dir(), $zip ) );
		  last UNZIP;
        }
    }

    # Create a database for each database specified
    foreach my $dbtype (
        keys %{ $db_conf->{'databases'}->{ $self->{'species'} } } )
    {
        # Copy the general configuration into a dbtype specific
        # configuration
        $self->{'conf'}->{$dbtype} = {};
        %{ $self->{'conf'}->{$dbtype} } = %$db_conf;
        $self->{'conf'}->{$dbtype}->{'module'} =
          $db_conf->{'databases'}->{ $self->{'species'} }->{$dbtype};

        # It is not necessary to store the databases and zip bits of
        # info
        delete $self->{'conf'}->{$dbtype}->{'databases'};
        delete $self->{'conf'}->{$dbtype}->{'zip'};

        # Don't create a database if there is a preloaded one specified
        if (( $db_conf->{'preloaded'}->{ $self->{'species'} }->{$dbtype}) && 
			( _db_exists(
						 $db,
						 $db_conf->{'preloaded'}->{ $self->{'species'} }->{$dbtype}
						)))
		  {

			# Store the temporary database name in the dbtype specific
			# configuration
            $self->{'conf'}->{$dbtype}->{'dbname'} =
              $db_conf->{'preloaded'}->{ $self->{'species'} }
              ->{$dbtype};
            $self->{'conf'}->{$dbtype}->{'preloaded'} = 1;
        } else {
            # Create a temporary database name
            my $dbname =
              $db_conf->{'preloaded'}->{ $self->{'species'} }
              ->{$dbtype};

            if ( !defined $dbname ) {
                $dbname = $self->_create_db_name($dbtype);
                delete $self->{'conf'}->{$dbtype}->{'preloaded'};
            } else {
                $self->{'conf'}->{$dbtype}->{'preloaded'} = 1;
            }

            # Store the temporary database name in the dbtype specific
            # configuration
            $self->{'conf'}->{$dbtype}->{'dbname'} = $dbname;

            $self->note("Creating database $dbname");

            if ( !$db->do("CREATE DATABASE $dbname") ) {
                warning("# !! Could not create database [$dbname]");
                return;
            }

            # Copy the general configuration into a dbtype specific
            # configuration

            $db->do("USE $dbname");

            # Load the database with data
            my $dir_name = catdir( $self->curr_dir(), DUMP_DIR,
                                   $self->species(),  $dbtype );

            my $dir = IO::Dir->new($dir_name);

            if ( !defined $dir ) {
                warning(
                    "# !! Could not open dump directory '$dir_name'" );
                return;
            }

            my @files = $dir->read();

            # Read in table creat statements from *.sql files and
            # process them with DBI

            foreach my $sql_file ( grep /\.sql$/, @files ) {

                $sql_file = catfile( $dir_name, $sql_file );

                my $fh = IO::File->new($sql_file);

                if ( !defined $fh ) {
                    warning(
                        "# !! Could not read SQL file '$sql_file'\n");
                    next;
                }

                my $sql_com = '';

                while ( defined( my $line = $fh->getline() ) ) {
                    if ( $line =~ /^#/ || $line !~ /\S/ ) {
                        # Ignore comments and white-space lines
                        next;
                    }
                    $sql_com .= $line;
                }

                $fh->close();

                # Chop off the last ';'
                $sql_com =~ s/;$//;

                foreach my $this_sql_com ( split( /;/, $sql_com ) ) {
                    $db->do($this_sql_com);
                }

                # Import data from the text files of the same name
                $sql_file =~ m#.*/(.*)\.sql#;
                my $tablename = $1;

                ( my $txt_file = $sql_file ) =~ s/\.sql$/.txt/;

                if ( !( -f $txt_file && -r $txt_file ) ) {
                    warning(
                        "# !! Could not read data file '$txt_file'\n");
                    next;
                }

                $db->do("LOAD DATA LOCAL INFILE '$txt_file' "
                      . "INTO TABLE $tablename" );

            }

            $dir->close();
        }
    }

    $db->disconnect();
}

sub unzip_test_dbs
{
    my ( $self, $zipfile ) = @_;

    if ( -d catdir( $self->curr_dir(), DUMP_DIR ) ) {
      warning(   "# !! '"
               . catdir( $self->curr_dir(), DUMP_DIR )
               . "' already unpacked\n" );
      return;
    }

    if ( !$zipfile ) {
        throw("zipfile argument is required\n");
    }

    if ( !-f $zipfile ) {
        warning("# !! Zip archive $zipfile could not be found\n");
        return;
    }

    # Unzip the zip file quietly
    print("# Unzipping test database achive file '$zipfile'\n");
    system( 'unzip', '-q', $zipfile, '-d', $self->curr_dir() );
}

sub get_DBAdaptor
{
    my ( $self, $type ) = @_;

    if ( !$type ) {
        die("type arg must be specified\n");
    }

    if ( !$self->{'db_adaptors'}->{$type} ) {
        warning(
            "# !! Database adaptor of type $type is not available\n");
        return undef;
    }

    return $self->{'db_adaptors'}->{$type};
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

sub hide
{
    my ( $self, $dbtype, @tables ) = @_;

    if ( !( $dbtype && @tables ) ) {
        die("dbtype and table args must be defined\n");
    }

    my $adaptor = $self->get_DBAdaptor($dbtype);

    if ( !$adaptor ) {
        die "adaptor for $dbtype is not available\n";
    }

    foreach my $table (@tables) {

        if ( $self->{'conf'}->{$dbtype}->{'hidden'}->{$table} ) {
            warning("# !! Table '$table' is already hidden "
                  . "and cannot be hidden again\n" );
            next;
        }

        my $hidden_name = "_hidden_$table";

        # Copy contents of table into a temporary table

        my $sth =
          $adaptor->dbc->prepare(
            "CREATE TABLE $hidden_name SELECT * FROM $table");

        $sth->execute();
        $sth->finish();

        # Delete the contents of the original table
        $sth = $adaptor->dbc->prepare("DELETE FROM $table");
        $sth->execute();
        $sth->finish();

        # Update the temporary table configuration
        $self->{'conf'}->{$dbtype}->{'hidden'}->{$table} = $hidden_name;
    }
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

sub restore
{
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

    my $adaptor = $self->get_DBAdaptor($dbtype);

    if ( !$adaptor ) {
        die "Adaptor for $dbtype is not available";
    }

    if ( !@tables ) {
        # Restore all of the tables for this database
        @tables = keys %{ $self->{'conf'}->{$dbtype}->{'hidden'} };
    }

    foreach my $table (@tables) {
        my $hidden_name =
          $self->{'conf'}->{$dbtype}->{'hidden'}->{$table};

        # Delete current contents of table
        my $sth = $adaptor->dbc->prepare("DELETE FROM $table");
        $sth->execute();
        $sth->finish();

        # Copy contents of tmp table back into main table
        $sth =
          $adaptor->dbc->prepare(
            "INSERT INTO $table " . "SELECT * FROM $hidden_name" );
        $sth->execute();
        $sth->finish();

        # Drop temp table
        $sth = $adaptor->dbc->prepare("DROP TABLE $hidden_name");
        $sth->execute();
        $sth->finish();

        # Delete value from hidden table configuration
        delete $self->{'conf'}->{$dbtype}->{'hidden'}->{$table};
    }
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

sub save
{
    my ( $self, $dbtype, @tables ) = @_;

    # Use the hide method to build the basic tables
    $self->hide( $dbtype, @tables );

    my $adaptor = $self->get_DBAdaptor($dbtype);

    if ( !$adaptor ) {
        die "adaptor for $dbtype is not available\n";
    }

    my $hidden_name = '';
    foreach my $table (@tables) {

        # Only do if the hidden table exists
        if ( $self->{'conf'}->{$dbtype}->{'hidden'}->{$table} ) {

            $hidden_name = "_hidden_$table";

            # Copy the data from the hidden table into the new table
            my $sth =
              $adaptor->dbc->prepare(
                "insert into $table " . "select * from $hidden_name" );
            $sth->execute();
        } else {
            warning("# !! Hidden table '$hidden_name' does not exist "
                  . "so saving is not possible\n" );
        }
    }
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

sub save_permanent
{
    my ( $self, $dbtype, @tables ) = @_;

    if ( !( $dbtype && @tables ) ) {
        die("dbtype and table args must be defined\n");
    }

    my $adaptor = $self->get_DBAdaptor($dbtype);

    if ( !$adaptor ) {
        die "adaptor for $dbtype is not available\n";
    }

    $self->{'conf'}->{$dbtype}->{'_counter'}++;

    foreach my $table (@tables) {

        my $hidden_name =
          "_bak_$table" . "_"
          . $self->{'conf'}->{$dbtype}->{'_counter'};

        my $sth =
          $adaptor->dbc->prepare(
            "CREATE TABLE $hidden_name " . "SELECT * FROM $table" );

        $sth->execute();
        $sth->finish();
    }
}

sub _db_exists
{
    my ( $db, $db_name ) = @_;

    my $db_names = $db->selectall_arrayref("SHOW DATABASES");

    for my $db_name_ref (@$db_names) {
        if ( $db_name_ref->[0] eq $db_name ) {
            return 1;
        }
    }

    return 0;
}

sub compare
{
    my ( $self, $dbtype, $table ) = @_;

    warning("# !! Compare method not yet implemented\n");

}

sub species
{
    my ( $self, $species ) = @_;

    if ($species) {
        $self->{'species'} = $species;
    }

    return $self->{'species'};
}

sub curr_dir
{
    my ( $self, $cdir ) = @_;

    if ($cdir) {
        $self->{'_curr_dir'} = $cdir;
    }

    return $self->{'_curr_dir'};
}

sub _create_db_name
{
    my ( $self, $dbtype ) = @_;

    my @localtime = localtime();
    my $date      = strftime "%Y%m%d", @localtime;
    my $time      = strftime "%H%M%S", @localtime;

    my $species = $self->species();

    # Create a unique name using host and date / time info
    my $db_name = sprintf(
        "%s_test_db_%s_%s_%s_%s",
        ( exists $ENV{'LOGNAME'} ? $ENV{'LOGNAME'} : $ENV{'USER'} ),
        $species, $dbtype, $date, $time
    );

    return $db_name;
}

sub cleanup
{
    my $self = shift;

    # Delete the unpacked schema and data files
    # $self->note("Deleting " . catdir( $self->curr_dir(), DUMP_DIR ));
    # $self->_delete_files( catdir( $self->curr_dir(), DUMP_DIR ) );


    # Remove all of the handles on db_adaptors
    foreach my $dbtype ( keys %{ $self->{'db_adaptors'} } ) {
        delete $self->{'db_adaptors'}->{$dbtype};
    }

    # Delete each of the created temporary databases
    foreach my $dbtype ( keys %{ $self->{'conf'} } ) {

        my $db_conf = $self->{'conf'}->{$dbtype};
        my $host    = $db_conf->{'host'};
        my $user    = $db_conf->{'user'};
        my $pass    = $db_conf->{'pass'};
        my $port    = $db_conf->{'port'};
        my $driver  = $db_conf->{'driver'};
        my $dbname  = $db_conf->{'dbname'};

        if ( $db_conf->{'preloaded'} ) {
            next;
        }

        # Connect to the database
        my $locator =
          sprintf( "DBI:%s:host=%s;port=%s", $driver, $host, $port );

        my $db =
          DBI->connect( $locator, $user, $pass, { RaiseError => 1 } )
          or die "Can't connect to database '$locator': "
          . $DBI::errstr;

        $self->note("Dropping database $dbname");

        $db->do("DROP DATABASE $dbname");
        $db->disconnect();
    }

    my $conf_file = catfile( $self->curr_dir(),
                          $self->species() . '.' . FROZEN_CONF_SUFFIX );

    # Delete the frozen configuration file
    if ( -e $conf_file && -f $conf_file ) {
        $self->note("Deleting $conf_file");
        unlink $conf_file;
    }
}

sub _delete_files
{
    my ( $self, $dir_name ) = @_;

    my $dir = IO::Dir->new($dir_name);

    # Ignore files starting with '.'

    my @files = grep !/^\./, $dir->read();

    foreach my $file (@files) {

        $file = $dir_name . "/" . $file;
        if ( -d $file ) {
            # Call recursively on subdirectories
            $self->_delete_files($file);
        } else {
            unlink $file;
        }
    }
    $dir->close();

    rmdir($dir_name);
}

sub DESTROY
{
    my ($self) = shift;

    if ( $ENV{'RUNTESTS_HARNESS'} ) {
        # Restore tables, do nothing else we want to use the database
        # for the other tests as well
        $self->note("Leaving database intact on server");
        $self->restore();
    } else {
        # We are runnning a stand-alone test, cleanup created databases
        $self->note("Cleaning up...");

        # Restore database state since we may not actually delete it in
        # the cleanup - it may be defined as a preloaded database
        $self->restore();
        $self->cleanup();
    }
}

1;
