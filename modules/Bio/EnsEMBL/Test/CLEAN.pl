use strict;
use warnings;

use File::Basename;
use File::Spec;
use Test::More;

use Bio::EnsEMBL::Test::MultiTestDB;

use constant CONF_FILE => 'MultiTestDB.conf';

$| = 1;

diag 'Starting database and files cleaning up...';

my $curr_file = __FILE__;
my $conf_file = File::Spec->catfile(dirname($curr_file), CONF_FILE);

if ( $conf_file =~ m#^/# ) {
    # The configuration file is in the current directory.
    $conf_file = File::Spec->catfile(File::Spec->curdir(), CONF_FILE);
}

my $db_conf = do $conf_file;

foreach my $species ( keys %{ $db_conf->{'databases'} } ) {
    my $multi = Bio::EnsEMBL::Test::MultiTestDB->new($species);
}

note "Deleting $curr_file";
my $result = unlink $curr_file;
ok($result, 'Unlink of '.$curr_file.' worked');

done_testing();