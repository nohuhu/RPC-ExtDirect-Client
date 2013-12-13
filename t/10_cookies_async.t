# Test cookie handling w/ asynchronous calls

package test::class;

use strict;

use RPC::ExtDirect  Action => 'test',
                    before => \&before_hook,
                    ;
use RPC::ExtDirect::Event;
use Test::More;

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

# !!! This is a temporary stop gap solution !!!
# Get rid of the Coro dependency before releasing to CPAN!
use Coro;

use Test::More;

eval {
    require AnyEvent::HTTP;
};

if ( $@ ) {
    plan skip_all => "AnyEvent::HTTP not present";
}
else {
    require RPC::ExtDirect::Client::Async;

    plan tests => 7;
};

use lib 't/lib';
use util;

# Port number as parameter means there's server listening elsewhere
my $port = shift @ARGV || start_server(static_dir => 't/htdocs');
ok $port, 'Got port';

# Give the server a chance to start
sleep 1;

my %client_params = (
    host         => '127.0.0.1',
    port         => $port,
    api_path     => '/api',
    timeout      => 10,
);

my $tests = eval do { local $/; <DATA>; }       ## no critic
    or die "Can't eval DATA: '$@'";

my $cv = AnyEvent->condvar;

run_tests(%$_) for @$tests;

sub run_tests {
    my %params = @_;

    my $client_params  = $params{client_params};
    my $cookie_jar     = $params{cookie_jar};
    my $desc           = $params{desc};
    my $expected_data  = $params{expected_data};
    my $expected_event = { name => 'cookies', data => $expected_data };

    my $api_cv = AnyEvent->condvar;

    $api_cv->begin;

    my $client = RPC::ExtDirect::Client::Async->new(
        @$client_params,
        api_cb => sub {
            $api_cv->end;
        },
    );

    $api_cv->recv;

    $client->call_async(
        $cookie_jar ? (cookies => $cookie_jar) : (),
        action  => 'test',
        method  => 'ordered',
        arg     => [],
        cv      => $cv,
        cb      => sub {
            my $data = shift;

            is_deeply $data, $expected_data, "Ordered with $desc"
                or diag explain $data;
        },
    );

    $client->submit_async(
        $cookie_jar ? (cookies => $cookie_jar) : (),
        action  => 'test',
        method  => 'form',
        cv      => $cv,
        cb      => sub {
            my $data = shift;

            is_deeply $data, $expected_data, "Form handler with $desc"
                or diag explain $data;
        },
    );

    $client->poll_async(
        $cookie_jar ? (cookies => $cookie_jar) : (),
        cv => $cv,
        cb => sub {
            my $event = shift;

            is_deeply $event, $expected_event, "Poll handler with $desc"
                or diag explain $event;
        },
    );
}

$cv->recv;

done_testing;


__DATA__

[
    {
        desc           => 'raw cookies w/ new',
        expected_data  => { foo => 'bar', bar => 'baz', },
        client_params  => [
            %client_params,
            cookies => { foo => 'bar', bar => 'baz', },
        ],
    },
    {
        desc           => 'raw cookies w/ call',
        cookie_jar     => {
            bar => 'foo',
            baz => 'bar',
        },
        expected_data  => {
            bar => 'foo',
            baz => 'bar',
        },
        client_params  => [ %client_params ],
    },
]
