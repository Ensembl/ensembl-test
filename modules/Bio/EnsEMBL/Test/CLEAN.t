use strict;
use warnings;
use File::Basename;
use Bio::EnsEMBL::Test::MultiTestDB;

BEGIN { $| = 1;
	use Test;
	plan tests => 1;
}

my $CONF_FILE = 'MultiTestDB.conf';

print STDERR "\n\nStarting database and files cleaning up....\n";

my $file = __FILE__;
my $curr_dir = dirname($file)."/";    

my $conf_file = $curr_dir . $CONF_FILE;
$conf_file = "./". $conf_file unless ($conf_file =~ /^\//);
my $db_conf = do $conf_file;

foreach my $species (keys %{$db_conf->{'databases'}}) {
    my $multi = Bio::EnsEMBL::Test::MultiTestDB->new($species);
}

unlink $file;

ok( 1 );