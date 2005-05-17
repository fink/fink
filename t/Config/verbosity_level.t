#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';

use Fink::Config qw(set_options);

my $config = Fink::Config->new_with_path("basepath/etc/fink.conf");

is( $config->verbosity_level(), 0 );

# We take highest among verbosity and verbose
my @Verbosity_Levels = (
                        ['true',   0,     3],
                        ['high',   0,     3],
                        ['medium', 0,     2],
                        ['low',    0,     1],
                        ['low',    2,     2],
                        [3,       -1,     0],
);

foreach my $test (@Verbosity_Levels) {
    my($verbose, $verbosity, $level) = @$test;

    $config->set_param('Verbose', $verbose);
    set_options( { verbosity => $verbosity } );
    is( $config->verbosity_level(), $level, "$verbose + $verbosity == $level" );
}

