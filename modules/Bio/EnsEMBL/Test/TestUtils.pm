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
<dev@ensembl.org>

=head1 METHODS

=cut

use strict;
use warnings;

use Exporter;


use Devel::Peek;
use Devel::Cycle;
use Error qw(:try);
use IO::String;
use PadWalker qw/peek_our peek_my/;
use Test::Builder;

use vars qw( @ISA @EXPORT );



@ISA    = qw(Exporter);
@EXPORT = qw(debug test_getter_setter count_rows find_circular_refs capture_std_streams is_rows warns_like mock_object);

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

sub debug {
  Test::Builder->new()->note(@_);
}

=head2 count_rows

  Arg [1]    : Bio::EnsEMBL::DBSQL::DBAdaptor $dba
  Arg [2]    : string $tablename
  Arg [3]    : string $constraint
  Arg [4]    : Array $params
  Example    : count_rows($human_dba, "gene");
  Example    : count_rows($human_dba, "gene", 'where analysis_id=?', 1028);
  Description: Returns the number of rows in the table $tablename
  Returntype : int
  Exceptions : none
  Caller     : test scripts

=cut

sub count_rows
{
    my $db        = shift;
    my $tablename = shift;
    my $constraint = shift;
    my $params     = shift;

    $constraint ||= q{};
    $params     ||= [];
    
    my $sth = $db->dbc->prepare("select count(*) from $tablename $constraint");

    $sth->execute(@{$params});

    my ($count) = $sth->fetchrow_array();

    return $count;
}

=head2 is_rows

  Arg [1]    : int $expected_count
  Arg [2]    : Bio::EnsEMBL::DBSQL::DBAdaptor $dba
  Arg [3]    : string $tablename
  Arg [4]    : string $constraint
  Arg [5]    : Array $params
  Example    : is_rows(20, $human_dba, "gene");
  Example    : is_rows(0, $human_dba, "gene", 'where analysis_id =?', 1025);
  Description: Asserts the count returned is the same as the expected value
  Returntype : None
  Exceptions : None
  Caller     : test scripts

=cut

sub is_rows {
  my ($expected_count, $db, $tablename, $constraint, $params) = @_;
  $constraint ||= q{};
  my $actual_count = count_rows($db, $tablename, $constraint, $params);
  my $joined_params = join(q{, }, @{($params || [] )});
  my $name = sprintf(q{Asserting row count is %d from %s with constraint '%s' with params [%s]}, 
    $expected_count, $tablename, $constraint, $joined_params
  );
  return Test::Builder->new()->is_num($actual_count, $expected_count, $name);
}

=head2 capture_std_streams

  Arg [1]     : CodeRef callback to execute which will attempt to write to STD streams
  Arg [2]     : Boolean 1-dump variables
  Example     : capture_std_streams(sub { 
                 my ($stdout_ref, $stderr_ref) = @_; 
                 print 'hello'; 
                 is(${$stdout_ref}, 'hello', 'STDOUT contains expected';) 
                });
  Description : Provides access to the STDOUT and STDERR streams captured into
                references. This allows you to assert code which writes to
                these streams but offers no way of changing their output
                stream.
  Returntype  : None
  Exceptions  : None
  Caller      : test scripts

=cut

sub capture_std_streams {
  my ($callback) = @_;
  
  my ($stderr_string, $stdout_string) = (q{}, q{});
  
  my $new_stderr = IO::String->new(\$stderr_string);
  my $old_stderr_fh = select(STDERR);
  local *STDERR = $new_stderr;
  
  my $new_stdout = IO::String->new(\$stdout_string);
  my $old_stdout_fh = select(STDOUT);
  local *STDOUT = $new_stdout;
  
  $callback->(\$stdout_string, \$stderr_string);
  
  return;
}

=head2 warns_like

  Arg [1]    : CodeRef code to run; can be a code ref or a block since we can prototype into a code block
  Arg [2]    : Regex regular expression to run against the thrown warnings
  Arg [3]    : String message to print to screen
  Example    : warns_like { do_something(); } qr/^expected warning$/, 'I expect this!';
               warns_like(sub { do_something(); }, qr/^expected$/, 'I expect this!');
  Description: Attempts to run the given code block and then regexs the captured
               warnings raised to SIG{'__WARN__'}. This is done using 
               Test::Builder so we are Test::More compliant. 
  Returntype : None
  Exceptions : none
  Caller     : test scripts

=cut

sub warns_like (&$;$) {
  my ($callback, $regex, $msg) = @_;
  my $warnings;
  local $SIG{'__WARN__'} = sub {
    $warnings .= $_[0];
  };
  $callback->();
  return Test::Builder->new()->like($warnings, $regex, $msg);
}

=head2 mock_object

  Arg [1]    : Object used to mock
  Arg [2]    : Boolean 1-dump variables
  Example    : my $mock = mock_object($obj); $mock->hello(); is($mock->_called('hello'), 1);
  Description: Returns a mock object which counts the number of times a method
               is invoked on itself. This is very useful to use when we want
               to make sure certain methods are & are not called.
  Returntype : Bio::EnsEMBL::Test::TestUtils::MockObject
  Exceptions : none
  Caller     : test scripts

=cut

sub mock_object {
  my ($obj) = @_;
  return Bio::EnsEMBL::Test::TestUtils::MockObject->new($obj);
}

=head2 find_circular_refs

  Arg [1]    : Boolean 1-print cycles
  Arg [2]    : Boolean 1-dump variables
  Example    : my $count = find_circular_refs(1,1);
  Description: Returns the number of variables with circular references. 
               Only variables which are ensembl objects are considered.
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

#See mock_object() for more information about how to use
package Bio::EnsEMBL::Test::TestUtils::MockObject;

use base qw/Bio::EnsEMBL::Utils::Proxy/;

sub __clear {
  my ($self) = @_;
  $self->{__counts} = undef;
}

sub __called {
  my ($self, $method) = @_;
  return $self->{__counts}->{$method} if exists $self->{__counts}->{$method};
  return 0;
}

sub __is_called {
  my ($self, $method, $times, $msg) = @_;
  my $calls = $self->__called($method);
  return Test::Builder->new()->is_num($calls, $times, $msg);
}

sub __resolver {
  my ($invoker, $package, $method) = @_;
  return sub {
    my ($self, @args) = @_;
    my $wantarray = wantarray();
    $self->{__counts}->{$method} = 0 unless $self->{__counts}->{$method}; 
    my @capture = $self->__proxy()->$method(@args);
    $self->{__counts}->{$method}++;
    return @capture if $wantarray;
    return shift @capture;
  };
}

1;
