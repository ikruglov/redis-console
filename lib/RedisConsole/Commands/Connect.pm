package RedisConsole::Commands::Connect;

use 5.14.2;
use strict;
use warnings;
use Moo::Role;

#around do_connect => sub {
#    my ($orig, $self) = @_;
#    if ($self->host && $self->port) {
#        $self->cmd_connect($self->host, $self->port);
#    }
#};

sub cmd_connect {
    my ($self, @args) = @_;
    @args < 1 || @args > 2 and die "wrong number of arguments for 'connect' command";
    my $server = join(':', @args);

    my $redis = eval {
        Redis->new(
            server => $server,
            reconnect => 1,
        );
    } or do {
        my $error = $@ || "can't connect";
        die $self->extract_error_message($error);
    };

    $self->redis($redis);
    say "hello $server";
}

sub cmd_disconnect {
    $_[0]->redis(undef);
    say 'disconnected';
}

sub cmd_exit { say 'good bye!'; exit 0; }
sub cmd_quit { say 'good bye!'; exit 0; }
sub cmd_open { return cmd_connect(@_); }
sub cmd_close { return cmd_disconnect(@_); }

sub completion_for_connect {}
sub completion_for_disconnect {}
sub completion_for_exit {}
sub completion_for_quit {}
sub completion_for_open {}
sub completion_for_close {}

1;
