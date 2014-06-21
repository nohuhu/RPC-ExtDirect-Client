# Test Ext.Direct exception handling

package test::class;

use strict;

use RPC::ExtDirect Action => 'test';

sub ordered : ExtDirect(3) { shift; [@_] }
sub named : ExtDirect(params => [qw/ foo bar /]) { shift; [@_] }
sub no_strict : ExtDirect(params => [qw/ foo /], strict => !1) {
    shift; [@_]
}
sub form : ExtDirect(formHandler) { shift; [@_] }
sub dies : ExtDirect(0) { die "Whoa there!\n"; }

package main;

use strict;
use warnings;

use Test::More tests => 17;

use lib 't/lib';
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

# Try calling a Method in a nonexistent Action
my $data = eval {
    $client->call( action => 'nonexistent', method => 'ordered' )
};

my $regex = qr/^Action nonexistent is not found/;
like $@, $regex, "Nonexistent action";

# Try calling a nonexistent Method in existing Action
$data = eval {
    $client->call( action => 'test', method => 'nonexistent' )
};

$regex = qr/^Method nonexistent is not found in Action test/;
like $@, $regex, "Nonexistent method";

# Not enough arguments for an ordered method
$data = eval {
    $client->call( action => 'test', method => 'ordered', arg => [ 42 ], )
};

$regex = qr/requires 3 argument\(s\) but only 1 are provided/;
like $@, $regex, "Not enough ordered arguments";

# Wrong type of arguments for an ordered method
$data = eval {
    $client->call( action => 'test', method => 'ordered', arg => {}, )
};

$regex = qr/expects ordered arguments in arrayref/;
like $@, $regex, "Wrong arguments for ordered";

# Not all specified arguments for a named method
$data = eval {
    $client->call(
        action => 'test',
        method => 'named',
        arg    => { foo => 'bar' },
    )
};

$regex = qr/parameters: 'foo, bar'; these are missing: 'bar'/;
like $@, $regex, "Not enough named arguments";

# Not all specified arguments for a non-strict named method
$data = eval {
    $client->call(
        action => 'test',
        method => 'no_strict',
        arg    => { bar => 'baz', },
    )
};

$regex = qr/parameters: 'foo'; these are missing: 'foo'/;
like $@, $regex, "Not enough named arguments strict off";

# Wrong argument type for named
$data = eval {
    $client->call( action => 'test', method => 'named', arg => [], )
};

$regex = qr/expects named arguments in hashref/;
like $@, $regex, "Wrong arguments for named";

# Wrong argument type for formHandler
$data = eval {
    $client->submit( action => 'test', method => 'form', arg => [], )
};

$regex = qr/expects named arguments in hashref/;
like $@, $regex, "Wrong arguments for formHandler";

# Trying to upload unreadable or nonexisting file
$data = eval {
    $client->upload(
        action => 'test',
        method => 'form',
        arg    => {},
        upload => ['nonexistent_file_with_a_long_name'],
    )
};

$regex = qr{Upload entry 'nonexistent_file_with_a_long_name' is not readable};
like $@, $regex, "Unreadable upload";

# Finally, try calling a method that dies
$data = eval {
    $client->call( action => 'test', method => 'dies', arg => [], )
};

is   $@,             '',             "Method call didn't die";
like ref $data,      qr/Exception/,  'Dying method result is exception';
like $data->message, qr/Whoa/,       'Dying method description matches';

