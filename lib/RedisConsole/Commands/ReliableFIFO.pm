package RedisConsole::Commands::ReliableFIFO;

use JSON;
use Moo::Role;
use Data::Dumper;
use Queue::Q::ReliableFIFO::Item;

has fformat => (
    is => 'rw',
    default => sub { 'raw' },
);

has fbuffer => (
    is => 'rw',
    default => sub { {} },
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

sub cmd_fbuffer {
    my ($self) = @_;
    my ($queue, $items, $len) = $self->_get_fbuffer();

    $self->_print($self->_format($items));
    $self->print("\nBuffer contains $len items from $queue");
}

sub cmd_fls {
    my ($self, $queue, $p1, $p2) = @_;

    if (defined $queue) {
        my ($start, $stop) = (0, 10);
        if (defined $p1 && defined $p2) {
            ($start, $stop) = (int $p1 , int $p2);
        } elsif (defined $p1) {
            ($start, $stop) = (0, int $p1);
        }

        my $raw_items = $self->redis->lrange($queue, $start, $stop);
        $self->_print($self->_format($raw_items));
        $self->_set_fbuffer($queue, $raw_items);
    } else {
        my @items = map {
            sprintf("%-40s %d items", $_, int($self->redis->llen($_)))
        } sort $self->_get_all_queues();
        $self->_print(\@items);
    }
}

sub cmd_fgrep {
    my ($self, $queue, $pattern) = @_;
    die "queue name required\n" unless $queue;
    die "pattern required\n" unless $pattern;

    my $raw_items = $self->redis->lrange($queue, 0, -1);
    my @filtered_items = grep(m/$pattern/, @$raw_items);

    $self->_print($self->_format(\@filtered_items));
    $self->_set_fbuffer($queue, \@filtered_items);
}

sub cmd_fdump {
    my ($self, $file) = @_;
    die "file name required\n" unless $file;

    my ($queue, $items, $len) = $self->_get_fbuffer();
    $self->print("Dumping $len items to file '$file'");

    open(my $fh, '>', $file) or die "failed to open file: $!\n";
    print $fh join("\n", @{ $self->_format($items) });
    close($fh);
}

sub cmd_fdel {
    my ($self) = @_;

    my $num_deleted = 0;
    my ($queue, $items, $len) = $self->_get_fbuffer();

    foreach my $value (@$items) {
        $num_deleted += $self->redis->lrem($queue, 1, $value);
    }

    $self->print("Deleted $num_deleted out of $len items");
}

sub cmd_frequeue {
    my ($self, $force) = @_;
    my $do_force = ($force // '') eq 'force';

    my $num_requeued = 0;
    my ($queue, $items, $len) = $self->_get_fbuffer();

    my $main_queue = $queue;
    $main_queue =~ s/_[^_]+$/_main/;

    foreach my $value (@$items) {
        my $data = Queue::Q::ReliableFIFO::Item->new(
            _serialized => $value
        )->data();

        $do_force and $data->{force} = 1;
        my $item_to_enqueue = Queue::Q::ReliableFIFO::Item->new(data => $data);

        my $is_deleted = $self->redis->lrem($queue, 1, $value);
        if ($is_deleted) {
            $num_requeued += $is_deleted;
            $self->redis->lpush($main_queue, $item_to_enqueue->_serialized);
        }
    }

    $self->print("Requeued $num_requeued out of $len items" . ($do_force ? ' (with force)' : ''));
}

##################################
# internal routines
#################################

sub _get_all_queues {
    my $self = shift;
    return map { $self->redis->keys("*_$_") } @{ $self->all_queue_types };
}

sub _set_fbuffer {
    my ($self, $queue, $items) = @_;
    die "queue name required\n" unless $queue;
    $items //= [];
    my $length = scalar @$items;

    $self->fbuffer({ $queue => $items});
    $self->repl_mode and $self->print("\nBuffer updated, $length items stored from $queue");
}

sub _get_fbuffer {
    my $self = shift;
    my @keys = keys %{ $self->fbuffer // {} };
    @keys or die("Buffer is empty\n");

    my $queue = $keys[0];
    my $items = $self->fbuffer->{$queue};
    return ($queue, $items, scalar @$items);
}

sub _format {
    my ($self, $raw_items) = @_;

    if ($self->fformat eq 'raw') {
        return $raw_items;
    } elsif ($self->fformat eq 'hdp') {
        my @items = map {
            my $item = Queue::Q::ReliableFIFO::Item->new(_serialized => $_);
            my $data = $item->data() // {};
            my $error = $item->last_error() // '';
            $error =~ s/^error importing \d{10} - \d{10}: //;
            $error =~ s/\s+/ /g;

            sprintf(
                '%-15s %-25s %-15s %-30s %-10s %-100s',
                $data->{epoch},
                $data->{epoch_humanized},
                join(',', @{ $data->{dc} // ['none'] }),
                join(',', @{ $data->{type} // ['none'] }),
                $data->{force} // 0,
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

sub _print {
    my ($self, $items) = @_;
    $self->print(join("\n", @$items));
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
