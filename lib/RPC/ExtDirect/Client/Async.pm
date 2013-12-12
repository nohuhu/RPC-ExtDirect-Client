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

croak "RPC::ExtDirect::Client requires RPC::ExtDirect 3.0+"
    if $RPC::ExtDirect::VERSION < 3.0;

### PUBLIC CLASS METHOD (CONSTRUCTOR) ###
#
# Instantiate a new Client, connect to the specified server
# and initialize Ext.Direct API
#

sub new {
    my ($class, %params) = @_;
    
    # It is a good style to throw exceptions instead of returning errors,
    # but in asynchronous code it's rather hard to do - you can't just
    # die() when an error happened. Instead, we accept optional `cv`
    # parameter that should be a live AnyEvent::CondVar that we will
    # croak() upon.
    # Besides croaking, this cv will be signaled when API becomes available,
    # so that the caller can wait for it.
    my $self = $class->SUPER::new(%params);
    
    $self->{exceptions} = [];
    
    return $self;
}

### PUBLIC INSTANCE METHOD ###
#
# Call specified Action's Method asynchronously
#

sub call_async {
    my ($self, %params) = @_;
    
    my $action = delete $params{action};
    my $method = delete $params{method};
    my $arg    = delete $params{arg};
    my $cb     = delete $params{cb};
    my $cv     = delete $params{cv};
    
    $self->_throw("Callback subroutine is required in call_async")
        unless 'CODE' eq ref $cb;
    
    my $exceptions = $self->{exceptions};
    $self->_throw(join "\n", @$exceptions, "\n") if @$exceptions;
    
    my $call_cb = sub {
        my $actual_arg  = $self->_normalize_arg($action, $method, $arg);
        my $response_cb = $self->_curry_response_cb($cb);
    
        $self->_call_async($action, $method, $actual_arg, $response_cb, \%params);
    };
    
    if ($self->api_ready) {
        $call_cb->();
    }
    else {
        $self->_queue_request($call_cb);
    }
    
    return 1;
}

### PUBLIC INSTANCE METHOD ###
#
# Submit a form to specified Action's Method asynchronously
#

sub submit_async {
    my ($self, %params) = @_;
    
    my $cb = delete $params{cb};
    
    $self->_throw("Callback subroutine is required in submit_async")
        unless 'CODE' eq ref $cb;
    
    my $exceptions = $self->{exceptions};
    $self->_throw(join "\n", @$exceptions, "\n") if @$exceptions;
    
    my $submit_cb = sub {
        my $response_cb = $self->_curry_response_cb($cb);
    
        $self->_call_form_async(%params, cb => $response_cb);
    };
    
    if ($self->api_ready) {
        $submit_cb->();
    }
    else {
        $self->_queue_request($submit_cb);
    };
    
    return 1;
}

### PUBLIC INSTANCE METHOD ###
#
# Upload a file using POST form. Same as submit()
#

*upload_async = *submit_async;

### PUBLIC INSTANCE METHOD ###
#
# Poll server for events asynchronously
#

sub poll_async {
    my ($self, %params) = @_;
    
    my $cb = delete $params{cb};
    
    $self->_throw("Callback subroutine is required in poll_async")
        unless 'CODE' eq ref $cb;
    
    my $exceptions = $self->{exceptions};
    $self->_throw(join "\n", @$exceptions, "\n") if @$exceptions;
    
    my $poll_cb = sub {
        $self->_call_poll_async(%params, cb => $cb);
    };
    
    if ($self->api_ready) {
        $poll_cb->();
    }
    else {
        $self->_queue_request($poll_cb);
    };
    
    return 1;
}

### PUBLIC INSTANCE METHOD ###
#
# Read-write accessor
#

