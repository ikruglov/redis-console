#!/usr/local/bin/booking-perl

use strict;
use warnings;

use Redis;
use Data::Dumper;
use Term::ReadLine;
use Getopt::Long::Descriptive;

my %COMMANDS = (
    ls => sub {
        my ($redis, $pattern) = @_;
        $pattern //= '*';

        my %types= (
            hash   => '%',
            list   => '@',
            string => '$',
        );

        my @keys = $redis->keys($pattern);
        my @result = map {
            my $type = $redis->type($_);
            my $prefix = $types{$type} // '';
            "$prefix$_";
        } @keys;

        print_result(\@result);
    }, 

    exit => sub { exit 0 },
    quit => sub { exit 0 },
);

# Get options from command line
my ( $cmd_opts, $usage ) = describe_options(
    '%c %o',
    [ 'host|h=s', 'Redis host', { required => 1  } ],
    [ 'port|p=i', 'Redis port', { required => 1  } ],
    [                                              ],
    [ 'debug!', 'show verbose debug output'        ],
    [ 'help|?', 'show this help message'           ],
);

if ( $cmd_opts->help ) {
    print $usage->text;
    exit 0;
}

my $term= Term::ReadLine->new('Perl redis_cli');
$term->Attribs->{completion_function} = \&complete;

my $redis_server = $cmd_opts->host . ':' . $cmd_opts->port;
my $redis = Redis->new(
    server => $redis_server,
    reconnect => 60
);

if ($redis) {
    print "hello $redis_server\n";
} else {
    die "failed to connect to $redis_server";
}

MAIN_LOOP:
while (1) {
    my $line = $term->readline('redis> ');
    last unless defined $line;
    next if $line =~ m/^\s*$/;

    $term->addhistory($line);

    my ($cmd, @args) = split /\s+/, $line;
    if (exists $COMMANDS{$cmd}) {
        eval {
            $COMMANDS{$cmd}->($redis, @args);
            1;
        } or do {
            my $error = $@ || 'zombie error';
            print "$error\n";
        }
    } elsif ($redis->can($cmd)) {
        my @result = $redis->$cmd(@args);
        print_result(\@result);
    } else {
        print "unknown command '$cmd'\n";
    }
}

sub complete {
}

sub print_result {
    my $result = shift;
    my $ref = ref $result;
    if ($ref eq 'ARRAY') {
        my $len = scalar @$result;
        if ($len == 1) {
            print Dumper $result->[0];
            print $result->[0], "\n";
        } elsif ($len > 1) {
            my $i = 0;
            foreach (@$result) {
                print ++$i, ') ', $_, "\n";
            }
        }
    } elsif ($ref eq 'HASH') {
        print Dumper $result;
    } else {
        print $result, "\n";
    }
}

exit 1
