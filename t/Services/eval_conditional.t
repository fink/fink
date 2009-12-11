#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';

BEGIN { use_ok( 'Fink::Services', qw(eval_conditional) ) };

# "str1 op str2" forms

my @stringsets = (
    [qw/ a b /],
    [qw/ b b /],
    [qw/ b a /],
    [ 0, 1  ],
    [ 2, 10 ]
);

foreach my $optest (
    # each list is $op then ref to list of results parallelling @stringsets
    [ ">>" => [ 0, 0, 1, 0, 1 ] ],
    [ "<<" => [ 1, 0, 0, 1, 0 ] ],
    [ ">=" => [ 0, 1, 1, 0, 1 ] ],
    [ "<=" => [ 1, 1, 0, 1, 0 ] ],
    [ "="  => [ 0, 1, 0, 0, 0 ] ],
    [ "!=" => [ 1, 0, 1, 1, 1 ] ]
) {
    for( my $setnum=0; $setnum<@stringsets; $setnum++ ) {
	my $test = $stringsets[$setnum]->[0] . " " . $optest->[0] . " " .  $stringsets[$setnum]->[1];
	cmp_ok( &eval_conditional( $test, "eval_conditional.t" ),
	    '==', $optest->[1]->[$setnum],
	    $test
	  );
    }
}

# "str1 op str2" whitespace tests
foreach my $str1 ( "a", " a" ) {
    foreach my $op ( "=", " =", "= ", " = " ) {
	foreach my $str2 ( "a", "a " ) {
	    my $test = $str1 . $op . $str2;
	    cmp_ok( &eval_conditional( $test, "eval_conditional.t" ),
		    '==', 1,
		    "'$test'"
		  );
	}
    }
}

# "str" forms
foreach my $testitem (
    [ ""    => 0 ],
    [ " "   => 0 ],
    [ "a"   => 1 ],
    [ "a "  => 1 ],
    [ " a"  => 1 ],
    [ " a " => 1 ],
    [ 0     => 1 ]   # these are stringified comparisons!
) {
    cmp_ok( &eval_conditional( $testitem->[0], "eval_conditional.t" ),
	    '==', $testitem->[1],
	    "'$testitem->[0]'"
	  );
}

# bogus forms
foreach my $testitem (
    "a a",
    "a=a a"
) {
    eval {  &eval_conditional( $testitem, "eval_conditional.t" ) };
    like( $@,
	  qr/Error/,
	  "'$testitem'"
	);
}

