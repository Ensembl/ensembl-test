#!/usr/local/bin/perl

# Copyright EMBL-EBI 2001
# Author: Alistair Rust
# Creation: 04.10.2001
# Last modified:

=head1 NAME
  
  rawpipelineDBCompare.pl

=head1 SYNPOSIS

  This script performs a comparison of a database generated from
  a "reference" run of the raw pipeline against a current run to verify 
  the functonality of the code.  Therefore, the script must be pointed 
  at 2 databases; one with the reference data records and one with the 
  new data records.

  A separate file may be created (testgenomeConf.pl) to store the 
  relevant parameters to make the connections to the 2 databases.  These 
  database options can however be overridden by entering them via the 
  command line.

  The options are:
   -ref_host
   -ref_dbname
   -ref_port
   -ref_dbclient
   -ref_dbuser
   -ref_dbpass
   -new_host
   -new_dbname
   -new_port
   -new_dbclient
   -new_dbuser
   -new_dbpass
   -detailed
  
  where ref is the reference db and new the newly generated db. The 
  -detailed switch simply toggles the amount of messages sent to STDERR.

  The current checks are performed on the feature and repeat_feature
  databases.  The comparisons are intended to be hierarchical, 
  beginning with simple checks on the size of the databases, descending 
  down to fine grain checks of individual hids and coordinates.

=cut
 
use strict;
use DBI;
use Getopt::Long;

require "testgenomeConf.pl";  # info on database connections


# database connection stuff

my $ref_host = $::testgenomeConf{'ref_host'};
my $ref_dbname = $::testgenomeConf{'ref_dbname'};
my $ref_port = $::testgenomeConf{'ref_port'};
my $ref_dbclient = $::testgenomeConf{'ref_dbclient'};
my $ref_dbuser = $::testgenomeConf{'ref_dbuser'};
my $ref_dbpass = $::testgenomeConf{'ref_dbpass'};

my $new_host = $::testgenomeConf{'new_host'};
my $new_dbname = $::testgenomeConf{'new_dbname'};
my $new_port = $::testgenomeConf{'new_port'};
my $new_dbclient = $::testgenomeConf{'new_dbclient'};
my $new_dbuser = $::testgenomeConf{'new_dbuser'};
my $new_dbpass = $::testgenomeConf{'new_dbpass'};

my $verbage = 0;

GetOptions(
   'ref_host=s'     => \$ref_host,
   'ref_dbname=s'   => \$ref_dbname,
   'ref_port=i'     => \$ref_port,
   'ref_dbclient=s' => \$ref_dbclient,
   'ref_dbuser=s'   => \$ref_dbuser,
   'ref_dbpass=s'   => \$ref_dbpass,
   'new_host=s'     => \$new_host,
   'new_dbname=s'   => \$new_dbname,
   'new_port=i'     => \$new_port,
   'new_dbclient=s' => \$new_dbclient,
   'new_dbuser=s'   => \$new_dbuser,
   'new_dbpass=s'   => \$new_dbpass,
   'detailed'       => \$verbage
)
or die ("Couldn't get options.");

my $dsn = "DBI:$ref_dbclient:database=$ref_dbname;host=$ref_host;port=$ref_port";
my $dsn2 = "DBI:$new_dbclient:database=$new_dbname;host=$new_host;port=$new_port";
 
 
my $dbh_ref = DBI->connect($dsn, $ref_dbuser, $ref_dbpass)
                                   or die "Couldn't connect to database: " . DBI->errstr;

my $dbh_new = DBI->connect($dsn2, $new_dbuser, $new_dbpass)
                                   or die "Couldn't connect to database: " . DBI->errstr;


# time to get the data from the dbs
# records are stored as:
# analysis : contig : hid : seq_start : seq_end : hstart : hend

# load an array with the ref features
my @temp_ref = ();
@temp_ref = get_features( $dbh_ref );


# load an aray with the new featuers
my @temp_new = ();
@temp_new = get_features( $dbh_new );


# Now sort the feature arrays by analysis primarily,
# though I'm not sure that this is necessary as records are
# stored in order in the databases but anyway...

