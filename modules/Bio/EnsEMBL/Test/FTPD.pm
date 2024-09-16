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

package Bio::EnsEMBL::Test::FTPD;

=pod

=head1 NAME

Bio::EnsEMBL::Test::FTPD;

=head1 SYNOPSIS

  my $root_dir = '/path/to/static/files';
  my $user = 'testuser';
  my $pass = 'testpass';
  my $ftpd = Bio::EnsEMBL::Test::FTPD->new($user, $pass, $root_dir);

  my $ftp_uri = "ftp://$user:$pass\@localhost:" . $ftpd->port . '/myfiletoretreive.txt';
  ok(do_FTP($ftp_uri), 'Basic successful get');

=head1 DESCRIPTION

This module creates a simple FTP daemon with a root directory and credentials
given at instantiation. It uses Net::FTPServer internally so all basic FTP
functionality is available.

If the root directory doesn't exist an error will be raised.

The FTP daemon is destroyed on exit.

=cut

use strict;
use warnings;

use Test::More;
use Test::Exception;
use Test::TCP;
require_ok('Test::FTP::Server');

use base 'Test::Builder::Module';

=head2 new

  Arg[1]     : string $user
               Username for ftp server authentication
  Arg[2]     : string $pass
               Password for ftp server authentication
  Arg[1]     : string $root_dir
               The directory where files to be returned by
               the FTPD live

  Returntype : Test::TCP instance, where listening
               port can be retreived

=cut

sub new {
    my ($self, $user, $pass, $root_dir) = @_;

    # Do we have a valid DocumentRoot
    ok( -d $root_dir, 'Root dir for HTTPD is valid');

    # Create an FTPD wrapped in a Test::TCP
    # instance, Test::TCP finds an unused port
    # for the FTPD to bind to
    my $ftpd = Test::TCP->new(
        code => sub {
	    my $port = shift;
 
	    my $ftpd = Test::FTP::Server->new(
		'users' => [{
		    'user' => $user,
		    'pass' => $pass,
		    'root' => $root_dir,
		}],
		'ftpd_conf' => {
		    'port' => $port,
		    'daemon mode' => 1,
		    'run in background' => 0,
		},
	    )->run;
	});

    return $ftpd;
}

1;
