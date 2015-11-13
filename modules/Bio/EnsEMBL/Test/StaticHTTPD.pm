=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

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

package Bio::EnsEMBL::Test::StaticHTTPD;

=pod

=head1 NAME

Bio::EnsEMBL::Test::StaticHTTPD;

=head1 SYNOPSIS

  my $root_dir = '/path/to/static/files';
  my $httpd = Bio::EnsEMBL::Test::StaticHTTPD->new($root_dir);
  my $endppoint = $httpd->endpoint;

  ok(do_GET($endpoint . '/file.txt'), 'Basic successful fetch');

=head1 DESCRIPTION

This module creates a simple HTTPD daemon that returns static files in the 
root_dir if they exist, return content-type will always be text/plain.

If the file doesn't exist in the root_dir, a 404 error code will be returned.

The HTTPD daemon is destroyed on exit.

=cut

use strict;
use warnings;

use Test::More;
use Test::Exception;
use File::Spec;

use Bio::EnsEMBL::Utils::IO qw/slurp/;

require_ok('Test::Fake::HTTPD');

use base 'Test::Builder::Module';

=head2 new

  Arg[1]     : string $root_dir
               The directory where files to be returned by
               the HTTPD live, similar to DocumentRoot in Apache
  Arg[2]     : int $timeout
               Optional argument for httpd timeout, defaults
               to 30 seconds

  Returntype : httpd instance

=cut

sub new {
    my ($self, $root_dir, $timeout) = @_;

    # Do we have a valid DocumentRoot
    ok( -d $root_dir, 'Root dir for HTTPD is valid');

    # Create the new HTTPD instance
    my $httpd = Test::Fake::HTTPD->new(
	timeout => (defined $timeout ? $timeout : 30),
	);

    # Stash the root_dir for the run subroutine
    $ENV{httpd_root_dir} = $root_dir;

    # Callback routine for serving requests
    $httpd->run(sub {
	my ($req) = @_;
	my $uri = $req->uri;

	# Make the file path based on our DocumentRoot and requested path
	my $file = File::Spec->catpath(undef, $ENV{httpd_root_dir}, $uri);

	return do {
	    if( -f $file ) {
		my $file_contents = slurp($file);
		[ 200, [ 'Content-Type', 'text/pain'], [ $file_contents ] ];
	    } else {
		[ 404, [ 'Content-type', 'text/plain' ], ['File does not exist']];
	    }
	}
    });

    ok( defined $httpd, 'Got a web server' );
    diag( sprintf "You can connect to your server at %s.\n", $httpd->host_port );
    return $httpd;
}

1;
