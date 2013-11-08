package CLI;

use 5.14.2;

use Moo;
use Redis;
use Data::Dumper;
use Term::ReadLine;

has redis => (
    is => 'rw',
);

before 'redis' => sub {
    die "not connected\n" if !$_[0]->{redis} && @_ == 1;
};

has sub_cmd_prefix => (
    is => 'ro',
    default => sub { 'cmd_' }
);

my @roles = map { s#/#::#g; s#\.pm##; $_ } glob('CLI/Role/*');
with $_ foreach (@roles);

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
        }
    }
}

sub do_repl {
    my ($self, $server) = @_;
    $self->cmd_connect($server);

    my $term = Term::ReadLine->new('Perl redis_cli');
    my $attr = $term->Attribs;
    $term->ornaments(0);

    $attr->{completion_function} = sub {
        my ($text, $line, $start) = @_;
        my @items = $start == 0
                    ? @{ $self->all_cmds() }
                    : eval { $self->redis->keys('*') };

        return grep(/^$text/, @items);
    };

    while (1) {
        my $line = $term->readline('redis> ');
        last unless defined $line;
        next if $line =~ m/^\s*$/;

        $term->addhistory($line);
        $self->do_command($line);
    }
}

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
        @{ $self->_all_redis_cmds() },
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

sub _all_redis_cmds {
    return [];
}

1;
