requires 'DBI';
requires 'DBD::mysql', '<= 4.050'; # newer versions do not support MySQL 5
requires 'Test::More';
requires 'Test::Warnings';
requires 'Devel::Peek';
requires 'Devel::Cycle';
requires 'Error';
requires 'PadWalker';
requires 'Test::Builder::Module';
requires 'IO::String';
requires 'IO::Scalar';
requires 'Test::FTP::Server';
requires 'MooseX::App::Simple';
requires 'File::Path';
requires 'File::Spec';
requires 'Scalar::Util';
requires 'Test::Exception';
requires 'Test::TCP';
requires 'English';
requires 'Data::Dumper';
requires 'File::Basename';
requires 'File::Copy';
requires 'File::Spec::Functions';
requires 'IO::Dir';
requires 'IO::File';
requires 'POSIX';
requires 'File::Spec';
requires 'File::Temp';
requires 'Time::Piece';

feature 'testdb_patcher', 'Additional dependencies of scripts used to patch test databases' => sub {
  requires 'DBIx::Class::Schema::Loader';
  requires 'SQL::Translator';
};
