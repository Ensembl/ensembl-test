package Bio::EnsEMBL::Test::TestUtils;

=head1 NAME

Bio::EnsEMBL::Test::TestUtils - Utilities for testing the EnsEMBL Perl API

=head1 SYNOPSIS

    debug("Testing Bio::EnsEMBL::Slice->foo() method");
    ok( &test_getter_setter( $object, 'foo', 'value' ) );
    count_rows( $human_dba, "gene" );

=head1 DESCRIPTION

This module contains a several utilities for testing the EnsEMBL Perl API.

=head1 EXPORTS

This modules exports the following methods by default:

 - debug
 - test_getter_setter
 - count_rows

=head1 CONTACT

Email questions to the ensembl developer mailing list
<ensembl-dev@ebi.ac.uk>

=head1 METHODS

=cut

use strict;
use warnings;

use Exporter;

use vars qw( @ISA @EXPORT );

@ISA    = qw(Exporter);
@EXPORT = qw(debug test_getter_setter count_rows);

=head2 test_getter_setter

  Arg [1]    : Object $object
               The object to test the getter setter on
  Arg [2]    : string $method
               The name of the getter setter method to test
  Arg [3]    : $test_val
               The value to use to test the set behavior of the method.
  Example    : ok(&TestUtils::test_getter_setter($object, 'type', 'value'));
  Description: Tests a getter setter method by attempting to set a value
               and verifying that the newly set value can be retrieved.
               The old value of the the attribute is restored after the
               test (providing the method functions correctly).
  Returntype : boolean - true value on success, false on failure
  Exceptions : none
  Caller     : test scripts

=cut

sub test_getter_setter
{
    my ( $object, $method, $test_val ) = @_;

    my $ret_val = 0;

    # Save the old value
    my $old_val = $object->$method();

    $object->$method($test_val);

    # Verify value was set
    $ret_val =
      (      ( !defined($test_val) && !defined( $object->$method() ) )
          || ( $object->$method() eq $test_val ) );

    # Restore the old value
    $object->$method($old_val);

    return $ret_val;
}

=head2 debug

  Arg [...]  : array of strings to be printed
  Example    : debug("Testing Bio::EnsEMBL::Slice->foo() method")
  Description: Prints a debug message on the standard error console
               if the verbosity has not been swithed off
  Returntype : none
  Exceptions : none
  Caller     : test scripts

=cut

sub debug
{
    if ($::verbose) {
        print STDERR @_, "\n";
    }
}

=head2 count_rows

  Arg [1]    : Bio::EnsEMBL::DBSQL::DBAdaptor $dba
  Arg [2]    : string $tablename
  Example    : count_rows($human_dba, "gene");
  Description: Returns the number of rows in the table $tablename
  Returntype : int
  Exceptions : none
  Caller     : test scripts

=cut

sub count_rows
{
    my $db        = shift;
    my $tablename = shift;

    my $sth = $db->dbc->prepare("select count(*) from $tablename");

    $sth->execute();

    my ($count) = $sth->fetchrow_array();

    return $count;
}

1;
