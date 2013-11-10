#!/usr/bin/perl

use strict;
use warnings;

use Redis::CLI;
exit Redis::CLI->new_with_options()->run();