RPC::ExtDirect::Util::Accessor->mk_accessor(
    simple => [qw/ api_ready /],
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
    $self->{request_queue} = [];
    
    my $cv = $self->cv;
    
    $self->_get_api(sub {
        my ($api_js) = @_;
        
        $self->_import_api($api_js);
        $self->api_ready(1);
        
        my $queue = $self->{request_queue};
        delete $self->{request_queue};
        
        $_->() for @$queue;
        
        $cv->end if 'AnyEvent::CondVar' eq ref $cv;
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
    
    $cv->begin if 'AnyEvent::CondVar' eq ref $cv;

    AnyEvent::HTTP::http_request(
        GET => $uri,
        %$params,
        $api_cb,
    );
}

### PRIVATE INSTANCE METHOD ###
#
# Queue asynchronous request
#

sub _queue_request {
    my ($self, $req) = @_;
    
    my $queue = $self->{request_queue};
    
    push @$queue, $req;
}

### PRIVATE INSTANCE METHOD ###
#
# Call Action's Method in asynchronous fashion
#

sub _call_async {
    my ($self, $action, $method, $actual_arg, $response_cb, $p) = @_;
    
    my $uri       = $self->_get_uri('remoting');
    my $params    = $self->{http_params} || {};
    my $post_body = $self->_encode_post_body($action, $method, $actual_arg);
    
    @$params{ keys %$p } = values %$p if $p;
    
    if ( $self->cookies && !$params->{cookies} ) {
        $params->{cookies} = $self->cookies;
    }

    my $options = {};
    
    $self->_parse_cookies($options, $params);
    
    my $headers = $options->{headers} || {};
    $headers->{'Content-Type'} = 'application/octet-stream';
    
    # TODO Handle errors
    my $result_cb = $self->_curry_result_cb($response_cb);
    
    AnyEvent::HTTP::http_request(
        POST    => $uri,
        headers => $headers,
        body    => $post_body,
        %$params,
        $result_cb,
    );
}

### PRIVATE PACKAGE SUBROUTINE ###
#
# Cleanse Response
#

sub _cleanse_response {
    my ($resp) = @_;
    
    # We're only interested in the data
    return 'HASH' eq ref $resp ? $resp->{result} : $resp;
}

### PRIVATE INSTANCE METHOD ###
#
# Call Action's Method by submitting a form in asynchronous fashion
#

sub _call_form_async {
    my ($self, %params) = @_;
    
    my $resp_cb = delete $params{cb};
    my $upload  = $params{upload};
    my $uri     = $self->_get_uri('remoting');
    my $fields  = $self->_formalize_arg(%params);
    
    my $ct = $upload ? 'multipart/form-data; boundary='.$self->_get_boundary
           :           'application/x-www-form-urlencoded; charset=utf-8'
           ;
    my $form_body = $upload ? $self->_www_form_multipart($fields, $upload)
                  :           $self->_www_form_urlencode($fields)
                  ;

    my $options = {};
    my $p = $self->{http_params} || {};
    @$p{ keys %params } = values %params;
    
    if ( $self->cookies && !$p->{cookies} ) {
        $p->{cookies} = $self->cookies;
    }

    $self->_parse_cookies($options, $p);
    
    my $headers = $options->{headers} || {};
    $headers->{'Content-Type'} = $ct;
    
    my $result_cb = $self->_curry_result_cb($resp_cb);
    
    AnyEvent::HTTP::http_request(
        POST    => $uri,
        headers => $headers,
        body    => $form_body,
        %$p,
        $result_cb,
    );
}

### PRIVATE INSTANCE METHOD ###
#
# Call polling provider in asynchronous fashion
#

sub _call_poll_async {
    my ($self, %params) = @_;
    
    my $resp_cb = delete $params{cb};
    my $uri     = $self->_get_uri('polling');
    
    my $options = {};
    
    my $p = $self->{http_params} || {};
    @$p{ keys %params } = values %params;

    if ( $self->cookies && !$p->{cookies} ) {
        $p->{cookies} = $self->cookies;
    }

    $self->_parse_cookies($options, $p);

    my $result_cb = $self->_curry_result_cb($resp_cb, 1);
    
    AnyEvent::HTTP::http_request(
        GET => $uri,
        %$p,
        $result_cb,
    );
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
# Generate response handling callback
#

sub _curry_response_cb {
    my ($self, $cb) = @_;
    
    return sub {
        my ($response) = @_;
        
        my $result = _cleanse_response($response);
        
        $cb->($result);
    };
}

### PRIVATE INSTANCE METHOD ###
#
# Generate result handling callback
#

sub _curry_result_cb {
    my ($self, $cb, $is_poll) = @_;
    
    my $handler = $is_poll ? '_handle_poll_response'
                :            '_handle_response'
                ;
    
    return sub {
        my ($data, $headers) = @_;
        
        $DB::single = 1;
        
        my $status  = $headers->{Status};
        my $success = $status eq '200';
        
        my $result = $self->$handler({
            status  => $status,
            success => $status eq '200',
            content => $data,
        });
        
        $cb->($result, $success);
    };
}

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

