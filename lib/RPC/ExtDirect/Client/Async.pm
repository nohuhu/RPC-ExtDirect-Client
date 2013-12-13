package RPC::ExtDirect::Client::Async;

use strict;
use warnings;
no  warnings 'uninitialized';

use Carp;
use File::Spec;
use HTTP::Tiny;
use AnyEvent::HTTP;

use RPC::ExtDirect::Util::Accessor;
use RPC::ExtDirect::Config;
use RPC::ExtDirect::API;
use RPC::ExtDirect;
use RPC::ExtDirect::Client;

use base 'RPC::ExtDirect::Client';

#
# This module is not compatible with RPC::ExtDirect < 3.0
#

croak __PACKAGE__." requires RPC::ExtDirect 3.0+"
    if $RPC::ExtDirect::VERSION < 3.0;

### PACKAGE GLOBAL VARIABLE ###
#
# Module version
#

our $VERSION = '3.00_01';

### PUBLIC CLASS METHOD (CONSTRUCTOR) ###
#
# Instantiate a new Async client, connect to the specified server
# and initialize the Ext.Direct API. Optionally fire a callback
# when that's done
#

sub new {
    my ($class, %params) = @_;
    
    my $api_cb = delete $params{api_cb};
    
    my $self = $class->SUPER::new(%params);
    
    $self->api_cb($api_cb);
    
    return $self;
}

### PUBLIC INSTANCE METHOD ###
#
# Call specified Action's Method asynchronously
#

sub call_async { shift->async_request('call', @_) }

### PUBLIC INSTANCE METHOD ###
#
# Submit a form to specified Action's Method asynchronously
#

sub submit_async { shift->async_request('form', @_) }

### PUBLIC INSTANCE METHOD ###
#
# Upload a file using POST form. Same as submit()
#

*upload_async = *submit_async;

### PUBLIC INSTANCE METHOD ###
#
# Poll server for events asynchronously
#

sub poll_async { shift->async_request('poll', @_) }

### PUBLIC INSTANCE METHOD ###
#
# Run a specified request type asynchronously
#

sub async_request {
    my $self = shift;
    my $type = shift;
    
    my $tr_class    = $self->transaction_class;
    my $transaction = $tr_class->new(@_);
    
    #
    # We try to avoid action-at-a-distance here, so we will
    # call all the stuff that could die() up front,
    # to pass on the exception to the caller immediately
    # rather than blowing up later on.
    #
    eval { $self->_async_request($type, $transaction) };
    
    if ($@) { croak 'ARRAY' eq ref($@) ? $@->[0] : $@ };
    
    # Stay positive
    return 1;
}

### PUBLIC INSTANCE METHOD ###
#
# Return the name of the Transaction class
#

sub transaction_class { 'RPC::ExtDirect::Client::Async::Transaction' }

### PUBLIC INSTANCE METHOD ###
#
# Read-write accessor
#

RPC::ExtDirect::Util::Accessor->mk_accessor(
    simple => [qw/ api_ready api_cb request_queue /],
);

############## PRIVATE METHODS BELOW ##############

### PRIVATE INSTANCE METHOD ###
#
# Throw an exception using the condvar passed to the constructor,
# or just set an error so the next async request would die() with it
#

sub _throw {
    my ($self, $ex) = @_;
    
    my $cv = $self->cv;
    
    if ($cv) {
        $cv->croak($ex);
    }
    else {
        push @{$self->{exceptions}}, $ex;
    }
}

### PRIVATE INSTANCE METHOD ###
#
# Initialize API declaration
#

sub _init_api {
    my ($self) = @_;
    
    # We want to be truly asynchronous, so instead of
    # blocking on API retrieval, we create a request queue
    # and return immediately. If any call/form/poll requests happen
    # before we've got the API result back, we push them in the queue
    # and wait for the API to arrive, then re-run the requests.
    # After the API declaration has been retrieved, all subsequent
    # requests run without queuing.
    $self->request_queue([]);
    
    $self->_get_api(sub {
        my ($api_js) = @_;
        
        $self->_import_api($api_js);
        $self->api_ready(1);
        
        my $queue = $self->request_queue;
        delete $self->{request_queue};  # A bit quirky
        
        $_->() for @$queue;
        
        my $cv = $self->cv;
    
        $cv->end if $cv;
        
        $self->api_cb->($self) if $self->api_cb;
    });
}

