package Redis::CLI;

use 5.14.2;

use Moo;
use Redis;
use Data::Dumper;
use MooX::Options;
use Term::ReadLine;

has redis => (
    is => 'rw',
);

before 'redis' => sub {
    die "not connected\n" if !$_[0]->{redis} && @_ == 1;
};

has term => (
    is => 'lazy',
);

has sub_cmd_prefix => (
    is => 'ro',
    default => sub { 'cmd_' }
);

has sub_autompletion_prefix => (
    is => 'ro',
    default => sub { 'completion_for_' }
);

has builtin_redis_cmds => (
    is => 'ro',
    default => sub {[
        'ping', 'set', 'get', 'mget', 'incr', 'decr', 'exists', 'del', 'type', 'keys',
        'randomkey', 'rename', 'dbsize', 'rpush', 'lpush', 'llen', 'lrange', 'ltrim',
        'lindex', 'lset', 'lrem', 'lpop', 'rpop', 'sadd', 'srem', 'scard', 'sismember',
        'sinter', 'sinterstore', 'select', 'move', 'flushdb', 'flushall', 'sort', 'save',
        'bgsave', 'lastsave', 'shutdown', 'info'
    ]}
);

option 'execute' => (
    is => 'ro',
    short => 'e',
    format => 's',
    documentation => 'Command to execute',
);

# loading plugins
my @roles = map { s#/#::#g; s#\.pm##; $_ } glob('Redis/CLI/Role/*.pm');
with $_ foreach (@roles);

# main routines
sub run {
    my $self = shift;
    $self->do_connect();

    if ($self->execute) {
        return $self->do_command($self->execute);
    } else {
        return $self->do_repl();
    }
}

sub do_connect {}

sub do_command {
    my ($self, $line) = @_;

    my ($cmd, @args) = split /\s+/, $line;
    return unless $cmd;

    my $cmd_name = $self->sub_cmd_prefix . $cmd;
    if ($self->can($cmd_name)) {
        eval {
            $self->$cmd_name(@args);
            1;
        } or do {
            my $error = $@ || 'zombie error';
            say $self->extract_error_message($error);
            return 1;
        }
    } else {
        eval {
            if ($self->redis->can($cmd)) {
                my @result = $self->redis->$cmd(@args);
                $self->print_result(\@result);
            } else {
                my $result = $self->redis->$cmd(@args);
                $self->print_result($result);
            }

            1;
        } or do {
            my $error = $@ || 'zombie error';
            say $self->extract_error_message($error);
            return 1;
        }
    }

    return 0;
}

sub do_repl {
    my ($self) = @_;
    my $attr = $self->term->Attribs;

    $attr->{completion_function} = sub {
        my ($text, $line, $start) = @_;

        my @items;
        if ($start == 0) {
            # do cmd autocompletion
            @items = sort @{ $self->all_cmds() };
        } else {
            # do key autocompletion
            my ($cmd) = split /\s+/, $line;
            $cmd //= '';

            my $completion_func_name = $self->sub_autompletion_prefix() . $cmd;
            if ($self->can($completion_func_name)) {
                my $res = $self->$completion_func_name($text, $line, $start);
                @items = $res ? @{ $res } : ();
            } else {
                @items = eval { $self->redis->keys('*') };
            }
        }

        return grep(/^$text/, @items);
    };

    while (1) {
        my $line = $self->term->readline('redis> ');
        last unless defined $line;
        next if $line =~ m/^\s*$/;

        $self->term->addhistory($line);
        $self->do_command($line);
    }
}

# utils
sub print_result {
    my ($self, $result) = @_;
    return unless $result;

    my $ref = ref $result;
    if (!$ref) {
        say $result;
    } elsif ($ref eq 'ARRAY') {
        my $len = scalar @$result;
        if ($len == 1 ) {
            $self->print_result($result->[0]);
        } elsif ($len > 1) {
            my $i = 0;
            foreach (sort @$result) {
                print ++$i, ') ', $_, "\n";
            }
        }
    } else {
        print Dumper $result;
    }
}

# need to extract error message
# since Redis.pm always does confess instead of croak
sub extract_error_message {
    my ($self, $message) = @_;
    my ($first_line) = split("\n", $message);
    my $pos = rindex($first_line, ' at ');

    if ($pos > 0) {
        my $error = substr($first_line, 0, $pos);
        return $error =~ m/^\[[^\]]+\]\s+ERR\s+(.+)/ ? $1 : $error;
    }

    return $message;
}

sub all_cmds {
    my $self = shift;
    my @all_cmds = sort @{[
        @{ $self->builtin_redis_cmds },
        @{ $self->_all_package_cmds() },
    ]};

    return \@all_cmds;
}

sub _all_package_cmds {
    no strict 'refs';
    my $self = shift;
    my $prefix = $self->sub_cmd_prefix;
    my @cmds = map { m/^$prefix(.+)/ ? $1 : () } keys %{ ref($self) . '::' };
    return \@cmds;
}

sub _build_term {
    my $term = Term::ReadLine->new('Perl redis_cli');
    $term->ornaments(0);
    return $term;
}

1;
