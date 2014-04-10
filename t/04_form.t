# Test Ext.Direct form POST request handling

package test::class;

use strict;

use RPC::ExtDirect Action => 'test';

sub handle_form : ExtDirect(formHandler) {
    my ($class, %arg) = @_;

    delete $arg{_env};

    my @fields = grep { !/^file_uploads/ } keys %arg;

    my %result;
    @result{ @fields } = @arg{ @fields };

    return \%result;
}

package main;

use strict;
use warnings;
no  warnings 'uninitialized';

use Test::More tests => 8;

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

my $fields = { foo => 'qux', bar => 'baz' };

my $data = eval {
    $client->submit( action => 'test', method => 'handle_form',
                     arg    => $fields
    )
};

is        $@,        '',            "Form didn't die";
unlike    ref $data, qr/Exception/, "Form result not an exception";
is_deeply $data,     $fields,       "Form data match";

