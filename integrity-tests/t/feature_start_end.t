# feature_start_end.t      Daniel Barker    2001
#

=head1 feature_start_end

This test is intended as a check that no feature has an "end" prior to
its "start" (I think). It is based on the following email message,
relating to a pre-release version of Ensembl 120:

    *** MESSAGE BEGINS ***

    Date: Thu, 8 Nov 2001 15:31:48 +0000 (GMT)
    From: Tony Cox <avc@sanger.ac.uk>
    To: ensembl-admin@ebi.ac.uk
    Subject: Just for information: (fwd)




    mysql> select distinct name, analysis from feature where seq_end < seq_start;   
    +-----------+----------+
    | name      | analysis |
    +-----------+----------+
    | wublastp  |       10 |
    | wutblastn |       11 |
    | wutblastn |        7 |
    | wutblastn |       12 |
    +-----------+----------+
    4 rows in set (7 min 12.83 sec)

    *** MESSAGE ENDS ***

=cut


## We start with some black magic to print on failure.
BEGIN { $| = 1; print "1..2\n"; 
	use vars qw($loaded); }
END {print "not ok 1\n" unless $loaded;}

use strict;
use lib 't';
use TestSupport;
$loaded = 1;
print "ok 1\n";		# 1st test passes.

TestSupport::zero_count_test("select count(*) from feature where seq_end < seq_start", 2);
