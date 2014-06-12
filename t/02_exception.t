# Test Ext.Direct exception handling

package test::class;

use strict;

use RPC::ExtDirect Action => 'test';

sub dies : ExtDirect(0) {
    die "Whoa there!\n";
}

package main;

use strict;
use warnings;

use Test::More tests => 9;

use RPC::ExtDirect::Server::Util;

BEGIN { use_ok 'RPC::ExtDirect::Client' };

# Host/port in @ARGV means there's server listening elsewhere
my ($host, $port) = maybe_start_server(static_dir => 't/htdocs');
ok $port, "Got host: $host and port: $port";

my $cclass = 'RPC::ExtDirect::Client';

my $client = eval { $cclass->new( host => $host, port => $port,) };

is     $@,      '',      "Didn't die";
ok     $client,          'Got client object';
isa_ok $client, $cclass, 'Right object, too,';

# Try calling nonexistent method

my $data = eval {
    $client->call( action => 'test', method => 'nonexistent' )
};

my $regex = qr/^Method nonexistent is not found in Action test/;

like $@, $regex, "Nonexistent croaked";

# Try calling method that dies

$data = eval {
    $client->call( action => 'test', method => 'dies', arg => [], )
};

is   $@,             '',             "Method call didn't die";
like ref $data,      qr/Exception/,  'Dying method result is exception';
like $data->message, qr/Whoa/,       'Dying method description matches';

