#!/usr/bin/perl -w

package My::Fink;

use Test::More tests => 5;

require_ok('Fink::Base');
@ISA = qw(Fink::Base);

my $init_called = 0;
sub initialize { $init_called++ }

isa_ok( My::Fink->new(), 'My::Fink', 'new()' );
is( $init_called, 1, 'initialize called' );
isa_ok( My::Fink->new_from_properties({}), 'My::Fink', 
                                        'new_from_properties()' );
is( $init_called, 2, 'initialize called' );

