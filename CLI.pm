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

my @roles = map { s#/#::#g; s#\.pm##; $_ } glob('CLI/Role/*');
with $_ foreach (@roles);

sub do_command {
    my ($self, $line) = @_;

    my ($cmd, @args) = split /\s+/, $line;
    return unless $cmd;

    my $cmd_name = "cmd_$cmd";
    if ($self->can($cmd_name)) {
        eval {
            $self->$cmd_name(@args);
            1;
        } or do {
            my $error = $@ || 'zombie error';
            say $error;
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
            if ($error =~ /unknown command/) {
                say "unknown command '$cmd'";
            } elsif ($error =~ /wrong number of arguments/) {
                say "wrong number of arguments for '$cmd' command";
            } else {
                say $error;
            }
        }
    }
}

sub do_repl {
    my $self = shift;
    my $term = Term::ReadLine->new('Perl redis_cli');

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

1;
