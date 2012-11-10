package RPC::ExtDirect::Client;

use strict;
use warnings;
no  warnings 'uninitialized';

use File::Spec;
use HTTP::Tiny;

use RPC::ExtDirect::Client::API;

### VERSION ###

our $VERSION = '0.2';

### PUBLIC CLASS METHOD (CONSTRUCTOR) ###
#
# Instantiate a new Client, connect to specified server
# and initialize Ext.Direct API
#

sub new {
    my ($class, %params) = @_;

    my @our_params = qw(
        host port api_path router_path poll_path
        remoting_var polling_var
    );

    my $self = bless { tid => 0 }, $class;

    @$self{ @our_params } = delete @params{ @our_params };

    # Reasonable defaults
    $self->{api_path}     //= '/api';
    $self->{router_path}  //= '/router';
    $self->{poll_path}    //= '/events';
    $self->{remoting_var} //= 'Ext.app.REMOTING_API';
    $self->{polling_var}  //= 'Ext.app.POLLING_API';

    # The rest of parameters apply to transport
    $self->{http_params} = { %params };

    my $api_js = $self->_get_api();
    $self->_import_api($api_js);

    return $self;
}

### PUBLIC INSTANCE METHOD ###
#
# Call specified Action's Method
#

sub call {
    my ($self, %params) = @_;

    my $action = delete $params{action};
    my $method = delete $params{method};
    my $arg    = delete $params{arg};

    my $actual_arg = $self->_normalize_arg($action, $method, $arg);

    my $response = $self->_call_sync($action, $method, $actual_arg, \%params);

    # We're only interested in the data
    return ref($response) =~ /Exception/ ? $response
         :                                 $response->{result}
         ;
}

### PUBLIC INSTANCE METHOD ###
#
# Submit a form to specified Action's Method
#

sub submit {
    my ($self, %params) = @_;

    # Form calls do not support batching
    my $response = $self->_call_form(%params);

    # We're only interested in the data
    return ref($response) =~ /Exception/ ? $response
         :                                 $response->{result}
         ;
}

### PUBLIC INSTANCE METHOD ###
#
# Upload a file using POST form. Same as submit()
#

*upload = *submit;

### PUBLIC INSTANCE METHOD ###
#
# Poll server for Ext.Direct events
#

sub poll {
    my ($self, %params) = @_;

    my $response = $self->_call_poll(%params);

    return $response;
}

### PUBLIC INSTANCE METHOD ###
#
# Return next TID (transaction ID)
#

sub next_tid { $_[0]->{tid}++ }

### PUBLIC INSTANCE METHOD ###
#
# Read only getter
#

sub api { $_[0]->{api} }

############## PRIVATE METHODS BELOW ##############

### PRIVATE INSTANCE METHOD ###
#
# Receive API declaration from specified server,
# parse it and return Client::API object
#

sub _get_api {
    my ($self) = @_;

    my $uri    = $self->_get_uri('api');
    my $params = $self->{http_params};

    my $resp = HTTP::Tiny->new(%$params)->get($uri);

    die "Can't download API declaration: $resp->{status}\n"
        unless $resp->{success};

    die "Empty API declaration\n"
        unless length $resp->{content};

    return $resp->{content};
}

### PRIVATE INSTANCE METHOD ###
#
# Return URI for specified type of call
#

sub _get_uri {
    my ($self, $type) = @_;

    my $host = $self->{host};
    my $port = $self->{port};

    my $path = $type eq 'api'    ? $self->{api_path}
             : $type eq 'router' ? $self->{router_path}
             : $type eq 'poll'   ? $self->{poll_path}
             :                     die "Unknown type $type\n"
             ;

    $path   =~ s{^/}{};

    my $uri  = $port ? "http://$host:$port/$path"
             :         "http://$host/$path"
             ;

    return $uri;
}

### PRIVATE INSTANCE METHOD ###
#
# Import specified API into global namespace
#

sub _import_api {
    my ($self, $api_js) = @_;

    # Readability shortcut
    my $aclass = 'RPC::ExtDirect::Client::API';

    my $api = $aclass->new($api_js);

    $self->{api} = $api;
}

### PRIVATE INSTANCE METHOD ###
#
# Normalize passed arguments to conform to Method's spec
#

sub _normalize_arg {
    my ($self, $action, $method, $arg) = @_;

    my $named   = $self->api->actions($action)->method($method)->is_named;
    my $ordered = $self->api->actions($action)->method($method)->is_ordered;

    die "${action}->$method requires ordered (by position) arguments\n"
        if $ordered and 'ARRAY' ne ref $arg;

    die "${action}->$method requires named arguments\n"
        if $named and 'HASH' ne ref $arg;

    my $result;

    if ( $named ) {
        my $params = $self->api->actions($action)->method($method)->params;

        @$result{ @$params } = @$arg{ @$params };
    }
    elsif ( $ordered ) {
        my $len = $self->api->actions($action)->method($method)->len;

        @$result = splice @$arg, 0, $len;
    };

    return $result;
}

