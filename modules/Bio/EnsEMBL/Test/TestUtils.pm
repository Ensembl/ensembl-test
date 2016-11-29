=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

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
<http://lists.ensembl.org/mailman/listinfo/dev>

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
use Test::Builder::Module;
use Bio::EnsEMBL::Utils::IO qw/gz_work_with_file work_with_file/;

use vars qw( @ISA @EXPORT );

@ISA = qw(Exporter Test::Builder::Module);
@EXPORT = qw(
  debug 
  test_getter_setter 
  count_rows 
  find_circular_refs 
  capture_std_streams 
  is_rows 
  warns_like 
  mock_object 
  ok_directory_contents 
  is_file_line_count
  compare_file_line
  has_apache2_licence
  all_has_apache2_licence
  all_source_code
);

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
  Bio::EnsEMBL::Test::TestUtils->builder->note(@_);
}

=head2 count_rows

  Arg [1]    : Bio::EnsEMBL::DBSQL::DBAdaptor $dba
  Arg [2]    : string $tablename
  Arg [3]    : string $constraint
  Arg [4]    : Array $params
  Example    : count_rows($human_dba, "gene");
  Example    : count_rows($human_dba, "gene", 'where analysis_id=?', [1028]);
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
  Example    : is_rows(0, $human_dba, "gene", 'where analysis_id =?', [1025]);
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
  return __PACKAGE__->builder->is_num($actual_count, $expected_count, $name);
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
  return __PACKAGE__->builder()->like($warnings, $regex, $msg);
}

=head2 ok_directory_contents

  Arg [1]    : String directory to search for files in
  Arg [2]    : ArrayRef filenames to look for
  Arg [3]    : String message to print 
  Example    : ok_directory_contents('/etc', 'hosts', '/etc/hosts is there');
  Description: 
  Returntype : Boolean declares if the test was a success
  Exceptions : none
  Caller     : test scripts

=cut

sub ok_directory_contents ($$;$) {
  my ($dir, $files, $msg) = @_;
  my $result;
  my @missing;
  foreach my $file (@{$files}) {
    my $full_path = File::Spec->catfile($dir, $file);
    if(! -e $full_path || ! -s $full_path) {
      push(@missing, $file);
    }
  }
  my $builder = __PACKAGE__->builder();
  if(@missing) {
    $result = $builder->ok(0, $msg);
    $builder->diag("Directory '$dir' is missing the following files");
    my $missing_msg = join(q{, }, @missing);
    $builder->diag(sprintf('[%s]', $missing_msg));
  }
  else {
    $result = $builder->ok(1, $msg);
  }
  return $result;
}

=head2 compare_file_line

  Arg [1]    : String file to test. Can be a gzipped file or uncompressed
  Arg [2]    : Line number to test
  Arg [3]    : String, the expected line
  Arg [3]    : String optional message to print to screen
  Example    : compare_file_line('/etc/hosts', 5, 'On the fifth line it said', 'The line is as expected');
  Description: Opens the given file (can be gzipped or not) and compares a given line number 
               with an expected string
  Returntype : Boolean Declares if the test succeeeded or not
  Exceptions : none
  Caller     : test scripts

=cut

sub compare_file_line ($$;$;$;$) {
  my ($file, $line_number, $expected_line, $msg) = @_;
  my $builder = __PACKAGE__->builder();
  if(! -e $file) {
    my $r = $builder->ok(0, $msg);
    $builder->diag("$file does not exist");
    return $r;
  }

  my $result_line;
  my $sub_line = sub {
    my ($fh, $line) = @_;
    my $count = 0;
    while(my $line = <$fh>) {
      chomp $line;
      $count++;
      if ($count == $line_number) {
        $result_line = $line;
        last;
      }
    }
    return;
  };

  if($file =~ /.gz$/) {
    gz_work_with_file($file, 'r', $sub_line);
  }
  else {
    work_with_file($file, 'r', $sub_line);
  }

  return $builder->cmp_ok($result_line, 'eq', $expected_line, $msg);
}

=head2 is_file_line_count

  Arg [1]    : String file to test. Can be a gzipped file or uncompressed
  Arg [2]    : Integer the number of expected rows
  Arg [3]    : String optional message to print to screen
  Arg [4]    : Pattern for matching lines
  Example    : is_file_line_count('/etc/hosts', 10, 'We have 10 entries in /etc/hosts');
  Description: Opens the given file (can be gzipped or not) and counts the number of
               lines by simple line iteration
  Returntype : Boolean Declares if the test succeeeded or not
  Exceptions : none
  Caller     : test scripts

=cut

