# Test Ext.Direct event poll request handling for empty responses

package test::class;

use strict;

use RPC::ExtDirect;
use RPC::ExtDirect::Event;

sub handle_poll : ExtDirect(pollHandler) { return; }

package main;

use strict;
use warnings;

use Test::More tests => 2;

use RPC::ExtDirect::Server::Util;
use RPC::ExtDirect::Client;

# Host/port in @ARGV means there's server listening elsewhere
my ($host, $port) = maybe_start_server(static_dir => 't/htdocs');
ok $port, "Got host: $host and port: $port";

my $client = RPC::ExtDirect::Client->new( host => $host, port => $port,);

my @data = $client->poll();

is scalar @data, 0, "No events returned";

