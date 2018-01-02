=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2018] EMBL-European Bioinformatics Institute

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

package Bio::EnsEMBL::Test::MultiTestDB::SQLite;

=pod

=head1 NAME

Bio::EnsEMBL::Test::MultiTestDB::SQLite

=head1 DESCRIPTION

SQLite specifics for Bio::EnsEMBL::Test::MultiTestDB.

Used automatically, as determined by the 'driver' setting in MultiTestDB.conf.

=cut

use strict;
use warnings;

use English qw(-no_match_vars);
use File::Basename;
use File::Path qw(make_path);
use File::Spec::Functions;      # catfile

use base 'Bio::EnsEMBL::Test::MultiTestDB';

sub load_txt_dump {
    my ($self, $txt_file, $tablename, $db) = @_;

    $db->disconnect;

    my $db_type = basename(dirname($txt_file)); # yuck!!
    my $db_file = $self->{conf}->{$db_type}->{dbname}; # yuck, but at least it's there
    my $command = sprintf('.import %s %s', $txt_file, $tablename);
    system('sqlite3', '-separator', "\t", $db_file, $command) == 0
        or die "sqlite3 import of '$txt_file' failed: $?";

    $db = $self->_do_connect($db_file);

    # NULL processing
    my $sth = $db->column_info(undef, 'main', $tablename, '%');
    my $cols = $sth->fetchall_arrayref({});
    foreach my $col (@$cols) {
        if ($col->{NULLABLE} == 1) {
            my $colname = $col->{COLUMN_NAME};
            my $up_sth = $db->prepare(sprintf(
                                           'UPDATE %s SET %s = NULL WHERE %s IN ("NULL", "\N")',
                                           $tablename, $colname, $colname));
            my $rows = $up_sth->execute;
            $self->note("Table $tablename, column $colname: set $rows rows to NULL") if $rows > 0;
        }
    }

    return $db;
}

our %dbi;

sub create_and_use_db {
    my ($self, $db, $dbname) = @_;
    return $dbi{$dbname} if $dbi{$dbname};

    my $create_db = $self->_do_connect($dbname);
    if(! $create_db) {
      $self->note("!! Could not create database [$dbname]");
      return;
    }
    return $dbi{$dbname} = $create_db;
}

sub _do_connect {
    my ($self, $dbname) = @_;

    my $locator = sprintf('DBI:SQLite:dbname=%s', $dbname);
    my $dbh = DBI->connect($locator, undef, undef, { RaiseError => 1 } );
    return $dbi{$dbname} = $dbh;
}

sub _db_conf_to_dbi {
    my ($self, $db_conf, $options) = @_;
    my $dbdir = $db_conf->{dbdir};
    unless ($dbdir) {
        $self->diag("!! Must specify dbdir for SQLIte files");
        return;
    }
    make_path($dbdir, {error => \my $err});
    if (@$err) {
        $self->diag("!! Couldn't create path '$dbdir'");
        return;
    }
    return {
        db_conf => $db_conf,
        options => $options,
    };
}

sub _dbi_options {
    my $self = shift;
    return undef;
}

sub _schema_name {
    my ($self, $dbname) = @_;
    return 'main';
}

sub _db_path {
    my ($self, $driver_handle) = @_;
    return $driver_handle->{db_conf}->{dbdir};
}

sub _drop_database {
    my ($self, $db, $dbname) = @_;

    eval { unlink $dbname };
    $self->diag("Could not drop database $dbname: $EVAL_ERROR") if $EVAL_ERROR;

    return;
}

sub do_disconnect {
    my ($self) = @_;
    foreach my $dbname ( keys %dbi ) {
        $dbi{$dbname}->disconnect;
    }
    return;
}

1;