my @ref_features = sort order @temp_ref;
my @new_features = sort order @temp_new;


# get the repeat features from the reference repeat_feature table
my @ref_repeats = get_repeat_features( 1, $dbh_ref );

# get the repeat features from the new repeat_feature table
my @new_repeats = get_repeat_features( 1, $dbh_new );



# check the number of feature entries for each unique analysis
# and each unique contig

my %ref_analyses = ();
my %new_analyses = ();
my %ref_fcontigs = ();
my %new_fcontigs = ();

my $i;
for $i ( 0 .. $#ref_features ) {
  $ref_analyses{$ref_features[$i][0]}++;
  $ref_fcontigs{$ref_features[$i][1]}++;
}

for $i ( 0 .. $#new_features ) {
  $new_analyses{$new_features[$i][0]}++;
  $new_fcontigs{$new_features[$i][1]}++;
}


# Time to do some comparisons
print STDERR "\n[FEATURE] Table Comparisons\n";


# Comparison 1
# Are the feature tables the same size?

print STDERR "\n[FEATURE] Comparison#1: Size of feature tables\n";

if ( $#new_features == $#ref_features ) {
  if ( $verbage ) {
    print STDERR "PASS: Same number of features [$#new_features]\n";
  }
  else {
    print STDERR "PASS\n";
  }
}
else {
  print STDERR "FAIL: Number of new pipeline features DOES NOT EQUAL reference features.\n";
  print STDERR "Number of new pipeline features: $#new_features \n";
  print STDERR "Number of reference features: $#ref_features \n"; 
}


# Comparison #2
# Are the number of analyses the same?

print STDERR "\n[FEATURE] Comparison#2: Number of analyses performed\n";

my @num_ref_analyses = keys(%ref_analyses);
my @num_new_analyses = keys(%new_analyses);

if ( $#num_ref_analyses == $#num_new_analyses ) {
  if ( $verbage ) {
    print STDERR "PASS: Same number of analyses: [$#num_ref_analyses]\n";
  }
  else {
    print STDERR "PASS\n";
  }
}
else {
  print STDERR "FAIL: Number of analyses in new pipeline db DOES NOT EQUAL number of analyses in reference db.\n";
  print STDERR "Number of new pipeline analyses: $#num_ref_analyses \n";
  print STDERR "Number of reference analyses: $#num_new_analyses \n"; 
}


# Comparison #3
# Are the number of individual analyses the same?

print STDERR "\n[FEATURE] Comparison#3: Number of separate analyses performed\n";

my $fail = 0;
foreach my $analyses ( keys %ref_analyses ) {
  if ( exists $new_analyses{$analyses} ) {
    if ( $ref_analyses{$analyses} != $new_analyses{$analyses} ) {
      print STDERR "Mismatch in analyses for analysis $analyses - Ref db: $ref_analyses{$analyses} New db: $new_analyses{$analyses}\n";
      $fail++;
    }
    else {
      if ( $verbage ) {
	print STDERR "Analysis $analyses: Ref $ref_analyses{$analyses} matches new $new_analyses{$analyses}\n";
      }
    }
  }
  else {
    print STDERR "Analysis $analyses DOES NOT exist in new pipeline db \n";
    $fail++;
  }
}

if ( $fail ) {
  print STDERR "\nFAIL: $fail errors when comparing the number of individual analysis records\n"
}
else {
  print STDERR "PASS\n";
}


# Comparison #4
# Are the number of contigs analysed the same?

print STDERR "\n[FEATURE] Comparison#4: Number of contigs analysed\n";

my @num_ref_contigs = keys(%ref_fcontigs);
my @num_new_contigs = keys(%new_fcontigs);

if ( $#num_ref_contigs == $#num_new_contigs ) {
  if ( $verbage ) {
    print STDERR "PASS: Same number of contigs analysed [$#num_ref_contigs]\n";
  }
  else {
    print STDERR "PASS\n";
  }
}
else {
  print STDERR "FAIL: Number of contigs analysed in new pipeline DOES NOT EQUAL number of contigs analysed in reference db.\n";
  print STDERR "Number of new contigs analysed: $#num_ref_contigs \n";
  print STDERR "Number of reference contigs analysed: $#num_new_contigs \n"; 
}


