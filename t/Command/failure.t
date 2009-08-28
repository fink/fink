#!/usr/bin/perl -w

# Test the return values of Fink::Command functions when they fail.

use strict;
use Test::More 'no_plan';

use Fink::Command qw(:ALL);
use Fink::Services;

($<,$>) = (0,0) if $< == 0 or $> == 0;

my $Unprivledged_UID = getpwnam('nobody') || getpwnam('unknown');

my $scratch_dir = 'Command/scratch';
mkdir_p $scratch_dir;
chmod 0755, $scratch_dir;
ok( chdir $scratch_dir );
END { chdir '../..';  rm_rf $scratch_dir }

{
    eval { mv() };
    like( $@, qr/^Insufficient arguments / );
    eval { mv 'foo' };
    like( $@, qr/^Insufficient arguments / );

    touch 'foo', 'bar', 'baz';
    eval { mv 'foo', 'bar', 'baz' };
    like( $@, qr/^Too many arguments / );
    unlink 'foo', 'bar', 'baz';

    $! = 0;
    ok( !mv('dont_exist', 'bar'),  'mv, no source, no dest' );
    ok( !-e 'bar' );
    cmp_ok( $!, '!=', 0 );

    mkdir 'bar';
    END { rm_rf 'bar' }
    ok( !mv('dont_exist', 'bar'),  '    no source' );

    $! = 0;
    touch 'foo';
    END { unlink 'foo' }
    ok( !mv('foo', 'dont_exist', 'bar'), '    one source missing' );
    cmp_ok( $!, '!=', 0 );
    ok( -e 'bar/foo' );
    ok( !-e 'foo' );
    unlink 'foo';
    rm_rf 'bar';
}

{
    eval { cp() };
    like( $@, qr/^Insufficient arguments / );
    eval { cp 'foo' };
    like( $@, qr/^Insufficient arguments / );

    touch 'foo', 'bar', 'baz';
    eval { cp 'foo', 'bar', 'baz' };
    like( $@, qr/^Too many arguments / );
    unlink 'foo', 'bar', 'baz';


    $! = 0;
    ok( !cp('dont_exist', 'bar'),  'cp, no source, no dest' );
    ok( !-e 'bar' );
    cmp_ok( $!, '!=', 0 );

    mkdir 'bar';
    ok( !cp('dont_exist', 'bar'),  '    no source' );

    $! = 0;
    touch 'foo';
    ok( !cp('foo', 'dont_exist', 'bar'), '    one source missing' );
    cmp_ok( $!, '!=', 0 );
    ok( -e 'bar/foo' );

    unlink 'foo';
    rm_rf 'bar';
}

{
    $! = 0;
    touch 'foo';
    ok( !mkdir_p('foo'), 'mkdir_p: file already exists' );
TODO: {
    todo_skip "Fails if manual CPAN usage, not yet understood", 1;
    cmp_ok( $!, '!=', 0 ); 
    }

    ok( !mkdir_p('foo', 'bar'), '          one failure, one success' );
    ok( -d 'bar' );

    unlink 'foo';
    rm_rf 'bar';
}


SKIP: {
    skip "You must be root", 5 unless $> == 0;
    skip "Can't find an unprivledged user", 5 unless $Unprivledged_UID;

    mkdir 'foo';
    mkdir 'bar';

    chmod 0500, 'foo';
    chmod 0777, 'bar';
    chowname 'nobody:nobody', 'bar';
    touch 'bar/baz';
    chowname 'nobody:nobody', 'bar/baz';
    chmod 0666, 'bar/baz';

    # drop privledges
    local $> = $Unprivledged_UID;

    $! = 0;
    ok( !rm_rf('foo') );
    ok( -e 'foo' );
    cmp_ok( $!, '!=', 0 );

    $! = 0;
    ok( !rm_rf('bar/baz', 'foo') );
    cmp_ok( $!, '!=', 0 );
    ok( -e 'foo' );

TODO: {
    local $TODO;
    $TODO = "Fails on 10.6 during upgrade from older OS X" if Fink::Services::get_kernel_vers()==10;
    ok( !-e 'bar/baz' );
}
}
rm_rf 'foo';
rm_rf 'bar';



{
    mkdir 'foo';
    touch 'bar';

    $! = 0;
    ok( !rm_f 'foo' );
    TODO: {
        local $TODO = 'Unlinking a directory not setting $! when root' 
          if $> == 0;
        cmp_ok( $!, '!=', 0 );
    }
    ok( -e 'foo' );

    $! = 0;
    ok( !rm_f 'foo', 'bar' );

    TODO: {
        local $TODO = 'Unlinking a directory not setting $! when root' 
          if $> == 0;
        cmp_ok( $!, '!=', 0 );
    }
    ok( !-e 'bar' );

    rm_rf 'foo';
}

    

SKIP: {
    skip "You must be root", 2 unless $> == 0;
    skip "Can't find an unprivledged user", 2 unless $Unprivledged_UID;

    touch 'foo';
    chmod 0444, 'foo';
    my $mtime = (stat 'foo')[9];
    is( (stat 'foo')[2] & 0777, 0444, 'chmod succeeded' );

    # drop privs
    local $> = $Unprivledged_UID;

    sleep 1;
    ok( !touch 'foo' );
    is( (stat 'foo')[9], $mtime );
}
unlink 'foo';


{
    my $user  = getpwuid($>);
    my $group = getgrgid($));

    ok( !chowname "$user:$group", "dontexist" );

    touch "foo";
    ok( !chowname "$user:$group", "dontexist", "foo" );

    ok( !chowname("lakjflj", "foo") );
    ok( !chowname(":lakjflj", "foo") );
    ok( !chowname("lkasjdlfkj:lakjflj", "foo") );

    unlink 'foo';
}


SKIP: {
    skip "You must be root", 2 unless $> == 0;
    skip "Can't find an unprivledged user", 2 unless $Unprivledged_UID;

    touch 'foo';
    chmod 0444, 'foo';

    # drop privs
    local $> = $Unprivledged_UID;

    touch 'bar';

    $! = 0;
    ok( !symlink 'bar', 'foo' );
    cmp_ok( $!, '!=', 0 );
}
unlink 'foo', 'bar';

    
