#!/usr/local/bin/perl

# Copyright EMBL-EBI 2001
# Author: Alistair Rust
# Creation: 04.10.2001
# Last modified:

=head1 NAME
  
  flush-rawtables.pl

=head1 SYNPOSIS

  A simple little script which cleans tables after having run 
  contigs through the rawpipeline.  It was primarliy written to
  flush tables after a run of a single contig just to check
  on the functionality of the code and any errors etc.

  Tables affected are:
  - job
  - jobstatus
  - current_status
  - repeat_feature
  - feature
  - InputIdAnalysis (removes any jobs not equal 3)

  Database connection parameters are hard-coded into the top of
  the script but can be over-ridden from the command line. A full
  command line prompt would be:

  ./flush-rawtables.pl -dbname=alistair_db
                       -user=ensadmin
                       -dbpass=foo
                       -host=ecs1a
                       -driver=mysql

=cut
 
use strict;
use Getopt::Long; 
use Bio::EnsEMBL::DBSQL::DBAdaptor; 

my $dbname = "alistair_db";
my $user   = "ensadmin";
my $dbpass = "XXXX";
my $host   = "ecs1a";
my $driver = "mysql";

GetOptions(
   'host=s'     => \$host,
   'dbname=s'   => \$dbname,
   'dbdriver=s' => \$driver,
   'user=s'     => \$user,
   'dbpass=s'   => \$dbpass
)
or die ("Couldn't get options.");


my $db = Bio::EnsEMBL::DBSQL::DBAdaptor->new(
					  -user   => $user,
					  -dbname => $dbname,
					  -pass   => $dbpass,
					  -host   => $host,
					  -driver => $driver
					 );
 
die "Unsuccessful DB connection to alistair_db" unless $db;


print STDERR "Removing completed analysis jobs from the InputIdAnalysis table\n\n";
my $sth = $db->prepare("DELETE from InputIdAnalysis WHERE analysisId !=3");
$sth->execute;


print STDERR "Removing jobs from the job table\n\n";
$sth = $db->prepare("DELETE from job");
$sth->execute;

print STDERR "Removing jobs from the jobstatus table\n\n";
$sth = $db->prepare("DELETE from jobstatus");
$sth->execute;

print STDERR "Removing jobs from the current_status table\n\n";
$sth = $db->prepare("DELETE from current_status");
$sth->execute;

print STDERR "Cleaning the repeat_feature table\n\n";
$sth = $db->prepare("DELETE from repeat_feature");
$sth->execute;

print STDERR "Cleaning the feature table\n\n";
$sth = $db->prepare("DELETE from feature");
$sth->execute;

print STDERR "Cleaning the fset table\n\n";
$sth = $db->prepare("DELETE from fset");
$sth->execute;

print STDERR "Cleaning the fset_feature table\n\n";
$sth = $db->prepare("DELETE from fset_feature");
$sth->execute;
