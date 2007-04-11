#!/usr/local/ensembl/bin/perl -w

use strict;
use warnings;

use File::Basename;
use Getopt::Long;
use Test::Harness qw( &runtests $verbose );

use IO::Dir;

our ( $opt_c, $opt_h, $opt_l, $opt_v );

if (
    !GetOptions(
        'clean|clear|c'           => \$opt_c,
        'help|h'                  => \$opt_h,
        'list|tests|list-tests|l' => \$opt_l,
        'verbose|v'               => \$opt_v
    )
  )
{
    die;
}

# If we were not given a directory as an argument, assume './'
if ( !@ARGV ) {
    push @ARGV, './';
}

# Print usage on '-h' command line option
if ($opt_h) {
    usage();
    exit;
}

# List test files on '-l' command line option
if ($opt_l) {
    foreach
      my $file ( grep { !/CLEAN\.t/ } @{ get_all_tests( \@ARGV ) } )
    {
        print "$file\n";
    }
    exit;
}

# Set environment variables
$ENV{'RUNTESTS_HARNESS'} = 1;

$verbose = $opt_v;

# Make sure proper cleanup is done if the user interrupts the tests
$SIG{'HUP'} = $SIG{'KILL'} = $SIG{'INT'} =
  sub { warn "\n\nINTERRUPT SIGNAL RECEIVED\n\n"; clean(); exit };

# Run all specified tests
eval {
    runtests( grep { !/CLEAN\.t/ } @{ get_all_tests( \@ARGV ) } );
};

clean( \@ARGV );


sub usage
{
    print <<EOT;
Usage:
\t$0 [-c] [-v] [<test files or directories> ...]
\t$0 -l        [<test files or directories> ...]
\t$0 -h

\t-l|--list|--tests|--list-tests\n\t\tlist available tests
\t-c|--clean|--clear\n\t\trun tests and clean up in each directory
\t\tvisited (default is not to clean up)
\t-v|--verbose\n\t\tbe verbose
\t-h|--help\n\t\tdisplay this help text

If no directory or test file is given on the command line, the script
will assume './' (the current directory).
EOT
}

=head2 get_all_tests

  Arg [21]    :(optional) listref $input_files_or_directories
               testfiles or directories to retrieve. If not specified all 
               "./" direcroty is the default.
  Example    : @test_files = read_test_dir('t');
  Description: Returns a list of testfiles in the directories specified by
               the @tests argument.  The relative path is given as well as
               with the testnames returned.  Only files ending with .t are
               returned.  Subdirectories are recursively entered and the test
               files returned within them are returned as well.
  Returntype : listref of strings.
  Exceptions : none
  Caller     : general

=cut

sub get_all_tests
{
    my ($input_files_directories) = @_;

    my @files;
    my @out = ();

    if ( $input_files_directories && @{$input_files_directories} ) {
        # Input files were specified so use them
        @files = @{$input_files_directories};
    } else {
        # Otherwise use every file in the directory

        my $dir = IO::Dir->new('.');

        if ( !defined $dir ) {
            warn("WARNING: cannot open directory '.'\n");
            return [];
        }

        @files = $dir->read();
        $dir->close();
    }

    # Put a  slash at the end of each directory name
    foreach my $dir ( @{$input_files_directories} ) {
        if ( -d $dir && $dir !~ m#/$# ) {
            $dir .= '/';
        }
    }

    while (my $file = shift @files) {
        # Filter out CVS directories
        if ($file eq 'CVS') {
            next;
        }

        if ( -d $file ) {
            $file =~ s#/$##;

            my $dir = IO::Dir->new($file);

            if ( !defined $dir ) {
                warn("WARNING: cannot open directory '$file'\n");
                next;
            }

            foreach my $another_file ( $dir->read() ) {
                # Filter out CVS files and ./ and ../
                if (   $another_file eq '.'
                    || $another_file eq '..'
                    || $another_file eq 'CVS' )
                {
                    next;
                }

                push @files, $file . '/' . $another_file;
            }

            $dir->close();
        } elsif ( $file =~ /\.t$/ ) {
            # Files ending with a '.t' are considered test files
            # Filter out files ending in ~

            if ( !-r $file || !-f $file ) {
                warn("WARNING: cannot read test file '$file'\n");
            }

            push @out, $file;
        }
    }

    return \@out;
}

sub clean
{
    my $tests = shift;

    # Unset environment variable indicating final cleanup should be
    # performed
    delete $ENV{'RUNTESTS_HARNESS'};

    if ($opt_c) {
        my %dirs;

        foreach my $file (@$tests) {
            if ( -d $file && !exists $dirs{ $file } ) {
                $dirs{$file} = 1;
            } else {
                my $dir = dirname($file);
                if ( !exists $dirs{$dir} ) {
                    $dirs{$dir} = 1;
                }
            }
        }
        eval {
            runtests( grep { /CLEAN\.t/ }
                  @{ get_all_tests( [ keys %dirs ] ) } );
        };
    }
}