sub is_file_line_count ($$;$;$) {
  my ($file, $expected_count, $msg, $pattern) = @_;
  my $builder = __PACKAGE__->builder();
  if(! -e $file) {
    my $r = $builder->ok(0, $msg);
    $builder->diag("$file does not exist");
    return $r;
  }

  my $count = 0;
  my $sub_counter = sub {
    my ($fh) = @_;
    while(my $line = <$fh>) {
      if ($pattern && $line !~ /$pattern/) { next; }
      $count++;
    }
    return;
  };

  if($file =~ /.gz$/) {
    gz_work_with_file($file, 'r', $sub_counter);
  }
  else {
    work_with_file($file, 'r', $sub_counter); 
  }

  return $builder->cmp_ok($count, '==', $expected_count, $msg);
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

=head2 all_has_apache2_licence

  Arg [n]    : Directories to scan. Defaults to blib, t, modules, lib and sql 
               should they exist (remember relative locations matter if you give them)
  Example    : my @files = all_has_apache2_licence();
               my @files = all_has_apache2_licence('../lib/t');
  Description: Scans the given directories and returns all found instances of
               source code. This includes Perl (pl,pm,t), Java(java), C(c,h) and 
               SQL (sql) suffixed files. It then looks for the Apache licence 2.0 
               declaration in the top of the file (30 lines leway given).

               Should you not need it to scan a directory then put a no critic 
               declaration at the top. This will prevent the code from scanning and
               mis-marking the file. The scanner directive is (American spelling also supported)
                  no critic (RequireApache2Licence) 
  Returntype : Boolean indicating if all given directories has source code 
               with the expected licence

=cut

sub all_has_apache2_licence {
  my @files = all_source_code(@_);
  my $ok = 1;
  foreach my $file (@files) {
    $ok = 0 if ! has_apache2_licence($file);
  }
  return $ok;
}

=head2 has_apache2_licence

  Arg [1]    : File path to the file to test
  Example    : has_apache2_licence('/my/file.pm');
  Description: Asserts if we can find the short version of the Apache v2.0
               licence within the first 30 lines of the given file. You can
               skip the test with a C<no critic (RequireApache2Licence)> tag. We
               also support the American spelling of this.
  Returntype : None
  Exceptions : None

=cut

sub has_apache2_licence {
  my ($file) = @_;
  my $count = 0;
  my $max_lines = 30;
  my ($found_copyright, $found_url, $found_warranties, $skip_test) = (0,0,0,0);
  open my $fh, '<', $file or die "Cannot open $file: $!";
  while(my $line = <$fh>) {
    last if $count >= $max_lines;
    if($line =~ /no critic \(RequireApache2Licen(c|s)e\)/) {
      $skip_test = 1;
      last;
    }
    $found_copyright = 1 if $line =~ /Apache License, Version 2\.0/;
    $found_url = 1 if $line =~ /www.apache.org.+LICENSE-2.0/;
    $found_warranties = 1 if $line =~ /WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND/;
    $count++;
  }
  close $fh;
  if($skip_test) {
    return __PACKAGE__->builder->ok(1, "$file has a no critic (RequireApache2Licence) directive");
  }
  if($found_copyright && $found_url && $found_warranties) {
    return __PACKAGE__->builder->ok(1, "$file has a Apache v2.0 licence declaration");
  }
  __PACKAGE__->builder->diag("$file is missing Apache v2.0 declaration");
  __PACKAGE__->builder->diag("$file is missing Apache URL");
  __PACKAGE__->builder->diag("$file is missing Apache v2.0 warranties");
  return __PACKAGE__->builder->ok(0, "$file does not have an Apache v2.0 licence declaration in the first $max_lines lines");
}

=head2 all_source_code

  Arg [n]    : Directories to scan. Defaults to blib, t, modules, lib and sql 
               should they exist (remember relative locations matter if you give them)
  Example    : my @files = all_source_code();
               my @files = all_source_code('lib/t');
  Description: Scans the given directories and returns all found instances of
               source code. This includes Perl (pl,pm,t), Java(java), C(c,h) and 
               SQL (sql) suffixed files.
  Returntype : Array of all found files

=cut

sub all_source_code {
  my @starting_dirs = @_ ? @_ : _starting_dirs();
  my @files;
  my @dirs = @starting_dirs;
  while ( my $file = shift @dirs ) {
    if ( -d $file ) {
      opendir my $dir, $file or next;
      my @new_files = 
        grep { $_ ne 'CVS' && $_ ne '.svn' && $_ ne '.git' && $_ !~ /^\./ } 
        File::Spec->no_upwards(readdir $dir);
      closedir $dir;
      push(@dirs, map {File::Spec->catfile($file, $_)} @new_files);
    }
    if ( -f $file ) {
      next unless $file =~ /(?-xism:\.(?:[cht]|p[lm]|java|sql))/;
      push(@files, $file);
    }
  } # while
  return @files;
}

sub _starting_dirs {
  my @dirs;
  push(@dirs, grep { -e $_ } qw/blib lib sql t modules/);
  return @dirs;
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
  return Bio::EnsEMBL::Test::TestUtils->builder()->is_num($calls, $times, $msg);
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
