#!/usr/bin/perl -w

use Test::More 'no_plan';
use Fink::Command qw(touch);

ok( touch "foo" );
ok( -e "foo" );
is( -s "foo", 0 );
my $mtime = (stat("foo"))[9];
sleep 1;
ok( touch "foo" );
cmp_ok( $mtime, '<', (stat("foo"))[9] );

ok( open( FILE, ">foo" ) );
print FILE "something";
close FILE;

$mtime = (stat("foo"))[9];
sleep 1;
ok( touch "foo" );
cmp_ok( $mtime, '<', (stat("foo"))[9] );
ok( open FILE, "foo" );
is( join('', <FILE>), "something" );
close FILE;

END { unlink 'foo' }
