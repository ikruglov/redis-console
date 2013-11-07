package CLI::Role::Main;

use 5.14.2;
use Moo::Role;
use Data::Dumper;

has host => (
    is => 'ro',
);

has port => (
    is => 'ro',
);

sub cmd_exit { say 'good bye!'; exit 0; }
sub cmd_quit { say 'good bye!'; exit 0; }

sub cmd_connect {
    my ($self, @args) = @_;
    @args > 2 and die "too many parameters\n";
    my $server = join(':', @args);

    my $redis = eval {
        Redis->new(
            server => $server,
            reconnect => 1,
        );
    } or do {
        my $error = $@ || "can't connect";
        die "$error\n";
    };

    $self->redis($redis);
    say "hello $server";
}

sub cmd_disconnect {
    $_[0]->redis(undef);
    say 'disconnected';
}

1;
