#!/usr/bin/perl -w

use Test::More 'no_plan';
use Fink::Command qw(cat);

open FILE, '>foo';
print FILE "Some stuff\nAnd things\n";
close FILE;

is( cat('foo'), "Some stuff\nAnd things\n" );
is_deeply( [cat 'foo'], ["Some stuff\n", "And things\n"] );

$! = 0;  # just in case something else set it.
is( cat('i_do_not_exist'), undef, "cat can't find the file" );
cmp_ok( $!, '!=', 0,                      '  $! set' );

unlink 'foo';
