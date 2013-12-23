package RedisConsole::Commands::Exit;

use strict;
use warnings;
use Moo::Role;

sub cmd_exit {
    my $self = shift;
    $self->exit_repl(1);
    $self->print("good bye!\n") if $self->repl_mode;;
}

sub cmd_quit {
    return shift->cmd_exit;
}

sub completion_for_exit {}
sub completion_for_quit {}

1;
