=head1 LICENSE

See the NOTICE file distributed with this work for additional information
regarding copyright ownership.

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

package Bio::EnsEMBL::Test::MultiTestDB::MariaDB;

=pod

=head1 NAME

Bio::EnsEMBL::Test::MultiTestDB::MariaDB

=head1 DESCRIPTION

MariaDB specifics for Bio::EnsEMBL::Test::MultiTestDB.

Used automatically, as determined by the 'driver' setting in MultiTestDB.conf.

=cut

use strict;
use warnings;

use English qw(-no_match_vars);

use base 'Bio::EnsEMBL::Test::MultiTestDB';

sub load_txt_dump {
    my ($self, $txt_file, $tablename, $db) = @_;
    if(index($txt_file, 'compressed_genotype_var') != -1) {
      my $load = sprintf(q{LOAD DATA LOCAL INFILE '%s' INTO TABLE `%s`FIELDS ESCAPED BY '\\\\' (variation_id, subsnp_id , @var1) SET genotypes = UNHEX(@var1)}, $txt_file, $tablename);
    	$db->do($load);
    	return $db;
    } elsif (index($txt_file, 'compressed_genotype_region') != -1) {
      my $load = sprintf(q{LOAD DATA LOCAL INFILE '%s' INTO TABLE `%s`FIELDS ESCAPED BY '\\\\' (sample_id, seq_region_id, seq_region_start, seq_region_end, seq_region_strand, @var1) SET genotypes = UNHEX(@var1)}, $txt_file, $tablename);
    	$db->do($load);
    	return $db;
    } else {
    	my $load = sprintf(q{LOAD DATA LOCAL INFILE '%s' INTO TABLE `%s` FIELDS ESCAPED BY '\\\\'}, $txt_file, $tablename);
    	$db->do($load);
    	return $db;
    }

}

sub create_and_use_db {
    my ($self, $db, $dbname) = @_;
    my $create_db = $db->do("CREATE DATABASE $dbname");
    if(! $create_db) {
      $self->note("!! Could not create database [$dbname]");
      return;
    }

    $db->do('use '.$dbname);
    return $db;
}

sub _db_conf_to_dbi {
  my ($self, $db_conf, $options) = @_;
  my %params = ($db_conf->{host} eq 'localhost')?
               (host => $db_conf->{host}):
               (host => $db_conf->{host}, port => $db_conf->{port});
  %params = (%params, %{$options}) if $options;
  my $param_str = join(q{;}, map { $_.'='.$params{$_} } keys %params);
  my $locator = sprintf('DBI:%s:%s', $db_conf->{driver}, $param_str);
  my $db = DBI->connect( $locator, $db_conf->{user}, $db_conf->{pass}, { RaiseError => 1 } );
  return $db if $db;
  $self->diag("Can't connect to database '$locator': ". $DBI::errstr);
  return;
}

sub _dbi_options {
    my $self = shift;
    return {mariadb_local_infile => 1, mariadb_max_allowed_packet => 1024*1024*1024, mariadb_server_prepare => 1};
}

sub _schema_name {
    my ($self, $dbname) = @_;
    return $dbname;
}

sub _db_path {
    my ($self, $driver_handle) = @_;
    return;
}

sub _drop_database {
    my ($self, $db, $dbname) = @_;

    eval {$db->do("DROP DATABASE $dbname");};
    $self->diag("Could not drop database $dbname: $EVAL_ERROR") if $EVAL_ERROR;

    $db->disconnect();

    return;
}

sub do_disconnect {
    my ($self) = @_;
    my $db = $self->dbi_connection();
    $db->disconnect;
    return;
}

1;
