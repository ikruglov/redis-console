#!/usr/bin/perl

use strict;
use warnings;

use CLI;
exit CLI->new()->do_repl('localhost:6379');
