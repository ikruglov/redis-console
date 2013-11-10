package Redis::CLI::Role::FIFO;

use JSON;
use Moo::Role;
use Data::Dumper;

has all_queue_types => (
    is => 'ro',
    default => sub {[ 'main', 'busy', 'failed' ]},
);

sub cmd_fls {
    my ($self, $queue, $len) = @_;

    if (defined $queue) {
        my @items = $self->redis->lrange($queue, 0, int($len || 10));
        $self->print_result(\@items);
    } else {
        my @queues = map {
            sprintf("%-40s %d items", $_, int($self->redis->llen($_)))
        } sort $self->_get_all_queues();

        $self->print_result(\@queues);
    }
}

sub cmd_fgrep {
    my ($self, $queue, $pattern) = @_;
    die "queue name required" unless $queue;
    $pattern //= '';

    my @items = grep( m/$pattern/, $self->redis->lrange($queue, 0, -1));
    $self->print_result(\@items);
}

sub completion_for_fls   { _queue_completion(@_); }
sub completion_for_fgrep { _queue_completion(@_); }

sub _queue_completion {
    my @queues = sort $_[0]->_get_all_queues();
    return \@queues;
}

sub _get_all_queues {
    my $self = shift;
    return map { $self->redis->keys("*_$_") } @{ $self->all_queue_types };
}

1;