### PRIVATE INSTANCE METHOD ###
#
# Receive API declaration from specified server,
# parse it and return Client::API object
#

sub _get_api {
    my ($self, $cb) = @_;

    my $cv     = $self->cv;
    my $uri    = $self->_get_uri('api');
    my $params = $self->{http_params};

    # Run additional checks before firing curried callback
    my $api_cb = sub {
        my ($content, $headers) = @_;
        
        $self->_throw("Can't download API declaration: $headers->{Status}\n")
            unless $headers->{Success} ne '200';

        $self->_throw("Empty API declaration\n")
            unless length $content;
        
        $cb->($content);
    };
    
    $cv->begin if $cv;

    AnyEvent::HTTP::http_request(
        GET => $uri,
        %$params,
        $api_cb,
    );
}

### PRIVATE INSTANCE METHOD ###
#
# Run asynchronous request(s) if the API is already available;
# queue for later if not
#

sub _run_request {
    my $self = shift;
    
    if ( $self->api_ready ) {
        $_->() for @_;
    }
    else {
        $self->_queue_request(@_);
    }
}

### PRIVATE INSTANCE METHOD ###
#
# Queue asynchronous request(s)
#

sub _queue_request {
    my $self = shift;
    
    my $queue = $self->{request_queue};
    
    push @$queue, @_;
}

### PRIVATE INSTANCE METHOD ###
#
# Make an HTTP request in asynchronous fashion
#

sub _async_request {
    my ($self, $type, $transaction) = @_;
    
    $self->_run_request(sub {
        my $prepare = "_prepare_${type}_request";
        my $method  = $type eq 'poll' ? 'GET' : 'POST';
    
        $transaction->start;
        
        my ($uri, $request_content, $http_params, $request_options)
            = eval { $self->$prepare($transaction) };
        
        $transaction->finish('ARRAY' eq ref $@ ? $@->[0] : $@, !1)
            if $@;
    
        my $request_headers = $request_options->{headers};
    
        # TODO Handle errors
        AnyEvent::HTTP::http_request(
            $method, $uri,
            headers => $request_headers,
            body    => $request_content,
            %$http_params,
            $self->_curry_response_cb($type, $transaction),
        )
    });
}

### PRIVATE INSTANCE METHOD ###
#
# Parse cookies if provided, creating Cookie header
#

sub _parse_cookies {
    my ($self, $to, $from) = @_;
    
    $self->SUPER::_parse_cookies($to, $from);
    
    # This results in Cookie header being a hashref,
    # but we need a string for AnyEvent::HTTP
    if ( $to->{headers} && (my $cookies = $to->{headers}->{Cookie}) ) {
        $to->{headers}->{Cookie} = join '; ', @$cookies;
    }
}

### PRIVATE INSTANCE METHOD ###
#
# Generate result handling callback
#

sub _curry_response_cb {
    my ($self, $type, $transaction) = @_;
    
    return sub {
        my ($data, $headers) = @_;
        
        my $status  = $headers->{Status};
        my $success = $status eq '200';
        
        my $handler  = "_handle_${type}_response";
        my $response = eval {
            $self->$handler({
                status  => $status,
                success => $success,
                content => $data,
            })
        } if $success;
        
        # We're only interested in the data, but anything goes
        my $result = 'ARRAY' eq ref($@)       ? $@->[0]
                   : $@                       ? $@
                   : !$success                ? $headers->{Reason}
                   : 'poll' eq $type          ? $response
                   : 'HASH' eq ref($response) ? $response->{result}
                   :                            $response
                   ;
        
        $transaction->finish($result, !$@ && $success);
    };
}

package
    RPC::ExtDirect::Client::Async::Transaction;

use Carp;

use base 'RPC::ExtDirect::Client::Transaction';

my @fields = qw/ cb cv actual_arg fields /;

sub new {
    my ($class, %params) = @_;
    
    croak "Callback subroutine is required"
        unless 'CODE' eq ref $params{cb};
    
    my %self_params = map { $_ => delete $params{$_} } @fields;
    
    my $self = $class->SUPER::new(%params);
    
    @$self{ keys %self_params } = values %self_params;
    
    return $self;
}

