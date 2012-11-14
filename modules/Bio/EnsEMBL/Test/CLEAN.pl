use strict;
use warnings;

use File::Basename;
use File::Spec;
use Test::More;

use Bio::EnsEMBL::Test::MultiTestDB;

diag 'Starting database and files cleaning up...';

my $curr_file = __FILE__;
my $db_conf = Bio::EnsEMBL::Test::MultiTestDB->get_db_conf(dirname(__FILE__));

foreach my $species ( keys %{ $db_conf->{'databases'} } ) {
  my $multi = Bio::EnsEMBL::Test::MultiTestDB->new($species);
}

note "Deleting $curr_file";
my $result = unlink $curr_file;
ok($result, 'Unlink of '.$curr_file.' worked');

done_testing();