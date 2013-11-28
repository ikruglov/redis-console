package RedisConsole::Commands::Exit;

use strict;
use warnings;
use Moo::Role;

sub cmd_exit {
    my $self = shift;
    $self->print("good bye!\n");
    $self->exit_repl(1);
    return 0;
}

sub cmd_quit {
    return shift->cmd_exit;
}

1;
