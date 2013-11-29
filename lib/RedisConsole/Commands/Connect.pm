package RedisConsole::Commands::Connect;

use strict;
use warnings;
use Moo::Role;

has server => ( is => 'rw' );

sub cmd_connect {
    my ($self, @args) = @_;
    @args < 1 || @args > 2 and die "wrong number of arguments for 'connect' command";
    my $server = join(':', @args);

    my $redis = Redis->new(
        server => $server,
        reconnect => 1,
    );

    $self->redis($redis);
    die "failed to connect\n" unless $self->connected;

    $self->server($server);
    $self->prompt("$server > ");
    $self->print("hello $server") if $self->repl_mode;
}

sub cmd_disconnect {
    my $self = shift;
    $self->redis(undef);
    $self->server(undef);
    $self->prompt(undef);
    $self->print('disconnected') if $self->repl_mode;
}

sub cmd_open { shift->cmd_connect(@_) }
sub cmd_close { shift->cmd_disconnect(@_) }

1;
