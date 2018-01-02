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

package Bio::EnsEMBL::App::DumpTestSchema;

use 5.010;

use MooseX::App::Simple qw(Color);

use File::Slurp;
use File::Spec;

use Bio::EnsEMBL::Test::MultiTestDB;
use DBIx::Class::Schema::Loader qw(make_schema_at);

option 'test_dir' => (
    is            => 'ro',
    isa           => 'Str',
    default       => sub { $ENV{PWD} },
    cmd_aliases   => [qw/test-dir testdir/],
    documentation => q[Directory containing MultiTestDB.conf],
    );

option 'species' => (
    is            => 'ro',
    isa           => 'Str',
    default       => 'homo_sapiens',
    documentation => q[Species],
    );

option 'db_type' => (
    is            => 'ro',
    isa           => 'Str',
    default       => 'core',
    cmd_aliases   => [qw/db-type dbtype/],
    documentation => q[Database type],
    );

option 'dump_schema' => (
    is            => 'ro',
    isa           => 'Bool',
    cmd_aliases   => [qw/dump-schema dumpschema/],
    documentation => q[Dump DBIC schema],
    );

option 'schema_class' => (
    is            => 'ro',
    isa           => 'Str',
    default       => 'Bio::EnsEMBL::Test::Schema',
    cmd_aliases   => [qw/schema-class schemaclass/],
    documentation => q[Generated schema class],
    );

option 'schema_dir' => (
    is            => 'ro',
    isa           => 'Str',
    default       => sub { $ENV{PWD} },
    cmd_aliases   => [qw/schema-dir schemadir/],
    documentation => q[Directory for schema class dump],
    );

option 'ddl_dir' => (
    is            => 'ro',
    isa           => 'Str',
    default       => sub { $ENV{PWD} },
    cmd_aliases   => [qw/ddl-dir ddldir/],
    documentation => q[Directory for ddl output],
    );

option 'version' => (
    is            => 'ro',
    isa           => 'Str',
    default       => '0.1',
    documentation => q[Generated schema version],
    );

option 'check_driver' => (
    is            => 'ro',
    isa           => 'Str',
    default       => 'mysql',
    cmd_aliases   => [qw/check-driver checkdriver/],
    documentation => q[Expected source DBD driver type],
    );

option 'dump_driver' => (
    is            => 'ro',
    isa           => 'Str',
    default       => 'SQLite',
    cmd_aliases   => [qw/dump-driver dumpdriver/],
    documentation => q[Destination DBD driver type],
    );

has 'dbc' => (
    is   => 'rw',
    isa  => 'Bio::EnsEMBL::DBSQL::DBConnection',
    );

has ddl_file => (
    is            => 'ro',
    isa           => 'Str',
    builder       => '_build_ddl_file',
    lazy          => 1,
    );

sub _build_ddl_file {
    my ($self)  = @_;

    my $class_file = $self->schema_class;
    $class_file =~ s/::/-/g;

    my $filename = join('-', $class_file, $self->version, $self->dump_driver);
    $filename .= '.sql';

    return File::Spec->catfile($self->ddl_dir, $filename);
}

sub run {
    my ($self)  = @_;

    my $mdb = $self->get_MultiTestDB;
    my $dbc = $self->dbc($mdb->get_DBAdaptor($self->db_type)->dbc);

    my $driver = $dbc->driver;
    my $check_driver = $self->check_driver;
    die "Driver is '$driver' but expected '$check_driver'" unless $driver eq $check_driver;

    $self->make_schema;
    $self->create_ddl;
    $self->patch_ddl;

    return;
}

sub get_MultiTestDB {
    my ($self)  = @_;
    my $mdb = Bio::EnsEMBL::Test::MultiTestDB->new($self->species, $self->test_dir, 1);
    $mdb->load_database($self->db_type);
    $mdb->create_adaptor($self->db_type);
    return $mdb;
}

sub make_schema {
    my ($self) = @_;

    my $loader_options = { naming => 'current' };
    $loader_options->{dump_directory} = $self->schema_dir if $self->dump_schema;

    make_schema_at($self->schema_class, $loader_options, [ sub { $self->dbc->db_handle } ]);
}

sub create_ddl {
    my ($self) = @_;
    my $schema = $self->connected_schema;
    $schema->create_ddl_dir([$self->dump_driver],
                            '0.1',
                            $self->ddl_dir,
                            undef,  # pre-version
                            { add_drop_table => 0 },
        );
}

sub patch_ddl {
    my ($self) = @_;
    my $ddl_file = $self->ddl_file;
    my $file = read_file($ddl_file);
    $file =~ s/INTEGER PRIMARY KEY/INTEGER PRIMARY KEY AUTOINCREMENT/g;
    write_file($ddl_file, $file);
    return;
}

sub connected_schema {
    my ($self) = @_;
    return $self->schema_class->connect( [ sub { $self->dbc->db_handle } ] );
}

no Moose;

# End of module

package main;

my $result = Bio::EnsEMBL::App::DumpTestSchema->new_with_options->run;
exit ($result ? $result : 0);

# EOF
