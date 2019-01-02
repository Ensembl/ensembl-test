# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2019] EMBL-European Bioinformatics Institute
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

use Cwd;
use File::Basename;
use File::Spec;
use Test::More tests => 2;
use Test::Warnings;

use Bio::EnsEMBL::Test::TestUtils;

subtest 'all_source_code', sub {

    my $playground_path = File::Spec->catfile( dirname(Cwd::realpath($0)), 'playground' );

    my @a = all_source_code($playground_path);
    is(scalar(@a), 6, 'Got 6 files');
    my $expected_files = [ 'a.pl', 'c.c', 'd.sqlite', 'e.mysql', 'f.pgsql', 'modules/a.R' ]; 
    s/$playground_path\/// for @a;
    is_deeply([sort @a], $expected_files, 'The files are the right ones');

    my $old_dir = chdir $playground_path;
    @a = all_source_code();
    is(scalar(@a), 1, 'Got 1 file');
    $expected_files = [ 'modules/a.R' ]; 
    is_deeply([sort @a], $expected_files, 'The file is the right one');
    chdir $old_dir;
};

done_testing();
