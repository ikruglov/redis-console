package RedisConsole::Commands::Keys;

use strict;
use warnings;
use Moo::Role;

sub cmd_keys {
    my ($self, $pattern) = @_;
    $pattern or die "wrong number of arguments for 'keys' command\n";

    my @keys = $self->redis->keys($pattern);
    $self->print(join("\n", @keys));
}

sub completion_for_keys {}

1;
