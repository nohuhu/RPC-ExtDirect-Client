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
no  warnings 'uninitialized';

use Test::More tests => 11;

use lib 't/lib';
use util;

BEGIN { use_ok 'RPC::ExtDirect::Client' };

# Port number as parameter means there's server listening elsewhere
my $port = shift @ARGV || start_server(static_dir => 't/htdocs');
ok $port, 'Got port';

my $cclass = 'RPC::ExtDirect::Client';

my $client = eval { $cclass->new(host => 'localhost', port => $port) };

is     $@,      '',      "Didn't die";
ok     $client,          'Got client object';
isa_ok $client, $cclass, 'Right object, too,';

# Try calling nonexistent method

my $data = eval {
    $client->call( action => 'test', method => 'nonexistent' )
};

is   $@,        '',            "Nonexistent didn't die";
like ref $data, qr/Exception/, 'Nonexistent result is exception';
like $data,     qr/not found/, 'Nonexistent description matches';

# Try calling method that dies

$data = eval {
    $client->call( action => 'test', method => 'dies' )
};

is   $@,        '',             "Method call didn't die";
like ref $data, qr/Exception/,  'Dying method result is exception';
like $data,     qr/Whoa/,       'Dying method description matches';
