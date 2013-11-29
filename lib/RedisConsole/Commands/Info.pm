package RedisConsole::Commands::Info;

use strict;
use warnings;
use Moo::Role;

sub cmd_info {
    my ($self) = @_;
    my $info = $self->redis->info();
    my @to_print = map { sprintf("%-30s %s", $_, $info->{$_}) } keys %$info;
    $self->print(join("\n", @to_print));
}

1;
