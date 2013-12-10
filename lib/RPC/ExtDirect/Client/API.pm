package RPC::ExtDirect::Client::API;

use strict;
use warnings;
no  warnings 'uninitialized';   ## no critic

use JSON;

use RPC::ExtDirect::Util::Accessor;
use RPC::ExtDirect::API;

use base 'RPC::ExtDirect::API';

### PUBLIC CLASS METHOD (CONSTRUCTOR) ###
#
# Instantiate a new API declaration from JavaScript code
#

sub new_from_js {
    my ($class, %params) = @_;
    
    my $js       = delete $params{js};
    my $api_json = _strip_js($js);
    my $api_href = _decode_api($api_json);
    
    my $self = $class->SUPER::new_from_hashref(
        api_href => $api_href,
        %params,
    );
    
    return $self;
}

############## PRIVATE METHODS BELOW ##############

### PRIVATE PACKAGE SUBROUTINE ###
#
# Extracts actual JSONified API declaration from JavaScript string
#

sub _strip_js {
    my ($js, $remoting_var) = @_;

    # We assume that the API definition is simple JavaScript
    my @parts = split /;\s*/, $js;
    
    my ($api_def) = grep /^\s*$remoting_var\s*=\s*{/, @parts;
    
    die "Can't find the API definition for $remoting_var\n"
        unless defined $api_def;
    
    # This should leave only the API object, more or less
    $api_def =~ s/^\s*$remoting_var\s*=\s*//;

    return $api_def;
}

### PRIVATE PACKAGE SUBROUTINE ###
#
# Decode API declaration and check basic constraints
#

sub _decode_api {
    my ($js) = @_;

    my ($api_js) = eval { JSON->new->utf8(1)->decode_prefix($js) };

    die "Can't decode API declaration: $@\n" if $@;

    die "Empty API declaration\n"
        unless 'HASH' eq ref $api;

    die "Unsupported API type\n"
        unless $api_js->{type} =~ /remoting/i;
    
    # Convert the JavaScript API definition to the format
    # API::new_from_hashref expects
    my $actions = $api_js->{actions};
    
    my %remote_actions
        = map { $_ => _convert_action($actions->{$_}) } keys %$actions;
    
    return \%remote_actions;
}

### PRIVATE PACKAGE SUBROUTINE ###
#
# Convert JavaScript Action definition to remote Action definition
#

sub _convert_action {
    my ($action_def) = @_;
    
    my %methods = map { delete $_->{name} => $_ } @$action_def;
    
    return {
        remote  => 1,
        methods => \%methods,
    };
}

1;
