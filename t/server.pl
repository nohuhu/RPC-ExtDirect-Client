#!/usr/bin/perl

# This script can be used for manual HTTP server testing in case
# something goes awry

use common::sense;

use RPC::ExtDirect::Server;

my $server = RPC::ExtDirect::Server->new(static_dir => 't/htdocs');
my $port   = $server->port;

say "Listening on port $port";

$server->run();

