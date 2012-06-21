package RPC::ExtDirect::Client::API;

use strict;
use warnings;
no  warnings 'uninitialized';   ## no critic

use JSON;

### PUBLIC CLASS METHOD (CONSTRUCTOR) ###
#
# Instantiate a new API declaration from JavaScript code
#

sub new {
    my ($class, $js) = @_;

    my $api_json = _strip_js($js);
    my $api_href = _decode_api($api_json);

    return bless $api_href, $class;
}

### PUBLIC INSTANCE METHOD ###
#
# Return Action object or list of Action objects, depending on context
#

sub actions {
    my ($self, @actions) = @_;

    my $aclass = 'RPC::ExtDirect::Client::API::Action';

    if ( wantarray ) {
        my @set = @actions ? @actions
                :            keys %{ $self->{actions} }
                ;

        my @result = map { $aclass->new($_->[0], $_->[1]) }
                     map { [ $_, $self->{actions}->{$_} ] }
                         @set;

        return @result;
    }
    else {
        my $action = shift @actions;

        return $aclass->new( $action, $self->{actions}->{ $action } );
    };
}

### PUBLIC INSTANCE METHODS ###
#
# Read only getters
#

sub type { $_[0]->{type} }
sub url  { $_[0]->{url}  }

############## PRIVATE METHODS BELOW ##############

### PRIVATE PACKAGE SUBROUTINE ###
#
# Extracts actual JSONified API declaration from JavaScript string
#

sub _strip_js {
    my ($js) = @_;

    # Strip leading and trailing JavaScript, leave only JSON
    $js =~ s/ \A [^{]+ //xms;
    $js =~ s/ [^}]+ \z //xms;

    return $js;
}

### PRIVATE PACKAGE SUBROUTINE ###
#
# Decode API declaration and check basic constraints
#

sub _decode_api {
    my ($js) = @_;

    my ($api) = eval { JSON->new->utf8(1)->decode_prefix($js) };

    die "Can't decode API declaration: $@\n" if $@;

    die "Empty API declaration\n"
        unless 'HASH' eq ref $api;

    die "Unsupported API type\n"
        unless $api->{type} =~ /remoting/i;

    return $api;
}

package
    RPC::ExtDirect::Client::API::Action;

### PUBLIC CLASS METHOD (CONSTRUCTOR) ###
#
# Instantiate a new Action
#

sub new {
    my ($class, $name, $action) = @_;

    # Convert from array of hashrefs to hash of hashrefs
    my %methods = map { $_->{name} => $_ } @$action;

    return bless { name => $name, methods => { %methods } }, $class;
}

### PUBLIC INSTANCE METHOD ###
#
# Returns Client::API::Method object by name
#

sub method {
    my ($self, $method) = @_;

    my $mclass = 'RPC::ExtDirect::Client::API::Method';

    return $mclass->new( {} ) unless $self->{methods}->{$method};
    return $mclass->new( $self->{methods}->{$method} );
}

### PUBLIC INSTANCE METHOD ###
#
# Read only getter
#

sub name { $_[0]->{name} }

package
    RPC::ExtDirect::Client::API::Method;

### PUBLIC CLASS METHOD (CONSTRUCTOR) ###
#
# Instantiate a new Client::API::Method
#

sub new {
    my ($class, $method) = @_;

    return bless $method, $class;
}

### PUBLIC INSTANCE METHOD ###
#
# Check if this Method accepts named parameters
#

sub is_named { !!$_[0]->{params} }

### PUBLIC INSTANCE METHOD ###
#
# Check if this Method accepts ordered parameters
#

sub is_ordered { $_[0]->{len} > 0 }

### PUBLIC INSTANCE METHOD ###
#
# Check if this Method is a form handler
#

sub is_formhandler { !!$_[0]->{formHandler} }

### PUBLIC INSTANCE METHODS ###
#
# Read only getters
#

sub len         { $_[0]->{len} // 0    }
sub name        { $_[0]->{name}        }
sub params      { $_[0]->{params}      }
sub formHandler { $_[0]->{formHandler} }

1;

__END__

=pod

=head1 NAME

RPC::ExtDirect::Client::API - Parse and interpret Ext.Direct API declarations

=head1 SYNOPSIS

This module is not intended to be used directly.

=head1 AUTHOR

Alexander Tokarev E<lt>tokarev@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2012 Alexander Tokarev

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself. See L<perlartistic>.

=cut