# Comparison #5
# Are the number of individual contig analyses the same?

print STDERR "\n[FEATURE] Comparison#5: Number of analyses performed per contig\n";

$fail = 0;
foreach my $fcontig ( keys %ref_fcontigs ) {
  if ( exists $new_fcontigs{$fcontig} ) {
    if ( $ref_fcontigs{$fcontig} != $new_fcontigs{$fcontig} ) {
      print STDERR "Mismatch in contigs for contig $fcontig: $ref_fcontigs{$fcontig}\n";
      $fail++;
    }
    if ( $verbage ) {
      print STDERR "Contig $fcontig: Ref $ref_fcontigs{$fcontig} matches new $new_fcontigs{$fcontig}\n";
    }
  }
  else { # no record of the current contig in the new db
    print STDERR "Contig $fcontig does not exist in new pipeline db \n";
    $fail++;
  }
}

if ( $fail ) {
  print STDERR "FAIL: $fail errors in feature table when comparing contig records\n"
}
else {
  print STDERR "PASS\n";
}


# Comparison #6
# Are the number of contigs analysed the same?

print STDERR "\n[FEATURE] Comparison#6: Entry-for-entry check for contig records\n";
print STDERR "                        Includes hid and coordinate skew checks.\n";

my $pass = 0;
my $total = 0;
my $new_index = 0;

$i = 0;
$fail = 0;

my $curr_contig = -1;
my $curr_analysis = -1;
my $found_new_record = 0;

while ( $i < $#ref_features ) {

  # check to see whether we have now jumped to a new analysis and/or a 
  # new contig.  In theory I should only need check to see whether the
  # contig has changed as the records are stored in order of analysis id.
  # But checking by contig alone does not work for (test) data sets
  # where only 1 contig is pushed through the pipeline.

  if ( $ref_features[$i][1] != $curr_contig ||
       $ref_features[$i][0] != $curr_analysis ) {

    # if we're onto a new analysis grab the new id
    if ( $curr_analysis != $ref_features[$i][0]) {
      $curr_analysis = $ref_features[$i][0];
    }

    $curr_contig = $ref_features[$i][1];

    # Chunking through the array DOES however assume that the once the
    # matching record is found the subsequent ones ARE stored in order.

    $found_new_record = 0;
    for my $j ( 0 .. $#new_features ) {
      if ( $new_features[$j][0] == $curr_analysis && 
	   $new_features[$j][1] == $curr_contig ) {

	  $new_index = $j;
	  $found_new_record = 1;
	  last;
	}
    }
  }

  if ( $found_new_record ) {
    # check the individual records

    my $match = compare_records( \@{$ref_features[$i]}, \@{$new_features[$new_index]} );

    $total++;
    if ( $match ) {
      $pass++;
    }
    else {
      $fail++;

      if ( $verbage ) {
	print STDERR "Record match failed for $curr_contig:\n";
	print STDERR "Ref: $ref_features[$i][0] : $ref_features[$i][1] : $ref_features[$i][2] : $ref_features[$i][3] : $ref_features[$i][4] : $ref_features[$i][5] : $ref_features[$i][6]\n";
	print STDERR "New: $new_features[$new_index][0] : $new_features[$new_index][1] : $new_features[$new_index][2] : $new_features[$new_index][3] : $new_features[$new_index][4] : $new_features[$new_index][5] : $new_features[$new_index][6]\n";
	print STDERR "\n";
      }
    }

    $i++;          # jump to the next records in the array
    $new_index++;

  }
  else {  # skip over the ref repeat records cos we couldn't find a 
          # matching record in the new db, summing the fails as we go
    while ( $curr_analysis == $ref_features[$i][0] && 
	    $curr_contig == $ref_features[$i][1] && 
	    $i < $#ref_features ) {
      $fail++;
      $total++;
      $i++;

      if ( $verbage ) {
	print STDERR "Failed to find a record match for $curr_contig in the new pipeline db\n";
      }
    }
  }
}