### PRIVATE INSTANCE METHOD ###
#
# Normalize passed arguments to submit as form POST
#

sub _formalize_arg {
    my ($self, %params) = @_;

    my $action = $params{action};
    my $method = $params{method};
    my $arg    = $params{arg};
    my $upload = $params{upload};

    my $fields = {
        extAction => $action,
        extMethod => $method,
        extType   => 'rpc',
        extTID    => $self->next_tid,
    };

    $fields->{extUpload} = 'true' if $upload;

    @$fields{ keys %$arg } = values %$arg;

    return $fields;
}

### PRIVATE INSTANCE METHOD ###
#
# Calls Action's Method in synchronous fashion
#

sub _call_sync {
    my ($self, $action, $method, $arg, $p) = @_;

    my $uri       = $self->_get_uri('router');
    my $params    = $self->{http_params} // {};
    my $post_body = $self->_encode_post_body($action, $method, $arg);

    @$params{ keys %$p } = values %$p if $p;

    my $options = {
        content => $post_body,
    };

    $self->_parse_cookies($options, $params);

    my $transp = HTTP::Tiny->new(%$params);
    my $resp   = $transp->post($uri, $options);

    return $self->_handle_response($resp);
}

### PRIVATE INSTANCE METHOD ###
#
# Call Action's Method by submitting a form
#

sub _call_form {
    my ($self, %params) = @_;

    my $uri    = $self->_get_uri('router');
    my $fields = $self->_formalize_arg(%params);
    my $upload = $params{upload};

    my $ct = $upload ? 'multipart/form-data; boundary='.$self->_get_boundary
           :           'application/x-www-form-urlencoded; charset=utf-8'
           ;
    my $form_body = $upload ? $self->_www_form_multipart($fields, $upload)
                  :           $self->_www_form_urlencode($fields)
                  ;

    my $options = {
        headers => {
            'Content-Type' => $ct,
        },
        content => $form_body,
    };

    my $p = $self->{http_params} || {};
    @$p{ keys %params } = values %params;

    $self->_parse_cookies($options, $p);

    my $resp = HTTP::Tiny->new->post($uri, $options);

    return $self->_handle_response($resp);
}

### PRIVATE INSTANCE METHOD ###
#
# Call Ext.Direct polling provider
#

sub _call_poll {
    my ($self, %params) = @_;

    my $uri = $self->_get_uri('poll');

    my $options = {};

    my $p = $self->{http_params} || {};
    @$p{ keys %params } = values %params;

    $self->_parse_cookies($options, $p);

    my $resp = HTTP::Tiny->new->get($uri, $options);

    return $self->_handle_poll_response($resp);
}

### PRIVATE INSTANCE METHOD ###
#
# Create POST payload body
#

sub _encode_post_body {
    my ($self, $action, $method, $arg) = @_;

    my $href = {
        action => $action,
        method => $method,
        data   => $arg,
        type   => 'rpc',
        tid    => $self->next_tid,
    };

    return JSON->new->utf8(1)->encode($href);
}

### PRIVATE INSTANCE METHOD ###
#
# Encode form fields as multipart/form-data
#

sub _www_form_multipart {
    my ($self, $arg, $uploads) = @_;

    # This code is shamelessly "adapted" from CGI::Test::Input::Multipart
    my $CRLF     = "\015\012";
    my $boundary = '--' . $self->_get_boundary();
    my $format   = 'Content-Disposition: form-data; name="%s"';

    my $result;

    while ( my ($field, $value) = each %$arg ) {
        $result .= $boundary                . $CRLF;
        $result .= sprintf($format, $field) . $CRLF.$CRLF;
        $result .= $value                   . $CRLF;
    };

    while ( $uploads && @$uploads ) {
        my $filename = shift @$uploads;
        my $basename = (File::Spec->splitpath($filename))[2];

        $result .= $boundary                                . $CRLF;
        $result .= sprintf $format, 'upload';
        $result .= sprintf('; filename="%s"', $basename)    . $CRLF;
        $result .= "Content-Type: application/octet-stream" . $CRLF.$CRLF;

        if ( open my $fh, '<', $filename ) {
            binmode $fh;
            local $/;

            $result .= <$fh> . $CRLF;
        };
    }

    $result .= $boundary . '--' if $result;

    return $result;
}

### PRIVATE INSTANCE METHOD ###
#
# Generate multipart/form-data boundary
#

