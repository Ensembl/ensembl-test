#!/usr/local/ensembl/bin/perl -w

use strict;
use warnings;
use File::Basename;

use Getopt::Long;
use Test::Harness;

my ($opt_l, $opt_h, $opt_c);

GetOptions('l' => \$opt_l,
           'h' => \$opt_h,
	   'c' => \$opt_c);


#print usage on '-h' command line option
if($opt_h) {
  &usage;
  exit;
}

#list test files on '-l' command line option
if($opt_l) {
   foreach my $file (grep {!/CLEAN\.t/} @{get_all_tests(\@ARGV)}) {
    print "$file\n";
  }
  exit;
}

#set environment var
$ENV{'RUNTESTS_HARNESS'} = 1;

#make sure proper cleanup is done if the user interrupts the tests
$SIG{HUP} = $SIG{KILL} = $SIG{INT} = 
  sub {warn "\n\nINTERRUPT SIGNAL RECEIVED\n\n"; &clean;};

#run all specified tests
eval {
  runtests(grep {!/CLEAN\.t/} @{&get_all_tests(\@ARGV)});
};

&clean(\@ARGV);

sub clean {
  #unset env var indicating final cleanup should be performed
  delete $ENV{"RUNTESTS_HARNESS"};
  if ($opt_c) {
    my @arguments;
    my %already_seen;
    foreach my $file (@ARGV) {
      if (-d $file) {
        push @arguments, $file;
      }
      my $dir = dirname($file);
      next if ($already_seen{$dir});
      push @arguments, $dir;
      $already_seen{$dir} = 1;
    }
    eval {
      runtests(grep {/CLEAN\.t/} @{&get_all_tests(\@arguments)});
    };
  }

  exit;
}

=head2 get_all_tests

  Arg [21]    :(optional) listref $input_files_or_directories
               testfiles or directories to retrieve. If not specified all 
               "./" direcroty is the default.
  Example    : @test_files = read_test_dir('t');
  Description: Returns a list of testfiles in the directories specified by
               the @tests argument.  The relative path is given as well as
               with the testnames returned.  Only files ending with .t are
               returned.  Subdirectories are recursively entered and the test
               files returned within them are returned as well.
  Returntype : listref of strings.
  Exceptions : none
  Caller     : general

=cut

sub get_all_tests {
  my ($input_files_directories) = @_;
  
  my @files;
  my @out = ();
  my $dir = "";

  if($input_files_directories && @$input_files_directories) {
    #input files were specified so use them
    @files = @$input_files_directories
  } else {
    #otherwise use every file in the directory
    $dir = "./t/";
    unless(opendir(DIR, "./t/")) {
      warn("WARNING: cannot open directory ./t\n");
      return [];
    }
    @files = readdir DIR;
    close DIR;
  }

  #filter out CVS files and ./ and ../
  @files = grep !/(^\.\.?$)|(^CVS$)/, @files;

  foreach my $file (@files) {

    if(-d $file) {
      #do a recursive call on directories
      $file =~ s/\/$//;
      my @more_files;

      unless(opendir(DIR, $file)) {
        warn("WARNING: cannot open directory $file\n");
        return [];
      }
      @more_files = map {"$file/$_"} grep { !/(^\.)|(^CVS$)|(~$)/ } readdir DIR;
      close DIR;

      push @out, @{get_all_tests(\@more_files)};

    } elsif ($file =~ /\.t$/) {
      #files ending with a '.t' are considered test files
      # filter out files ending in ~
      next if ($file =~ /~$/);
      $file = $dir . $file;

      unless(-r $file && -f $file) {
	warn("WARNING: cannot read test file $file\n");
      }

      push @out, $file;
    } 
  }

  return \@out;
}

sub usage {
  print "usage:\n";
  print "\tlist tests:             run_tests.pl -l [<testfiles or dirs> ...]\n";
  print "\trun tests:              run_tests.pl [<testfiles or dirs> ...]\n";
  print "\trun tests and clean up: run_tests.pl -c [<testfiles or dirs> ...]\n";
}
