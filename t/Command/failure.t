#!/usr/bin/perl -w

# Test the return values of Fink::Command functions when they fail.

use Test::More 'no_plan';

use Fink::Command qw(:ALL);

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
    cmp_ok( $!, '!=', 0 ); 

    ok( !mkdir_p('foo', 'bar'), '          one failure, one success' );
    ok( -d 'bar' );

    unlink 'foo';
    rm_rf 'bar';
}


SKIP: {
    skip "You must be root", 5 unless $> == 0;

    mkdir 'foo';
    mkdir 'bar';

    chmod 0600, 'foo';
    chmod 0777, 'bar';
    chowname 'nobody:nobody', 'bar';
    touch 'bar/baz';
    chowname 'nobody:nobody', 'bar/baz';
    chmod 0666, 'bar/baz';

    # drop privledges
    local $> = -2;
    local $< = -2;  

    $! = 0;
    ok( !rm_rf('foo') );
    cmp_ok( $!, '!=', 0 );

    $! = 0;
    ok( rm_rf('foo', 'bar/baz') );
    cmp_ok( $!, '!=', 0 );
    ok( !-e 'bar/baz' );
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

    touch 'foo';
    chmod 0400, 'foo';
    my $mtime = (stat 'foo')[9];

    # drop privs
    local $> = -2;
    local $< = -2;

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
    skip "You must be root", 2
      unless $> == 0;

    touch 'foo';
    chmod 0400, 'foo';

    # drop privs
    local $> = -2;
    local $< = -2;

    touch 'bar';

    $! = 0;
    ok( !symlink 'bar', 'foo' );
    cmp_ok( $!, '!=', 0 );
}
unlink 'foo', 'bar';

    
