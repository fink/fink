#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';

require_ok('Fink::Base');

isa_ok( Fink::Base->new(), 'Fink::Base', 'new' );

my $fb = Fink::Base->new_from_properties({ foo => "ugg", 
                                           bar => 0, 
                                           _wiffle => "something",
                                           baz => undef
                                         });
isa_ok( $fb, 'Fink::Base', 'new_from_properties' );

is( $fb->param("foo"), 'ugg' );
is( $fb->param("bar"), 0 );

# XXX Fink::Base seems to equate undef with the parameter not existing.
# set_param() will delete a parameter if its set to undef or "" but
# new_from_properties() will gladly accept it.  Bug?
is( $fb->param("baz"), undef, 'handles undef' );

ok( !$fb->has_param("_wiffle"), 'new_from_properties() ignores _ keys' );
ok( $fb->has_param("foo") );

is( $fb->param_default("dontexist", "foo"), "foo" );
is( $fb->param_default("dontexist"), "", 'param_default + forgotten arg' );

# XXX should this happen or should it be set to undef?
is( $fb->param_default("dontexist", undef), "", 'param_default + undef' );

is( $fb->param_default("foo", 23), 'ugg' );
is( $fb->param_default("foo"),     'ugg' );


$fb->set_param('foo', undef);
ok( !$fb->has_param('foo') );
$fb->set_param('bar', '');
ok( !$fb->has_param('bar') );
