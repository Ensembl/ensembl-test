package Bio::EnsEMBL::Test::DumpDatabase;

use strict;
use warnings;

use Bio::EnsEMBL::Utils::IO qw/work_with_file/;
use Bio::EnsEMBL::Utils::Scalar qw/assert_ref/;
use File::Spec;
use File::Path qw/mkpath/;
use Scalar::Util qw/looks_like_number/;

sub new {
  my ($class, $dba, $base_directory) = @_;
  my $self = bless({}, (ref($class) || $class));
  die "No DBA given" unless $dba;
  die "No directory given" unless $base_directory;
  
  $self->dba($dba);
  $self->base_directory($base_directory);
  return $self;
}

sub dump {
  my ($self) = @_;
  $self->dump_sql();
  $self->dump_tables();
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
  return $self->dba->get_MetaContainer()->get_production_name();
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
  
  work_with_file($file, 'w', sub {
    my ($fh) = @_;
    foreach my $table (@real_tables) {
      my $sql = $h->execute_single_result(-SQL => "show create table ${table}", -CALLBACK => sub { return $_[0]->[1] });
      print $fh "$sql;\n";
    }
    foreach my $view (@views) {
      my $sql = $h->execute_single_result(-SQL => "show create view ${view}", -CALLBACK => sub { return $_[0]->[1] });
      print $fh "$sql;\n";
    }
    return;
  });
  
  return;
}

sub dump_tables {
  my ($self) = @_;
  my $tables = $self->_tables();
  foreach my $table (@{$tables}) {
    $self->dump_table($table);
  }
  return;
}

sub dump_table {
  my ($self, $table) = @_;
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

sub _tables {
  my ($self) = @_;
  my $lookup = $self->_table_lookup();
  return [grep { $lookup->{$_} ne 'VIEW' } keys %$lookup];
}

sub _views {
  my ($self) = @_;
  my $lookup = $self->_table_lookup();
  return [grep { $lookup->{$_} eq 'VIEW' } keys %$lookup];
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

sub DESTROY {
  my ($self) = @_;
  $self->dba->dbc->disconnect_if_idle();
  return;
}

1;