#!/usr/bin/perl

use strict;
use warnings;

use Redis;
use Data::Dumper;
use Term::ReadLine;
use Getopt::Long::Descriptive;

my %COMMANDS = (
    connect => sub {
        my ($host, $port) = @_;
        my $redis_server = $host . ':' . $port;

        my $redis = Redis->new(
            server => $redis_server,
            reconnect => 60
        );

        if ($redis) {
            print "hello $redis_server\n";
        } else {
            print "failed to connect to $redis_server";
        }

        return $redis;
    },

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

my $term = Term::ReadLine->new('Perl redis_cli');
$term->Attribs->{completion_function} = \&complete;

my $redis = $COMMANDS{connect}->($cmd_opts->host, $cmd_opts->port);
die unless $redis;

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
        eval {
            $redis->$cmd(@args);
            1;
        } or do {
            my $error = $@ || 'zombie error';
            if ($error =~ /unknown command/) {
                print "unknown command '$cmd'\n";
            } elsif ($error =~ /wrong number of arguments/) {
                print "wrong number of arguments for '$cmd' command\n";
            } else {
                print "$error\n";
            }
        }
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
