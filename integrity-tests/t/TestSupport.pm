# TestSupport.pm       Michael Kirk    2001
#

=head1 TestSupport

Handy functions for regression tests, currently only one:

=cut

package TestSupport;

use lib 't';
use EnsIntegrityDBAdaptor;

=head2 zero_count_test($query, $test_number);

This function is used to run an sql query which tests
the ensembl database as part of the test suite.
The query passed in must be one which returns only a single
count value, where the test is deemed to have passed successfully
if and only if the count value returned is zero.
Depending on the result of the query the standard
"ok <test_number>" or "not ok <test_number>" test message
is output using the passed test_number parameter.

For example:
  zero_test_count("
    SELECT count(*)
    FROM   exon
    WHERE  id = "mary poppins", 1);

=cut

sub zero_count_test {

  my ($query, $test_num) = @_;

  my $db = EnsIntegrityDBAdaptor->new();

  my ($count);

  my $sth = $db->prepare($query);

    $sth->execute();
   
    $sth->bind_columns(undef, \$count);
   
    if ($sth->fetch) {
        if ($count) {
            print "not ok $test_num\n";
        } else {
            print "ok $test_num\n";
        } 
    } else {
        print "not ok $test_num\n";
    }

    $sth->finish();
};

1;
