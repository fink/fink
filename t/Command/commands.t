#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';

BEGIN { use_ok 'Fink::Command', ':ALL' }

my $scratch_dir = 'Command/scratch';
mkdir_p $scratch_dir;
ok( chdir $scratch_dir );
END { chdir '../..';  rm_rf $scratch_dir }

{
    open FILE, '>foo';
    print FILE "some stuff\n";
    close FILE;

    cp 'foo', 'bar';
    use File::Compare;
    is( compare('foo', 'bar'), 0 );

    mkdir 'something';
    cp 'foo', 'bar', 'something';
    ok( -e 'something/foo' );
    ok( -e 'something/bar' );

    rm_f 'something/*';
    ok( !-e 'something/foo' );
    ok( !-e 'something/bar' );

    mv 'foo', 'bar', 'something';
    ok( -e 'something/foo' );
    ok( -e 'something/bar' );
    ok( !-e 'foo' );
    ok( !-e 'bar' );

    rm_rf 'something';
    ok( !-e 'something' );
}

{
    ok( !-e 'this' );
    mkdir_p 'this/that';
    ok( -e 'this/that' );

    rm_rf('this/that');
}

{
    touch 'foo', 'bar';
    ok( -e 'bar' );
    symlink_f 'foo', 'bar';
    ok( -l 'bar' );
}