sub start {
    my ($self) = @_;
    
    my $cv = $self->cv;
    
    $cv->begin if $cv;
}

sub finish {
    my ($self, $result, $success) = @_;
    
    my $cb = $self->cb;
    my $cv = $self->cv;
    
    $cb->($result, $success) if $cb;
    $cv->end                 if $cv;
}

RPC::ExtDirect::Util::Accessor->mk_accessors(
    simple => [qw/ cb cv /],
);

1;

__END__

=pod

=head1 NAME

RPC::ExtDirect::Client - Ext.Direct client in Perl

=head1 SYNOPSIS

 use RPC::ExtDirect::Client;
 
 my $client = RPC::ExtDirect::Client->new(host => 'localhost');
 my $result = $client->call(
    action  => 'Action',
    method  => 'Method',
    arg     => [ 'foo', 'bar' ],
    cookies => { foo => 'bar' },
 );

=head1 DESCRIPTION

This module implements Ext.Direct client in pure Perl. Its main purpose
is to be used for testing server side Ext.Direct classes.

RPC::ExtDirect::Client uses HTTP::Tiny as transport.

=head1 METHODS

=over 4

=item new(%params)

Creates a new client instance. Constructor accepts the following arguments:

=over 8

=item api_path

URI for Ext.Direct API published by server. Default: '/api'.

=item router_path

URI for Ext.Direct remoting requests. Default: '/router'.

=item poll_path

URI for Ext.Direct events. Default: '/events'.

=item remoting_var

JavaScript variable name used to assign Ext.Direct remoting API object to.
Default: 'Ext.app.REMOTING_API'.

=item polling_var

JavaScript variable name used to assign Ext.Direct polling API object to.
Default: 'Ext.app.POLLING_API'.

=item cookies

Cookies to set when calling server side; can be either HTTP::Cookies object
or a hashref containing key-value pairs. Setting this in constructor will
pass the same cookies to all subsequent client calls.

=item %other

All other arguments are passed to HTTP::Tiny constructor. See L<HTTP::Tiny>
for more detail.

=back

=item get_api

Returns L<RPC::ExtDirect::Client::API> object with Ext.Direct API
declaration published by the server.

=item call(%params)

Calls Ext.Direct remoting method. Arguments are:

=over 8

=item action

Ext.Direct Action (class) name

=item method

Ext.Direct Method name to call

=item arg

Ext.Direct Method arguments; use arrayref for methods that accept ordered
parameters or hashref for named parameters.

=item cookies

Same as with constructor, but sets cookies for this particular call only.

=back

Returns either call Result or Exception.

=item submit

Submits a form request to formHandler method. Arguments should be:

=over 8

=item action

Ext.Direct Action (class) name

=item method

Ext.Direct Method name

=item arg

Method arguments; for formHandlers it should always be a hashref.

=item upload

Arrayref of file names to upload.

=item cookies

Same as with constructor, but sets cookies for this particular call only.

=back

Returns either call Result or Exception.

=item upload

Same as C<submit>.

=item poll

Polls server side for events, returns event data.

=over 8

=item cookies

Same as with constructor, but sets cookies for this particular call only.

=back

=back

=head1 DEPENDENCIES

RPC::ExtDirect::Client depends on the following modules:
L<HTTP::Tiny>, L<JSON>, and L<RPC::ExtDirect::Server> for testing.

=head1 SEE ALSO

For more information on using Ext.Direct with Perl, see L<RPC::ExtDirect>.
L<RPC::ExtDirect::Server> can be used to provide lightweight drop-in for
production environment to run Ext.Direct tests.

=head1 BUGS AND LIMITATIONS

There are no known bugs in this module. Use github tracker to report bugs
(the best way) or just drop me an e-mail. Patches are welcome.

=head1 AUTHOR

Alexander Tokarev E<lt>tokarev@cpan.orgE<gt>

=head1 ACKNOWLEDGEMENTS

I would like to thank IntelliSurvey, Inc for sponsoring my work
on this module.

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2012-2013 Alexander Tokarev.

This module is free software; you can redistribute it and/or modify it
under the same terms as Perl itself. See L<perlartistic>.

=cut