my $boundary;

sub _get_boundary {
    return $boundary if $boundary;
    
    my $rand;

    for ( 0..19 ) {
        $rand .= (0..9, 'A'..'Z')[$_] for int rand 36;
    };

    return $boundary = $rand;
}

### PRIVATE INSTANCE METHOD ###
#
# Encode form fields as application/x-www-form-urlencoded
#

sub _www_form_urlencode {
    my ($self, $arg) = @_;

    return HTTP::Tiny->new->www_form_urlencode($arg);
}

### PRIVATE INSTANCE METHOD ###
#
# Process Ext.Direct response and return either data or exception
#

sub _handle_response {
    my ($self, $resp) = @_;

    # By Ext.Direct spec it shouldn't even happen, but then again
    die "Ext.Direct request unsuccessful: $resp->{status}\n"
        unless $resp->{success};

    my $exclass = 'RPC::ExtDirect::Client::Exception';

    if ( $resp->{status} == 599 ) {

        # This means internal HTTP::Tiny error
        return $exclass->new({ type    => 'exception',
                               message => $resp->{content},
                               where   => 'HTTP::Tiny',
                            });
    };

    my $content = $self->_decode_response_body( $resp->{content} );

    return $exclass->new($content)
        if 'HASH' eq ref $content and $content->{type} eq 'exception';

    return $content;
}

### PRIVATE INSTANCE METHOD ###
#
# Handle poll response
#

sub _handle_poll_response {
    my ($self, $resp) = @_;

    my $ev = $self->_decode_response_body( $resp->{content} );

    # Poll provider has to return a null event if there are no events
    # because returning empty response would break JavaScript client.
    # But we don't have to follow that broken implementation here.
    return
        if ('HASH' ne ref $ev and 'ARRAY' ne ref $ev) or
           ('HASH' eq ref $ev and
                ($ev->{name} eq '__NONE__' or $ev->{name} eq '' or
                 $ev->{type} ne 'event')
           )
        ;

    delete $_->{type} for 'ARRAY' eq ref $ev ? @$ev : ( $ev );

    return $ev;
}

### PRIVATE INSTANCE METHOD ###
#
# Decode Ext.Direct response body
#

sub _decode_response_body {
    my ($self, $body) = @_;

    my $json_text = $body;

    # Form POSTs require this additional handling
    my $re = qr{^<html><body><textarea>(.*)</textarea></body></html>$}msi;

    if ( $body =~ $re ) {
        $json_text = $1;
        $json_text =~ s{\\"}{"}g;
    };

    return JSON->new->utf8(1)->decode($json_text);
}

### PRIVATE INSTANCE METHOD ###
#
# Parse cookies if provided, creating Cookie headers
#

sub _parse_cookies {
    my ($self, $to, $from) = @_;

    my $cookie_jar = $from->{cookies};

    return unless $cookie_jar;

    my $cookies;

    if ( 'HTTP::Cookies' eq ref $cookie_jar ) {
        $cookies = $self->_parse_http_cookies($cookie_jar);
    }
    else {
        $cookies = $self->_parse_raw_cookies($cookie_jar);
    }

    $to->{headers}->{Cookie} = $cookies if $cookies;
}

### PRIVATE INSTANCE METHOD ###
#
# Parse cookies from HTTP::Cookies object
#

sub _parse_http_cookies {
    my ($self, $cookie_jar) = @_;

    my @cookies;

    $cookie_jar->scan(sub {
        my ($v, $key, $value) = @_;

        push @cookies, "$key=$value";
    });

    return \@cookies;
}

### PRIVATE INSTANCE METHOD ###
#
# Parse (or rather, normalize) cookies passed as a hashref
#

sub _parse_raw_cookies {
    my ($self, $cookie_jar) = @_;

    return [] unless 'HASH' eq ref $cookie_jar;

    return [ map { join '=', $_ => $cookie_jar->{$_} } keys %$cookie_jar ];
}

# Tiny helper class
package
    RPC::ExtDirect::Client::Exception;

use overload
    '""' => \&stringify
    ;

### PUBLIC CLASS METHOD (CONSTRUCTOR) ###
#
# Instantiate a new Exception
#

sub new {
    my ($class, $ex) = @_;

    return bless $ex, $class;
}

### PUBLIC INSTANCE METHOD ###
#
# Return stringified Exception
#

sub stringify {
    my ($self) = @_;

    return sprintf "Exception %s in %s",
                   $self->{message}, $self->{where};
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

Copyright (c) 2012 Alexander Tokarev.

This module is free software; you can redistribute it and/or modify it
under the same terms as Perl itself. See L<perlartistic>.

=cut

