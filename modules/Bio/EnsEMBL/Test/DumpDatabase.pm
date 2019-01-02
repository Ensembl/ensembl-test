=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2019] EMBL-European Bioinformatics Institute

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

package Bio::EnsEMBL::Test::DumpDatabase;

use strict;
use warnings;

use Bio::EnsEMBL::Utils::IO qw/work_with_file/;
use Bio::EnsEMBL::Utils::Scalar qw/assert_ref/;
use File::Spec;
use File::Path qw/mkpath/;
use Scalar::Util qw/looks_like_number/;

sub new {
  my ($class, $dba, $base_directory, $old_schema_details, $new_schema_details) = @_;
  my $self = bless({}, (ref($class) || $class));
  die "No DBA given" unless $dba;
  die "No directory given" unless $base_directory;
  
  $self->dba($dba);
  $self->base_directory($base_directory);
  $self->old_schema_details($old_schema_details);
  $self->new_schema_details($new_schema_details);
  return $self;
}

sub dump {
  my ($self) = @_;
  $self->dump_sql();
  $self->dump_tables();
  $self->delete_tables();
  return;
}

sub dba {
  my ($self, $dba) = @_;
  if(defined $dba) {
    assert_ref($dba, 'Bio::EnsEMBL::DBSQL::DBAdaptor', 'source DBAdaptor');
  	$self->{'dba'} = $dba;
  }
  return $self->{'dba'};
}

sub base_directory {
  my ($self, $base_directory) = @_;
  if(defined $base_directory) {
    die "Cannot find the directory $base_directory" if ! -d $base_directory;
  	$self->{'base_directory'} = $base_directory;
  }
  return $self->{'base_directory'};
}

sub old_schema_details {
  my ($self, $old_schema_details) = @_;
  $self->{'old_schema_details'} = $old_schema_details if defined $old_schema_details;
  return $self->{'old_schema_details'};
}

sub new_schema_details {
  my ($self, $new_schema_details) = @_;
  $self->{'new_schema_details'} = $new_schema_details if defined $new_schema_details;
  return $self->{'new_schema_details'};
}

sub directory {
  my ($self) = @_;
  my $dir = File::Spec->catdir($self->base_directory(), $self->production_name(), $self->group());
  if(! -d $dir) {
    mkpath $dir;
  }
  return $dir;
}

sub production_name {
  my ($self) = @_;
  eval {
    my $mc = $self->dba->get_MetaContainer();
    if($mc->can('get_production_name')) {
      return $mc->get_production_name();
    }
  };
  return $self->dba->species;
}

sub group {
  my ($self) = @_;
  return $self->dba->group;
}

sub dump_sql {
  my ($self) = @_;
  my $file = File::Spec->catfile($self->directory(), 'table.sql');
  my $h = $self->dba->dbc->sql_helper();
  
  my @real_tables = @{$self->_tables()};
  my @views       = @{$self->_views()};
  
  my $schema_differences = $self->_schema_differences();
  #Do not redump if there were no schema changes (could be just a data patch)
  return if ! $schema_differences;
    
  work_with_file($file, 'w', sub {
    my ($fh) = @_;
    foreach my $table (@real_tables) {
      my $sql = $h->execute_single_result(-SQL => "show create table ${table}", -CALLBACK => sub { return $_[0]->[1] });
      print $fh "$sql;\n\n";
    }
    foreach my $view (@views) {
      my $sql = $h->execute_single_result(-SQL => "show create view ${view}", -CALLBACK => sub { return $_[0]->[1] });
      print $fh "$sql;\n\n";
    }
    return;
  });
  
  return;
}

sub dump_tables {
  my ($self) = @_;
  my $tables = $self->_tables();
  foreach my $table (@{$tables}) {
    my $data_difference = $self->_data_differences($table);
    #Skip this iteration of the loop if there were no data differences
    next if ! $data_difference;
    $self->dump_table($table);
  }
  return;
}

sub dump_table {
  my ($self, $table) = @_;
  my $response = $self->dba->dbc->sql_helper()->execute_simple(
       -SQL => "select count(*) from $table");
  return if ($response->[0] == 0);
  my $file = File::Spec->catfile($self->directory(), $table.'.txt');
  work_with_file($file, 'w', sub {
    my ($fh) = @_;
    $self->dba->dbc->sql_helper()->execute_no_return(
      -SQL => "select * from $table",
      -CALLBACK => sub {
        my ($row) = @_;
        my @copy;
        foreach my $e (@{$row}) {
          if(!defined $e) {
            $e = '\N';
          }
          elsif(!looks_like_number($e)) {
            $e =~ s/\n/\\\n/g;
            $e =~ s/\t/\\\t/g; 
          }
          push(@copy, $e);
        }
        my $line = join(qq{\t}, @copy);
        print $fh $line, "\n";
      }
    );
  });
  return;
}

sub delete_tables {
  my ($self) = @_;
  my $old_schema_details = $self->old_schema_details();
  my $new_schema_details = $self->new_schema_details();
  return unless $old_schema_details && $new_schema_details;
  foreach my $old_table (keys %{$old_schema_details}) {
    if(! exists $new_schema_details->{$old_table}) {
      my $file = File::Spec->catfile($self->directory(), $old_table.'.txt');
      unlink $file or die "Cannot unlink the file '$file': $!";
    }
  }
  return;
}

sub _tables {
  my ($self) = @_;
  my $lookup = $self->_table_lookup();
  return [sort grep { $lookup->{$_} ne 'VIEW' } keys %$lookup ];
}

sub _views {
  my ($self) = @_;
  my $lookup = $self->_table_lookup();
  return [sort grep { $lookup->{$_} eq 'VIEW' } keys %$lookup];
}

sub _table_lookup {
  my ($self) = @_;
  if(! $self->{_table_lookup}) {
    my $h = $self->dba->dbc->sql_helper();
    my $lookup = $h->execute_into_hash(-SQL => 'select TABLE_NAME, TABLE_TYPE from information_schema.TABLES where TABLE_SCHEMA = DATABASE()');
    $self->{_table_lookup} = $lookup;
  }
  return $self->{_table_lookup};
}

sub _schema_differences {
  my ($self) = @_;
  my $old_schema_details = $self->old_schema_details();
  my $new_schema_details = $self->new_schema_details();
  
  #Assume there is a difference if none or 1 hash was provided
  return 1 unless $old_schema_details && $new_schema_details;
  
  my $old_schema_concat = join(qq{\n}, map { $old_schema_details->{$_}->{create} } sort keys %$old_schema_details);
  my $new_schema_concat = join(qq{\n}, map { $new_schema_details->{$_}->{create} || '' } sort keys %$old_schema_details);
  
  return ( $old_schema_concat ne $new_schema_concat ) ? 1 : 0;
}

sub _data_differences {
  my ($self, $table) = @_;
  my $old_schema_details = $self->old_schema_details();
  my $new_schema_details = $self->new_schema_details();
  
  #Assume there is a difference if none or 1 hash was provided
  return 1 unless $old_schema_details && $new_schema_details;
  return 1 if ! exists $old_schema_details->{$table};
  return 1 if ! exists $new_schema_details->{$table};
  return ( $old_schema_details->{$table}->{checksum} ne $new_schema_details->{$table}->{checksum}) ? 1 : 0;
}

sub _delete_table_file {
  my ($self, $table) = @_;
  
  return;
}

sub DESTROY {
  my ($self) = @_;
  $self->dba->dbc->disconnect_if_idle();
  return;
}

1;
