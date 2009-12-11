#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';

BEGIN { use_ok( 'Fink::Services', qw(version_cmp) ) };

# "str1 op str2" forms

my @stringsets = (
    [qw/ a b /],
    [qw/ b b /],
    [qw/ b a /],
    [ 0, 1  ],
    [ 10, 2 ],
    [qw/ abc ab /],			# longer strings are higher
);

foreach my $optest (
    # each list is $op then ref to list of results parallelling @stringsets
    [ ">>" => [ 0, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1 ] ],
    [ "<<" => [ 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0 ] ],
    [ ">=" => [ 0, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1 ] ],
    [ "<=" => [ 1, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0 ] ],
    [ "="  => [ 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0 ] ],
) {
    for( my $setnum=0; $setnum<@stringsets; $setnum++ ) {
	my $test = $stringsets[$setnum]->[0] . " " . $optest->[0] . " " .  $stringsets[$setnum]->[1];
	cmp_ok( &version_cmp( $stringsets[$setnum]->[0], $optest->[0],  $stringsets[$setnum]->[1] ),
	    '==', $optest->[1]->[$setnum],
	    $test
	  );
    }
}
