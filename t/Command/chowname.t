#!/usr/bin/perl -w

use Test::More;

if( $> == 0 ) {
    plan 'no_plan';
}
else {
    # can anyone think of a way to test chown without being root?
    plan skip_all => "You must be root to test chowname";
}

use Fink::Command qw(chowname touch);

sub ugcheck { 
    my $file = shift;
    my($uid, $gid) = (stat $file)[4,5];
    return( scalar getpwuid($uid), getgrgid($gid) );
}

touch "foo";
END { unlink "foo" }

my($origuser, $origgroup) = ugcheck('foo');
ok( chowname 'nobody', 'foo' );
my($user, $group) = ugcheck('foo');
is( $user,  'nobody',   'chown to a user' );
is( $group, $origgroup, '  group untouched' );

unlink 'foo';  touch 'foo';
($origuser, $origgroup) = ugcheck('foo');
ok( chowname ':nobody', 'foo' );
($user,$group) = ugcheck('foo');
is( $group, 'nobody',     'chown to a group' );
is( $user,  $origuser,    '  user untouched' );


unlink 'foo';
touch 'foo';

ok( chowname 'nobody:nobody', 'foo' );
($user, $group) = ugcheck('foo');
is( $user,  'nobody', 'chown to a user...' );
is( $group, 'nobody', '  and a group' );
