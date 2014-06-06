# Test Ext.Direct event poll request handling for single events

package test::class;

use strict;

use RPC::ExtDirect;
use RPC::ExtDirect::Event;

our $EVENTS = [
    'foo',
    [ 'foo', 'bar' ],
    { foo => 'qux', bar => 'baz', },
];

sub handle_poll : ExtDirect(pollHandler) {
    my ($class) = @_;

    return RPC::ExtDirect::Event->new('foo', shift @$EVENTS);
}

package main;

use strict;
use warnings;
no  warnings 'uninitialized';

use Test::More tests => 7;

use RPC::ExtDirect::Test::Util;
use RPC::ExtDirect::Server::Util;
use RPC::ExtDirect::Client;

# Host/port in @ARGV means there's server listening elsewhere
my ($host, $port) = maybe_start_server(static_dir => 't/htdocs');
ok $port, "Got host: $host and port: $port";

my $cclass = 'RPC::ExtDirect::Client';

my $client = $cclass->new( host => $host, port => $port,);

my $tests = $test::class::EVENTS;

my $i = 0;

for my $test ( @$tests ) {
    my ($data) = eval { $client->poll() };
    my $exp    = { name => 'foo', data => $test };

    is      $@,    '',   "Poll $i didn't die";
    is_deep $data, $exp, "Poll $i data matches";

    $i++;
};

