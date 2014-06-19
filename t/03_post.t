# Test Ext.Direct POST request handling

package test::class;

use strict;

use RPC::ExtDirect Action => 'test';

sub ordered : ExtDirect(3) {
    my $class = shift;

    return [ splice @_, 0, 3 ];
}

sub named : ExtDirect(params => ['arg1', 'arg2', 'arg3']) {
    my ($class, %arg) = @_;

    return { %arg };
}

sub named_no_strict : ExtDirect(params => ['arg1', 'arg2'], strict => !1) {
    my ($class, %arg) = @_;

    return { %arg };
}

package main;

use strict;
use warnings;

use Test::More tests => 14;

use RPC::ExtDirect::Test::Util;
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

my $arg = [ qw(foo bar qux mumble splurge) ];
my $exp = [ qw(foo bar qux) ];

my $data = eval {
    $client->call(action => 'test', method => 'ordered', arg => $arg)
};

is      $@,        '',            "Ordered didn't die";
unlike  ref $data, qr/Exception/, 'Ordered not exception';
is_deep $data,     $exp,          'Ordered return data matches';

$arg = { arg1 => 'foo', arg2 => 'bar', arg3 => 'qux', arg4 => 'mumble' };
$exp = { arg1 => 'foo', arg2 => 'bar', arg3 => 'qux' };

$data = eval {
    $client->call(action => 'test', method => 'named', arg => $arg)
};

is      $@,        '',            "Named didn't die";
unlike  ref $data, qr/Exception/, 'Named not exception';
is_deep $data,     $exp,          'Named return data matches';

$data = eval {
    $client->call(
        action => 'test',
        method => 'named_no_strict',
        arg    => $arg,
    )
};

is      $@,        '',            "Named !strict didn't die";
unlike  ref $data, qr/Exception/, "Named !strict not exception";
is_deep $data,     $arg,          "Named !strict return data matches";

