package util;

use Carp;

use RPC::ExtDirect::Server;

use base 'Exporter';

our @EXPORT = qw(
    start_server
    stop_server
);

our ($SERVER_PID, $SERVER_PORT);

sub start_server {
    my (%params) = @_;

    return $SERVER_PORT if $SERVER_PORT;

    my $server = RPC::ExtDirect::Server->new(%params);
    my $port   = $SERVER_PORT = $server->port;

    if ( my $pid = $SERVER_PID = fork ) {
        local $SIG{CHLD} = sub { waitpid $pid, 0 };

        # Give the child some head start
        select undef, undef, undef, 0.1;

        return $port;
    }
    elsif ( defined $pid && $pid == 0 ) {

        # Trap last breaths to avoid cluttering the screen
        local $SIG{__DIE__} = sub {};

        $server->run();

        exit 0;
    }
    else {
        croak "Can't fork: $!";
    };

    return;
}

sub stop_server {
    my ($pid) = @_;

    $pid = $SERVER_PID unless defined $pid;

    # This is a bit cruel but somehow if I use any other signal
    # the server kid has last opportunity to cry for help.
    # Which we don't want because it breaks TAP output.
    kill 9, $pid if defined $pid;

    $SERVER_PID = $SERVER_PORT = undef;
}

END { stop_server }

1;


