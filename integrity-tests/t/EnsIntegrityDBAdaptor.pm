#
# EnsEMBL module for EnsIntegrityDBAdaptor
#
# Cared for by Daniel Barker <db2@sanger.ac.uk>
#
# Copyright Daniel Barker
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

EnsIntegrityDBAdaptor - database adaptor for integrity tests

=head1 SYNOPSIS

    # Add test dir to lib search path
    use lib 't';

    use EnsIntegrityDBAdaptor;

    my $db = EnsIntegrityDBAdaptor->new();

Environment variables are required as follows:

    ENS_INTEGRITY_HOST		# Database host
    ENS_INTEGRITY_USER		# Database user
    ENS_INTEGRITY_DBNAME	# Database name

So, for example, the integrity tests may be run from a UNIX
C Shell-like command line as follows:

    cd ensembl-test/integrity-tests
    perl Makefile.PL
    env ENS_INTEGRITY_HOST=kaka.sanger.ac.uk \
        ENS_INTEGRITY_USER=anonymous \
        ENS_INTEGRITY_DBNAME=ensembl110 \
        gmake tests

or from a UNIX Bourne Shell-like command-line as follows:

    cd ensembl-test/integrity-tests
    perl Makefile.PL
    ENS_INTEGRITY_HOST=kaka.sanger.ac.uk \
    ENS_INTEGRITY_USER=anonymous \
    ENS_INTEGRITY_DBNAME=ensembl110 \
    gmake tests

=head1 DESCRIPTION

This module is used by the EnsEMBL integrity-tests test
suite to open the database to be tested. It will throw an
exception if any of the necessary environment variables
is unset.

=head1 CONTACT

Ensembl: ensembl-dev@ebi.ac.uk

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with a _

=cut


# Let the code begin 


package EnsIntegrityDBAdaptor;

use strict;

use Bio::EnsEMBL::DBSQL::DBAdaptor;

use vars qw(@ISA);

@ISA = qw(Bio::EnsEMBL::DBSQL::DBAdaptor Bio::Root::RootI);

sub new {
    my($class) = shift;
    my $self = {};
    bless($self, $class);

    if ($ENV{ENS_INTEGRITY_HOST}
     && $ENV{ENS_INTEGRITY_USER}
     && $ENV{ENS_INTEGRITY_DBNAME})
    {
	$self = new Bio::EnsEMBL::DBSQL::DBAdaptor(
	 -host =>   $ENV{ENS_INTEGRITY_HOST},
	 -user =>   $ENV{ENS_INTEGRITY_USER},
	 -dbname => $ENV{ENS_INTEGRITY_DBNAME});
    }
    else
    {
        $self->throw("environment variables ENS_INTEGRITY_HOST, ENS_INTEGRITY_USER and ENS_INTEGRITY_DBNAME must be set\n");
    }

    bless($self, $class);
    return $self;
}
