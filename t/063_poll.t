# Test Ext.Direct event poll request handling for multiple events

package test::class;

use strict;

use RPC::ExtDirect;
use RPC::ExtDirect::Event;

sub handle_poll : ExtDirect(pollHandler) {
    my ($class) = @_;

    return (
        RPC::ExtDirect::Event->new('foo', 'bar'),
        RPC::ExtDirect::Event->new('bar', 'baz'),
    );
}

package main;

use strict;
use warnings;

use Test::More tests => 3;

use RPC::ExtDirect::Test::Util;
use RPC::ExtDirect::Server::Util;
use RPC::ExtDirect::Client;

# Host/port in @ARGV means there's server listening elsewhere
my ($host, $port) = maybe_start_server(static_dir => 't/htdocs');
ok $port, "Got host: $host and port: $port";

my $client = RPC::ExtDirect::Client->new( host => $host, port => $port,);

my $want = [{
    name => 'foo',
    data => 'bar',
}, {
    name => 'bar',
    data => 'baz',
}];

my @have = $client->poll();

is_deep \@have, $want, "List context data";

my $have = $client->poll();

is_deep $have, $want, "Scalar context data";


