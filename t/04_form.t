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

use lib 't/lib';
use util;

BEGIN { use_ok 'RPC::ExtDirect::Client' };

# Port number as parameter means there's server listening elsewhere
my $port = shift @ARGV || start_server(static_dir => 't/htdocs');
ok $port, 'Got port';

my $cclass = 'RPC::ExtDirect::Client';

my $client = eval {
    $cclass->new(
        host        => 'localhost',
        port        => $port,
        api_path    => '/api',
        router_path => '/router',
    )
};

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

