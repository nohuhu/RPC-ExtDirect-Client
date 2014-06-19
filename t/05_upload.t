# Test Ext.Direct form POST/upload request handling

package test::class;

use strict;

use RPC::ExtDirect Action => 'test';

sub handle_upload : ExtDirect(formHandler) {
    my ($class, %arg) = @_;

    my @uploads = @{ $arg{file_uploads} };

    my @result
        = map { { name => $_->{basename}, size => $_->{size} } }
              @uploads;

    return \@result;
}

package main;

use strict;
use warnings;

use File::Temp 'tempfile';
use File::Spec;

use Test::More tests => 8;

use RPC::ExtDirect::Test::Util;
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

# Generate some files with some random data
my @files = map { gen_file() } 0 .. int rand 9;

my $exp = [
    map {
        { name => (File::Spec->splitpath($_))[2], size => (stat $_)[7] }
    }
    @files
];

my $data = eval {
    $client->submit(
        action => 'test',
        method => 'handle_upload',
        arg    => {},
        upload => \@files,
    )
};

is      $@,        '',            "Upload didn't die";
unlike  ref $data, qr/Exception/, "Upload result not an exception";
is_deep $data,     $exp,          "Upload data match";

sub gen_file {
    my ($fh, $filename) = tempfile;

    print $fh int rand 1000 for 0 .. int rand 1000;

    return $filename;
}

