package RedisConsole::Commands::ReliableFIFO;

use JSON;
use Moo::Role;
use Data::Dumper;

has fformat => (
    is => 'rw',
    default => sub { 'raw' },
);

has fdryrun => (
    is => 'rw',
    default => sub { 0 },
);

has all_queue_types => (
    is => 'ro',
    default => sub {[ 'main', 'busy', 'failed' ]},
);

sub cmd_fformat {
    my ($self, $format) = @_;
    if (defined $format) {
        # validate input
        $self->fformat($format);
        $self->repl_mode and $self->print("ReliableFIFO output format: " . $self->fformat);
    } else {
        $self->print("ReliableFIFO output format: " . $self->fformat);
    }
}

sub cmd_fdryrun {
    my ($self, $dryrun) = @_;
    if (defined $dryrun) {
        $self->fdryrun($dryrun eq 'on' ? 1 : 0);
        $self->repl_mode
            and $self->print("ReliableFIFO dryrun mode: " . ($self->fdryrun ? 'on' : 'off'));
    } else {
        $self->print("ReliableFIFO dryrun mode: " . ($self->fdryrun ? 'on' : 'off'));
    }
}

sub cmd_fls {
    my ($self, $queue, $p1, $p2) = @_;

    my @items;
    if (defined $queue) {
        my ($start, $stop) = (0, 10);
        if (defined $p1 && defined $p2) {
            ($start, $stop) = (int $p1 , int $p2);
        } elsif (defined $p1) {
            ($start, $stop) = (0, int $p1);
        }

        my $raw_items = $self->redis->lrange($queue, $start, $stop);
        @items = @{ $self->_format($raw_items) };
    } else {
        @items = map {
            sprintf("%-40s %d items", $_, int($self->redis->llen($_)))
        } sort $self->_get_all_queues();
    }

    $self->print(join("\n", @items));
}

sub cmd_fgrep {
    my ($self, $queue, $pattern) = @_;
    die "queue name required\n" unless $queue;
    die "pattern required\n" unless $pattern;

    my $raw_items = $self->redis->lrange($queue, 0, -1);
    my $filtered_items = $self->_filter($raw_items, $pattern);
    $self->print(join("\n", @$filtered_items));
}

sub cmd_fdump {
    my ($self, $queue, $file) = @_;
    die "queue name required\n" unless $queue;
    die "file name required\n" unless $file;

    my $raw_items = $self->redis->lrange($queue, 0, -1);
    my $len = scalar @$raw_items;

    $self->print("dumping $len items to file '$file'") if $self->repl_mode;
    open(my $fh, '>', $file) or die "failed to open file: $!\n";
    print $fh join("\n", @{ $self->_format($raw_items) });
    close($fh);
}

sub cmd_fdel {
    my ($self, $queue, $pattern) = @_;
    die "queue name required\n" unless $queue;
    die "pattern required\n" unless $pattern;

    my $raw_items = $self->redis->lrange($queue, 0, -1);
    my $to_delete = $self->_filter($raw_items, $pattern);

    if ($self->fdryrun) {
        $self->print(join("\n", @{ $self->_format($to_delete) }));

        my $num_deleted = scalar @$to_delete;
        $self->print("\n") if $num_deleted;
        $self->print("Deleted $num_deleted items (dryrun)");
    } else {
        my $num_deleted = 0;
        foreach my $value (@$to_delete) {
            $num_deleted += $self->redis->lrem($queue, 1, $value);
        }

        $self->print("Deleted $num_deleted items");
    }
}

sub cmd_freorder {
    my ($self, $queue, $order) = @_;
    die "queue name required\n" unless $queue;
}

##################################
# internal routines
#################################

sub _get_all_queues {
    my $self = shift;
    return map { $self->redis->keys("*_$_") } @{ $self->all_queue_types };
}

sub _format {
    my ($self, $raw_items) = @_;

    if ($self->fformat eq 'raw') {
        return $raw_items;
    } elsif ($self->fformat eq 'hdp') {
        my @items = map {
            my $json = JSON::decode_json($_);
            my $error = $json->{error} // '';
            $error =~ s/^error importing \d{10} - \d{10}: //;
            $error =~ s/\s+/ /g;

            sprintf(
                '%-15s %-25s %-15s %-30s %-10s %-100s',
                $json->{b}->{epoch},
                $json->{b}->{epoch_humanized},
                join(',', @{ $json->{b}->{dc} // ['none'] }),
                join(',', @{ $json->{b}->{type} // ['none'] }),
                $json->{b}->{force} // 0,
                $self->_extract_error_message($error),
            );
        } @{ $raw_items };

        unshift @items, sprintf("%-15s %-25s %-15s %-30s %-10s %-100s",
                                '<epoch>', '<epoch_humanized>',
                                '<dc>', '<type>', '<force>', '<error>');

        return \@items;
    } else {
        die 'unknown _fls_type';
    }
}

sub _filter {
    my ($self, $raw_items, $pattern) = @_;
    return $raw_items unless $pattern;

    my @filtered_items = grep(m/$pattern/, @$raw_items);
    return \@filtered_items;
}

1;

#
#sub completion_for_fls   { _queue_completion(@_); }
#sub completion_for_fgrep { _queue_completion(@_); }
#
#sub _queue_completion {
#    my @queues = sort $_[0]->_get_all_queues();
#    return \@queues;
#}
