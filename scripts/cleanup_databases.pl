#!/usr/bin/env perl
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2018] EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


use strict;
use warnings;

use Bio::EnsEMBL::Test::MultiTestDB;
use Getopt::Long;
use Pod::Usage;

sub run {
  my ($class) = @_;
  $ENV{RUNTESTS_HARNESS} = 0;
  my $self = bless({}, 'main');
  $self->args();
  my $config = Bio::EnsEMBL::Test::MultiTestDB->get_db_conf($self->{opts}->{curr_dir});
  foreach my $species (sort keys %{$config->{databases}}) {
    my $multi = Bio::EnsEMBL::Test::MultiTestDB->new($species, $self->{opts}->{curr_dir});
    undef $multi;
  }
  return;
}

sub args {
  my ($self) = @_;
  my $opts = {};
  GetOptions(
    $opts, qw/
      curr_dir=s
      help
      man
      /
  ) or pod2usage(-verbose => 1, -exitval => 1);
  pod2usage(-verbose => 1, -exitval => 0) if $opts->{help};
  pod2usage(-verbose => 2, -exitval => 0) if $opts->{man};
  
  pod2usage(-verbose => 2, -exitval => 2, -msg => "No --curr_dir option given") if ! $opts->{curr_dir};
  pod2usage(-verbose => 2, -exitval => 2, -msg => "--curr_dir is not a directory") if ! -d $opts->{curr_dir};
  my $config = File::Spec->catfile($opts->{curr_dir}, 'MultiTestDB.conf');
  pod2usage(-verbose => 2, -exitval => 2, -msg => "Cannot find a MultiTestDB.conf at '${config}'. Check your --curr_dir command line option") if ! -f $config;

  $self->{opts} = $opts;
  return;
}

run();

1;
__END__

=head1 NAME

  cleanup_databases.pl

=head1 SYNOPSIS

  ./cleanup_databases.pl --curr_dir ensembl/modules/t

=head1 DESCRIPTION

Loads any available frozen files in the given directory, loads those schemas and attempts
to run cleanup of the databases

=head1 OPTIONS

=over 8

=item B<--curr_dir>

Current directory. Should be set to the directory which has your configuration files

=back

=cut
