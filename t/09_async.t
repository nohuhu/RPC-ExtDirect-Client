# Test asynchronous Ext.Direct request handling

package test::class;

use strict;

use RPC::ExtDirect Action => 'test';
use RPC::ExtDirect::Event;

sub ordered : ExtDirect(3) {
    my $class = shift;

    return [ splice @_, 0, 3 ];
}

sub named : ExtDirect(params => ['arg1', 'arg2', 'arg3']) {
    my ($class, %params) = @_;

    return {
        arg1 => $params{arg1}, 
        arg2 => $params{arg2},
        arg3 => $params{arg3},
    };
}

sub handle_form : ExtDirect(formHandler) {
    my ($class, %arg) = @_;

    delete $arg{_env};

    my @fields = grep { !/^file_uploads/ } keys %arg;

    my %result;
    @result{ @fields } = @arg{ @fields };

    return \%result;
}

sub handle_upload : ExtDirect(formHandler) {
    my ($class, %arg) = @_;

    my @uploads = @{ $arg{file_uploads} };

    my @result
        = map { { name => $_->{basename}, size => $_->{size} } }
              @uploads;

    return \@result;
}

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

use File::Temp 'tempfile';
use Test::More;

eval {
    require AnyEvent::HTTP;
};

if ( $@ ) {
    plan skip_all => "AnyEvent::HTTP not present";
}
else {
    require RPC::ExtDirect::Client::Async;

    plan tests => 15;
}

use lib 't/lib';
use util;

# Port number as parameter means there's server listening elsewhere
my $port = shift @ARGV || start_server(static_dir => 't/htdocs');
ok $port, 'Got port';

my $cclass = 'RPC::ExtDirect::Client::Async';

my $cv = AnyEvent->condvar;

my %client_params = (
    host        => 'localhost',
    port        => $port,
    api_path    => '/api',
    cv          => $cv,
);

my $client = eval { $cclass->new( %client_params ) };

is     $@,      '',      "Didn't die";
ok     $client,          'Got client object';
isa_ok $client, $cclass, 'Right object, too,';

my $arg_ordered = [ qw(foo bar qux mumble splurge) ];
my $exp_ordered = [ qw(foo bar qux) ];
my $arg_named = {
    arg1 => 'foo', arg2 => 'bar', arg3 => 'qux', arg4 => 'mumble'
};
my $exp_named = { arg1 => 'foo', arg2 => 'bar', arg3 => 'qux' };

my $timeout = 1;

# Ordered method call

$cv->begin;

$client->call_async(
    action => 'test',
    method => 'ordered',
    arg    => $arg_ordered,
    cb     => sub {
        my $data = shift;

        unlike ref $data, qr/Exception/, 'Ordered not exception';
        is_deeply $data, $exp_ordered, 'Ordered return data matches';

        $cv->end;
    },
    timeout => $timeout,
);

# Named method call

$cv->begin;

$client->call_async(
    action => 'test',
    method => 'named',
    arg    => $arg_named,
    cb     => sub {
        my $data = shift;

        unlike ref $data, qr/Exception/, 'Named not exception';
        is_deeply $data, $exp_named, 'Named return data matches';

        $cv->end;
    },
    timeout => $timeout,
);

# Form submit

$cv->begin;

my $fields = { foo => 'qux', bar => 'baz' };

$client->submit_async(
    action => 'test',
    method => 'handle_form',
    arg    => $fields,
    cb     => sub {
        my $data = shift;

        unlike ref $data, qr/Exception/, "Form not exception";
        is_deeply $data, $fields, "Form data match";

        $cv->end;
    },
);

# Form submit with file upload

# Generate some files with some random data
my @files = map { gen_file() } 0 .. int rand 9;

my $exp_upload = [
    map {
        { name => (File::Spec->splitpath($_))[2], size => (stat $_)[7] }
    }
    @files
];

$cv->begin;

$client->submit_async(
    action => 'test',
    method => 'handle_upload',
    upload => \@files,
    cb     => sub {
        my $data = shift;

        unlike ref $data, qr/Exception/, "Upload not exception";
        is_deeply $data, $exp_upload, "Upload data match";

        $cv->end;
    },
);

# Asynchronous polling

my $events = $test::class::EVENTS;

my $i = 0;

for my $test ( @$events ) {
    my $exp = { name => 'foo', data => $test };

    my $cb = sub {
        my $data = shift;

        is_deeply $data, $exp, "Poll $i data matches";

        $cv->end;
    };

    $cv->begin;

    $client->poll_async( cb => $cb );

    $i++;
}

$cv->recv;

sub gen_file {
    my ($fh, $filename) = tempfile;

    print $fh int rand 1000 for 0 .. int rand 1000;

    return $filename;
}

