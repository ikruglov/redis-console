package Devel::REPL::Plugin::RedisConsole;

use strict;
use warnings;

use Data::Dumper;
use Devel::REPL::Plugin;
use Text::ParseWords qw/parse_line/;

has delimiters => (
    is => 'rw',
    default => sub { '\s+' },
);

has builtin_redis_cmds => (
    is => 'ro',
    default => sub {
        my %cmds =  map { $_ => 1 } (
            'ping', 'set', 'get', 'mget', 'incr', 'decr', 'exists', 'del', 'type', 'keys',
            'randomkey', 'rename', 'dbsize', 'rpush', 'lpush', 'llen', 'lrange', 'ltrim',
            'lindex', 'lset', 'lrem', 'lpop', 'rpop', 'sadd', 'srem', 'scard', 'sismember',
            'sinter', 'sinterstore', 'select', 'move', 'flushdb', 'flushall', 'sort', 'save',
            'bgsave', 'lastsave', 'shutdown', 'info',
        );

        return \%cmds;
    }
);

has sub_cmd_prefix => (
    is => 'ro',
    default => sub { 'cmd_' },
);

around 'eval' => sub {
    my ($orig, $self, $line) = @_;

    my ($cmd, @args) = parse_line($self->delimiters, 0, $line);
    if ($cmd) {
        my $cmd_name = $self->sub_cmd_prefix . $cmd;
        if ($self->can($cmd_name)) {
            return $self->$cmd_name(@args);
        } elsif (exists $self->builtin_redis_cmds->{$cmd}) {
        }
    }

    return $self->$orig($line);
};

sub cmd_connect {
    my $self = shift;
    return $self->error_return("Redis error", 'test');
}

1;
