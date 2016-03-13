#!perl

use 5.010;
use strict;
use warnings FATAL => 'all';

use Test::More tests => 2;

BEGIN {
    use_ok('App::Droplets') || print "[Error]: Could not load App::Droplets.\n";
}

diag("Testing App::Droplets $App::Droplets::VERSION, Perl $], $^X");

my $cmd = File::Spec->catfile('blib', 'bin', 'droplets');
ok( -x $cmd, 'Can execute droplets' );
