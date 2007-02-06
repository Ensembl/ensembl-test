use strict;
use warnings;

use File::Basename;
use Test;

use Bio::EnsEMBL::Test::MultiTestDB;

use constant CONF_FILE => 'MultiTestDB.conf';

BEGIN { plan tests => 1 }

$| = 1;

print("# Starting database and files cleaning up...\n");

my $curr_file = __FILE__;
my $curr_dir  = dirname($curr_file) . "/";
my $conf_file = $curr_dir . CONF_FILE;

if ( $conf_file =~ m#^/# ) {
    # The configuration file is in the current directory.
    $conf_file = "./" . $conf_file;
}

my $db_conf = do $conf_file;

foreach my $species ( keys %{ $db_conf->{'databases'} } ) {
    my $multi = Bio::EnsEMBL::Test::MultiTestDB->new($species);
}

print("# Deleting $curr_file\n");
unlink $curr_file;

ok(1);