if ( $fail == 0 ) {
  if ( $verbage ) {
    print STDERR "PASS: All $total new contig records found and correctly match the reference db\n";
  }
  else {
    print STDERR "PASS\n";
  }
}
else {
  print STDERR "FAIL: Pass: $pass  Fail: $fail  Total: $total\n";
}


# Repeat table comparisons
print STDERR "\n\n[REPEAT] Table Comparisons\n\n";

# Comparison #7
print STDERR "[REPEAT] Comparison#7: Size of repeat_feature tables\n";

if ( $#ref_repeats == $#new_repeats ) {
  if ( $verbage ) {
    my $reps = $#ref_repeats + 1;
    print STDERR "PASS: Same number of repeat features [" . $reps . "]\n";
  }
  else {
    print STDERR "PASS\n";
  }
}
else {
    print STDERR "FAIL: Different number of repeat_features\n";
    print STDERR "Number of new db repeat features: $#new_repeats \n";
    print STDERR "Number of ref db repeat features: $#ref_repeats \n";
}


# Comparison #8
print STDERR "\n[REPEAT] Comparison#8: Number of contig records in repeat_feature table\n";

# check the number of records for each contig

my %unique_ref_rep_contigs;
my %unique_new_rep_contigs;

for my $i ( 0 .. $#ref_repeats ) {
  $unique_ref_rep_contigs{$ref_repeats[$i][0]}++;
}

for my $i ( 0 .. $#new_repeats ) {
  $unique_new_rep_contigs{$new_repeats[$i][0]}++;
}


$fail = 0;
foreach my $contig ( keys %unique_ref_rep_contigs ) {
  if ( exists $unique_new_rep_contigs{$contig} ) {
    if ( $unique_new_rep_contigs{$contig} != $unique_ref_rep_contigs{$contig} ) {
      print STDERR "Mismatch in repeats for contig $contig: $unique_ref_rep_contigs{$contig}\n";
      $fail++;
    }
  }
  else {   # the unique_new_rep_contig doesn't exist in the new pipeline
    print STDERR "Contig $contig DOES NOT exist in new pipeline db \n";
    $fail++;
  }
}

if ( $fail ) {
  print STDERR "\nFAIL: $fail errors in repeat feature table when comparing contig records\n"
}
else {
  print STDERR "PASS\n";
}


# Comparison #9
print STDERR "\n[REPEAT] Comparison#9: Entry-for-entry check for contig records\n";
print STDERR "                       Includes hid and coordinate skew checks.\n";

$pass = 0;
$total = 0;
$new_index = 0;

$i = 0;
$fail = 0;

$curr_contig = -1;
$found_new_record = 0;

while ( $i < $#ref_repeats ) {

  if ( $ref_repeats[$i][1] != $curr_contig ) {
    $curr_contig = $ref_repeats[$i][1];

    # Scan the new repeats array for a matching contig record.
    # If the arrays are equivalent then the indexes should be the same
    # but let's assume just in case that the records aren't at the 
    # same place, so scan the array for the first matching record.
    # Chunking through the array DOES however assume that the once the
    # matching record is found the subsequent ones ARE stored in order.

    # For the repeats don't check the analysis id because it should
    # always be set to 1.

    $found_new_record = 0;
    for my $j ( 0 .. $#new_repeats ) {
      next if ( $new_repeats[$j][1] != $curr_contig );

      $new_index = $j;
      $found_new_record = 1;
      last;
    }
  }

  if ( $found_new_record ) {
    # check the individual records
    my $match = compare_records( \@{$ref_repeats[$i]}, \@{$new_repeats[$new_index]} );

    $total++;
    if ( $match ) {
      $pass++;
    }
    else {
      $fail++;

      if ( $verbage ) {
	print STDERR "Record match failed for $curr_contig:\n";
	print STDERR "Ref: $ref_repeats[$i][0] : $ref_repeats[$i][1] : $ref_repeats[$i][2] : $ref_repeats[$i][3] : $ref_repeats[$i][4] : $ref_repeats[$i][5] : $ref_repeats[$i][6]\n";
	print STDERR "New: $new_repeats[$new_index][0] : $new_repeats[$new_index][1] : $new_repeats[$new_index][2] : $new_repeats[$new_index][3] : $new_repeats[$new_index][4] : $new_repeats[$new_index][5] : $new_repeats[$new_index][6]\n";
	print STDERR "\n";
      }
    }

    $i++;   # jump to the next records in the array
    $new_index++;

  }
  else {  # skip over the ref repeat records cos we couldn't find a 
          # matching record in the new db, summing the fails as we go

    while ( $curr_contig == $ref_repeats[$i][1] && $i < $#ref_repeats ) {
      $fail++;
      $total++;
      $i++;

      if ( $verbage ) {
	print STDERR "Failed to find a record match for $curr_contig in the new pipeline db\n";
      }
    }
  }
}

