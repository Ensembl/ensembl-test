package Bio::EnsEMBL::Test::MultiTestDB::mysql;

=pod

=head1 NAME

Bio::EnsEMBL::Test::MultiTestDB::mysql

=head1 SYNOPSIS


=head1 DESCRIPTION


=cut

use strict;
use warnings;

use English qw(-no_match_vars);

use base 'Bio::EnsEMBL::Test::MultiTestDB';

sub load_txt_dump {
    my ($self, $txt_file, $tablename, $db) = @_;
    my $load = sprintf(q{LOAD DATA LOCAL INFILE '%s' INTO TABLE `%s` FIELDS ESCAPED BY '\\\\'}, $txt_file, $tablename);
    $db->do($load);
    return;
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
  my %params = (host => $db_conf->{host}, port => $db_conf->{port});
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
    return {mysql_local_infile => 1};
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
