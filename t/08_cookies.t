# Test cookie handling

package test::class;

use strict;

use RPC::ExtDirect  Action => 'test',
                    before => \&before_hook,
                    ;
use RPC::ExtDirect::Event;

our %cookies;

sub before_hook {
    my ($class, %params) = @_;

    my $env = $params{env};

    %cookies = map { $_ => $env->cookie($_) } $env->cookie;

    return 1;
}

sub ordered : ExtDirect(0) {
    my $ret  = { %cookies };
    %cookies = ();

    return $ret;
}

sub form : ExtDirect(formHandler) {
    my $ret  = { %cookies };
    %cookies = ();

    return $ret;
}

sub poll : ExtDirect(pollHandler) {
    return RPC::ExtDirect::Event->new(
        'cookies',
        { %cookies },
    );
}

package main;

use strict;
use warnings;
no  warnings 'uninitialized';

use Test::More tests => 13;

use RPC::ExtDirect::Client;

use lib 't/lib';
use util;

# Port number as parameter means there's server listening elsewhere
my $port = shift @ARGV || start_server(static_dir => 't/htdocs');
ok $port, 'Got port';

my $expected_data = {
    foo => 'bar',
    bar => 'baz',
};

my $expected_event = {
    name => 'cookies',
    data => $expected_data,
};

my $client = RPC::ExtDirect::Client->new(
    host        => 'localhost',
    port        => $port,
    cookies     => $expected_data,
    api_path    => '/api',
    router_path => '/router',
    poll_path   => '/events',
);

run_tests(
    client         => $client,
    cookie_jar     => undef,
    desc           => 'raw cookies w/ new',
    expected_data  => $expected_data,
    expected_event => $expected_event,
);

$client = RPC::ExtDirect::Client->new(
    host        => 'localhost',
    port        => $port,
    api_path    => '/api',
    router_path => '/router',
    poll_path   => '/events',
);

$expected_data = {
    bar => 'foo',
    baz => 'bar',
};

$expected_event = {
    name => 'cookies',
    data => $expected_data,
};

run_tests(
    client         => $client,
    cookie_jar     => $expected_data,
    desc           => 'raw cookies override',
    expected_data  => $expected_data,
    expected_event => $expected_event,
);

$expected_data = {
    qux   => 'frob',
    mymse => 'splurge',
};

$expected_event = {
    name => 'cookies',
    data => $expected_data,
};

run_tests(
    client         => $client,
    cookie_jar     => $expected_data,
    desc           => 'raw cookies per each call',
    expected_data  => $expected_data,
    expected_event => $expected_event,
);

SKIP: {
    skip "Need HTTP::Cookies", 3 unless eval "require HTTP::Cookies";

    my $cookie_jar = HTTP::Cookies->new;

    $cookie_jar->set_cookie(1, 'foo', 'bar', '/', '');
    $cookie_jar->set_cookie(1, 'bar', 'baz', '/', '');

    my $expected_data = {
        foo => 'bar',
        bar => 'baz',
    };

    my $expected_event = {
        name => 'cookies',
        data => $expected_data,
    };

    $client = RPC::ExtDirect::Client->new(
        host        => 'localhost',
        port        => $port,
        api_path    => '/api',
        router_path => '/router',
        poll_path   => '/events',
    );

    run_tests(
        client         => $client,
        cookie_jar     => $cookie_jar,
        desc           => 'HTTP::Cookies',
        expected_data  => $expected_data,
        expected_event => $expected_event,
    );
}

sub run_tests {
    my %params = @_;

    my $client         = $params{client};
    my $cookie_jar     = $params{cookie_jar};
    my $desc           = $params{desc};
    my $expected_data  = $params{expected_data};
    my $expected_event = $params{expected_event};

    my $data = $client->call(
        action  => 'test',
        method  => 'ordered',
        arg     => [],
        $cookie_jar ? (cookies => $cookie_jar) : (),
    );

    is_deeply $data, $expected_data, "Ordered with $desc"
        or diag explain $data;

    $data = $client->submit(
        action  => 'test',
        method  => 'form',
        $cookie_jar ? (cookies => $cookie_jar) : (),
    );

    is_deeply $data, $expected_data, "Form handler with $desc"
        or diag explain $data;

    my $event = $client->poll(
        $cookie_jar ? (cookies => $cookie_jar) : (),
    );

    is_deeply $event, $expected_event, "Poll handler with $desc"
        or diag explain $data;
}

