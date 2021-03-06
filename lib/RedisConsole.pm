package RedisConsole;

use 5.14.2;
use strict;
use warnings;

use Moo;
use Redis;
use Module::Util;
use Term::ReadLine;
use Scalar::Util 'weaken';
use Text::ParseWords qw/parse_line/;
with $_ foreach (Module::Util::find_in_namespace('RedisConsole::Commands'));

has name => ( is => 'ro' );

has prompt => (
    is => 'rw',
    default => sub { 'redis> ' },
    coerce => sub { defined $_[0] ? $_[0] : 'redis> ' },
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

has sub_completion_prefix => (
    is => 'ro',
    default => sub { 'completion_for_' }
);

has repl_mode => (
    is => 'rw',
);

has history => (
    is => 'rw',
    default => sub {[]},
);

has builtin_redis_cmds => (
    is => 'ro',
    default => sub {[
        'ping', 'set', 'get', 'mget', 'incr', 'decr', 'exists', 'del', 'type', 'keys',
        'randomkey', 'rename', 'dbsize', 'rpush', 'lpush', 'llen', 'lrange', 'ltrim',
        'lindex', 'lset', 'lrem', 'lpop', 'rpop', 'sadd', 'srem', 'scard', 'sismember',
        'sinter', 'sinterstore', 'select', 'move', 'flushdb', 'flushall', 'sort', 'save',
        'bgsave', 'lastsave', 'shutdown', 'info',
    ]}
);

sub repl {
    my ($self) = @_;
    $self->repl_mode(1);
    $self->term->ornaments(0);

    my $weakself = $self;
    weaken($weakself);

    my $attr = $self->term->Attribs;
    if ($self->term->isa("Term::ReadLine::Gnu")) {
        $attr->{attempted_completion_function} = sub { $weakself->_completion(@_); }
    } elsif ($self->term->isa("Term::ReadLine::Perl")) {
        $attr->{completion_function} = sub { $weakself->_completion(@_); }
    } else {
        warn "Term::ReadLine::Gnu or Term::ReadLine::Perl is required for the Completion plugin to work";
    }

    while (not $self->exit_repl) {
        my $line = $self->term->readline($self->prompt);
        last unless defined $line;
        next if $line =~ m/^\s*$/;

        $self->add_history($line, 1);
        $self->execute($line);
    }

    return 0;
}

sub execute {
    my ($self, $line) = @_;
    return 1 unless $line;

    my ($cmd, @args) = $self->_parse_line($line);
    return $self->execute_command($cmd, @args);
}

sub execute_command {
    my ($self, $cmd, @args) = @_;
    return 1 unless $cmd;

    eval {
        my $cmd_name = $self->sub_cmd_prefix . $cmd;
        if ($self->can($cmd_name)) {
            $self->$cmd_name(@args);
        } else {
            my $res = $self->redis->$cmd(@args);
            $res and $self->print($res);
        }

        1;
    } or do {
        my $error = $@ || 'zombie error';
        chomp $error;
        $self->print($self->_extract_error_message($error));
        return 1;
    };

    return 0;
}

sub print {
    my ($self, @message) = @_;
    my $text = "@message";
    return unless $text;

    print { $self->out_fh } $text;
    if (!$self->repl_mode || $self->term->ReadLine =~ /Gnu/) {
        print { $self->out_fh } "\n";
    }
}

sub add_history {
    my ($self, $line, $not_add_to_term) = @_;
    my @lines = ref $line ? @$line : $line;

    foreach my $line (@lines) {
        next if @{ $self->history } && $self->history->[-1] eq $line;
        push @{ $self->history }, $line;
        $self->term->addhistory($line) unless $not_add_to_term;
    }
}

sub all_cmds {
    my $self = shift;
    my %cmds = map { $_ => 1 } $self->_all_package_cmds(), @{$self->builtin_redis_cmds};
    return wantarray ? keys %cmds : scalar keys %cmds;
}

# additional staff
# need to extract error message
# since Redis.pm always does confess instead of croak
sub _extract_error_message {
    my ($self, $message) = @_;
    my ($first_line) = split("\n", $message);
    return $message unless $first_line;

    my $pos = rindex($first_line, ' at ');
    $pos <= 0 and return $message;

    my $error = substr($first_line, 0, $pos);
    return $error =~ m/^\[[^\]]+\]\s+ERR\s+(.+)/ ? $1 : $error;
}

sub _all_package_cmds {
    no strict 'refs';
    my $self = shift;
    my $prefix = $self->sub_cmd_prefix;
    my @cmds = map { m/^$prefix(.+)/ ? $1 : () } keys %{ ref($self) . '::' };
    return wantarray ? @cmds : scalar @cmds;
}

sub _parse_line {
    my ($self, $line) = @_;
    return unless $line;

    $line=~ s/^\s+//;
    $line=~ s/\s+$//;
    return unless $line;

    return parse_line($self->delimiters, 0, $line);
}

sub _completion {
    my ($self, $text, $line, $start) = @_;

    my @items = ();
    if ($start == 0) {
        # do cmd autocompletion
        @items = sort $self->all_cmds();
    } elsif (my ($cmd) = $self->_parse_line($line)) {
        # do key autocompletion
        # detect what parameter we try to autocomplete
        my $sub_line = substr($line, 0, $start);
        my (undef, @sub_args) = $self->_parse_line($sub_line);
        my $param_no = scalar @sub_args + 1;

        my $completion_func_name = $self->sub_completion_prefix() . $cmd;
        if ($self->can($completion_func_name)) {
            # command-specific autocompletion
            @items = $self->$completion_func_name($param_no, $text, $line, $start);
        } else {
            # default key autocompletion
            @items = $param_no == 1 ? eval { $self->redis->keys('*') } : ();
        }
    }

    return grep(/^$text/, splice(@items, 0, 100));
}

1;
