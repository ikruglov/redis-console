package RedisConsole;

use 5.14.2;
use strict;
use warnings;

use Moo;
use Redis;
use MooX::Roles::Pluggable search_path => 'RedisConsole::Commands';
use Text::ParseWords qw/parse_line/;
use Term::ReadLine;
use Data::Dumper;

has name => ( is => 'ro' );

has prompt => (
    is => 'rw',
    default => sub { 'redis> ' },
);

has term => (
    is => 'lazy',
    default => sub { Term::ReadLine->new('Perl ' . shift->name) },
);

has out_fh => (
    is => 'rw',
    lazy => 1,
    default => sub { shift->term->OUT || \*STDOUT; }
);

has 'exit_repl' => (
    is => 'rw',
    default => sub { 0 }
);

has redis => (
    is => 'rw',
    trigger => sub { @_ == 2 and shift->connected(defined(shift) ? 1 : 0) },
);

has connected => (
    is => 'rw',
    default => sub { 0 },
);

before 'redis' => sub {
    die "not connected\n" if @_ == 1 && ! shift->connected;
};

has delimiters => (
    is => 'rw',
    default => sub { '\s+' },
);

has sub_cmd_prefix => (
    is => 'ro',
    default => sub { 'cmd_' }
);

sub repl {
    my ($self) = @_;

    while (not $self->exit_repl) {
        my $line = $self->term->readline($self->prompt);
        last unless defined $line;
        next if $line =~ m/^\s*$/;

        $self->term->addhistory($line);
        $self->execute($line);
    }

    return 0;
}

sub execute {
    my ($self, $line) = @_;

    my ($cmd, @args) = parse_line($self->delimiters, 0, $line);
    return 1 unless $cmd;

    my $cmd_name = $self->sub_cmd_prefix . $cmd;
    if ($self->can($cmd_name)) {
        return $self->eval(sub { $self->$cmd_name(@args) });
    } else {
        return $self->eval(sub { $self->redis->$cmd(@args) });
    }
}

sub cmd_test { shift->print('TEST'); }

sub eval {
    my ($self, $cmd) = @_;

    my $res = 1;
    eval {
        $res = $cmd->();
        1;
    } or do {
        my $error = $@ || 'zombie error';
        chomp $error;
        $self->print($error);
    };

    return $res;
}

sub print {
  my ($self, $message) = @_;
  print { $self->out_fh } $message;
  print { $self->out_fh } "\n" if $self->term->ReadLine =~ /Gnu/;
}

#    my $attr = $self->term->Attribs;
#    $attr->{completion_function} = sub {
#        my ($text, $line, $start) = @_;
#
#        my @items;
#        if ($start == 0) {
#            # do cmd autocompletion
#            @items = sort @{ $self->all_cmds() };
#        } else {
#            # do key autocompletion
#            my ($cmd) = split /\s+/, $line;
#            $cmd //= '';
#
#            my $completion_func_name = $self->sub_autompletion_prefix() . $cmd;
#            if ($self->can($completion_func_name)) {
#                my $res = $self->$completion_func_name($text, $line, $start);
#                @items = $res ? @{ $res } : ();
#            } else {
#                @items = eval { $self->redis->keys('*') };
#            }
#        }
#
#        return grep(/^$text/, @items);
#    };
#
#has sub_autompletion_prefix => (
#    is => 'ro',
#    default => sub { 'completion_for_' }
#);
#
#has builtin_redis_cmds => (
#    is => 'ro',
#    default => sub {[
#        'ping', 'set', 'get', 'mget', 'incr', 'decr', 'exists', 'del', 'type', 'keys',
#        'randomkey', 'rename', 'dbsize', 'rpush', 'lpush', 'llen', 'lrange', 'ltrim',
#        'lindex', 'lset', 'lrem', 'lpop', 'rpop', 'sadd', 'srem', 'scard', 'sismember',
#        'sinter', 'sinterstore', 'select', 'move', 'flushdb', 'flushall', 'sort', 'save',
#        'bgsave', 'lastsave', 'shutdown', 'info',
#    ]}
#);


# utils
sub print_result {
    my ($self, $result) = @_;
    return unless $result;

    my $ref = ref $result;
    if (!$ref) {
        print $result;
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


1;
