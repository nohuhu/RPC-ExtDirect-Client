# Test Ext.Direct form POST request handling

package test::class;

use strict;

use RPC::ExtDirect Action => 'test';

sub handle_form : ExtDirect(formHandler) {
    my ($class, %arg) = @_;

    my @fields = grep { !/^file_uploads/ } keys %arg;

    my %result;
    @result{ @fields } = @arg{ @fields };

    return \%result;
}

package main;

use strict;
use warnings;

use Test::More tests => 8;

use lib 't/lib';
use RPC::ExtDirect::Test::Util;
use RPC::ExtDirect::Server::Util;
use RPC::ExtDirect::Client::Test::Util;

BEGIN { use_ok 'RPC::ExtDirect::Client' };

# Clean up %ENV so that HTTP::Tiny does not accidentally connect to a proxy
clean_env;

# Host/port in @ARGV means there's server listening elsewhere
my ($host, $port) = maybe_start_server(static_dir => 't/htdocs');
ok $port, "Got host: $host and port: $port";

my $cclass = 'RPC::ExtDirect::Client';

my $client = eval { $cclass->new( host => $host, port => $port,) };

is     $@,      '',      "Didn't die";
ok     $client,          'Got client object';
isa_ok $client, $cclass, 'Right object, too,';

my $fields = { foo => 'qux', bar => 'baz' };

my $data = eval {
    $client->submit(
        action => 'test',
        method => 'handle_form',
        arg    => $fields,
    )
};

is      $@,        '',            "Form didn't die";
unlike  ref $data, qr/Exception/, "Form result not an exception";
is_deep $data,     $fields,       "Form data match";

