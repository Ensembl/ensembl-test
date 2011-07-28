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
 - find_circular_refs
 - dump_vars

=head1 CONTACT

Email questions to the ensembl developer mailing list
<ensembl-dev@ebi.ac.uk>

=head1 METHODS

=cut

use strict;
use warnings;

use Exporter;


use Devel::Peek;
use Devel::Cycle;
use Error qw(:try);

use PadWalker qw/peek_our peek_my/;

use vars qw( @ISA @EXPORT );



@ISA    = qw(Exporter);
@EXPORT = qw(debug test_getter_setter count_rows find_circular_refs);

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

=head2 find_circular_refs

  Arg [1]    : Boolean 1-print cycles
  Arg [2]    : Boolean 1-dump variables
  Example    : find_circular_refs();
  Description: Returns the number of variables with circular references. 
               Only my variables which are ensembl objects are considered.
               The sub will go through variables which are in scope at the point it was called. 
  Returntype : int
  Exceptions : none
  Caller     : test scripts

=cut

my %ensembl_objects = ();
my $cycle_found;
my $print_cycles;

sub find_circular_refs { 
 
    $print_cycles = shift;
    my $dump_vars = shift;
    my $message;
    my $lexical  = peek_my(1);
 
    while (my ($var, $ref) = each %$lexical) {
	my $dref = $ref;
    	while (ref($dref) eq "REF") {
	    $dref = $$dref;
	}
	if ( ref($dref) =~ /Bio\:\:EnsEMBL/ and !defined($ensembl_objects{$var.ref($dref)}) )  { 
	    $ensembl_objects{$var.ref($dref)} = 0;	    
	    $message = $var ." ". ref($dref);
	    _get_cycles($var,$dref,$message, $dump_vars);
 	} 
	if (ref($dref) eq "HASH") {
		my %dref_hash = %$dref;
		my $value_count = 0;
		foreach my $key (keys %dref_hash) {
		    $value_count ++;
		    if (ref($dref_hash{$key}) =~ /Bio\:\:EnsEMBL/ and !defined($ensembl_objects{$var.$value_count.ref($dref_hash{$key})} ) ) {	
			$ensembl_objects{$var.$value_count.ref($dref_hash{$key})} = 0;			
			$message = $var . " HASH value ".$value_count." ". ref($dref_hash{$key});
			_get_cycles($var,$dref_hash{$key},$message,$dump_vars,$key);		
		    }
		}
	}
	if (ref($dref) eq "ARRAY") {
	    #for an array check the first element only
	    my @dref_array = @$dref;
	  
	       if (ref($dref_array[0]) =~ /Bio\:\:EnsEMBL/ and  !defined($ensembl_objects{$var."0".ref($dref_array[0])}) ) {	
		   $ensembl_objects{$var."0".ref($dref_array[0])} = 0;
		   $message = $var ." ARRAY element 0 ". ref($dref_array[0]);
		   _get_cycles($var,$dref_array[0],$message,$dump_vars,undef,0);		
	       }
		    		
	}
	
    }
    my $circular_count = 0;
    foreach my $value (values %ensembl_objects) {
	$circular_count += $value;
    }
    return $circular_count;
}

sub _get_cycles {
    
    my $var = shift;
    my $dref = shift;
    my $message = shift;
    my $dump_vars = shift;
    my $hash_key = shift;
    my $array_element = shift;

    $cycle_found = 0; 
    if ($print_cycles) {
	find_cycle($dref);
	find_cycle($dref, \&_count_cycles);	
    }
    else {
    #use try/catch to return after 1st cycle is found if we're not printing cycles
	try {
	    find_cycle($dref, \&_count_cycles);
	}
	catch Error::Simple with {
	    
	};
    }
    
    if ($cycle_found) {

	my $key = "";
	if ($hash_key) {
	    $key = $var.$hash_key;
	}
	elsif (defined $array_element) {
	    $key = $var.$array_element;
	}
	$ensembl_objects{$key.ref($dref)} += 1;
	print "circular reference found in ".$message."\n";
	if ($dump_vars) {
	    Dump($dref);
	}
    }
}

sub _count_cycles {
   if (!$print_cycles && $cycle_found) {
       throw Error::Simple;
   }
   my $cycle_array_ref = shift;
   my @cycle_array = @$cycle_array_ref;
   if (scalar(@cycle_array) > 0) {
	$cycle_found = 1;
   }  
}


1;
