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
no  warnings 'uninitialized';

use File::Temp 'tempfile';
use File::Spec;

use Test::More tests => 8;

use lib 't/lib';
use util;

BEGIN { use_ok 'RPC::ExtDirect::Client' };

# Port number as parameter means there's server listening elsewhere
my $port = shift @ARGV // start_server(static_dir => 't/htdocs');
ok $port, 'Got port';

my $cclass = 'RPC::ExtDirect::Client';

my $client = eval { $cclass->new(host => 'localhost', port => $port) };

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
    $client->submit( action => 'test', method => 'handle_upload',
                     upload => \@files
    )
};

is        $@,        '',            "Upload didn't die";
unlike    ref $data, qr/Exception/, "Upload result not an exception";
is_deeply $data,     $exp,          "Upload data match";

exit 0;

sub gen_file {
    my ($fh, $filename) = tempfile;

    print $fh int rand 1000 for 0 .. int rand 1000;

    return $filename;
}