if ( $fail == 0 ) {
  if ( $verbage ) {
    print STDERR "PASS: All $total records found and correctly match the reference db\n";
  }
  else {
    print STDERR "PASS\n";
  }
}
else {
  print STDERR "FAIL: Pass: $pass  Fail: $fail  Total: $total\n";
}


# Disconnect from the databases
$dbh_new->disconnect;
$dbh_ref->disconnect;


# Title : order
# Usage : Sorts the arrays into order by the following sequence:
#         analysis id, contig number, hid, seq_start, seq_end and h_start

sub order {

  my @a_arr = ();
  my @b_arr = ();
  push @a_arr , @$a;
  push @b_arr , @$b;

  $a_arr[0] <=> $b_arr[0]
    ||
  $a_arr[1] <=> $b_arr[1]
    ||
  $a_arr[2] cmp $b_arr[2]
    ||
  $a_arr[3] <=> $b_arr[3]
    ||
  $a_arr[4] <=> $b_arr[4]
    ||
  $a_arr[5] <=> $b_arr[5]
}


# Title : get_features
# Usage : Grabs feature data from the feature table and returns it as
#         an array

sub get_features {

  my ( $dbh ) = shift;

  my @temp_arr= ();

  my $sth = $dbh->prepare(
     'SELECT analysis, contig, hid, seq_start, seq_end, hstart, hend
      FROM feature' );

  $sth->execute();

  if ( $sth->fetchrow() != 0) {

    # records are stored as:
    # analysis : contig : hid : seq_start : seq_end : hstart : hend

    while ( my @arr = $sth->fetchrow_array() ) {
      push @temp_arr, [ @arr ];
    }
  }

  return @temp_arr;
}


# Title : get_repeat_features
# Usage : Grabs feature data from the repeat_feature table and returns it as
#         an array.  Much the same as get_features

sub get_repeat_features {

  my ( $analysis, $dbh ) = @_;

  my @temp_arr;

  my $sth = $dbh->prepare(
     'SELECT contig, hid, seq_start, seq_end, hstart, hend
      FROM repeat_feature' );

  $sth->execute();

  if ( $sth->fetchrow() != 0) {

    # this may seem a wee bit pointless setting the analysis when in general
    # repeats are only masked by 1 program but this does mean that the data
    # retrieved from the database is consistent with that from the feature table.

    # records are stored as:
    # analysis : contig : hid : seq_start : seq_end : hstart : hend

    while ( my @arr = $sth->fetchrow_array() ) {
      push @temp_arr, [ $analysis , @arr ];
    }
  }

  return @temp_arr;
}



# Title : compare_records
# Usage : compares two records from the stored arrays.
#         A 1 is returned if all the elements agree.
#         A 0 is returned otherwise, even if there is
#         only one or multiple non-matches.

sub compare_records {

  my ( $ref_record, $new_record ) = @_;

  # records are stored as:
  # analysis : contig : hid : seq_start : seq_end : hstart : hend
  # 
  # the comparisons are hard-coded for now

  if (
    $$ref_record[0] == $$new_record[0]  &&
    $$ref_record[1] == $$new_record[1]  &&
    $$ref_record[2] eq $$new_record[2]  &&
    $$ref_record[3] == $$new_record[3]  &&
    $$ref_record[4] == $$new_record[4]  &&
    $$ref_record[5] == $$new_record[5]  &&
    $$ref_record[6] == $$new_record[6] ){

    return 1;
  }
  else {
    return 0;
  }
}
