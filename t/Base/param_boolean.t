#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';

require_ok('Fink::Base');

my $fb = Fink::Base->new();

ok( !$fb->param_boolean("foo") );
ok( !$fb->param_boolean("bar") );
ok( !$fb->param_boolean("_dontexist") );

foreach my $true (qw(true yes on 1)) {
    foreach my $muckery (sub { $_[0] },
                         sub { "$_[0] " },
                         sub { " $_[0]" },
                         sub { " $_[0] " },
                         sub { ucfirst $_[0] },
                         sub { uc $_[0] },
                        )
    {
        my $val = $muckery->($true);
        $fb->set_param("this", $val);
        ok( $fb->has_param("this") );
        is( $fb->param("this"), $val, "'$val'" );
        ok( $fb->param_boolean("this") );
        $fb->set_param("this", undef);
        ok( !$fb->has_param("this") );
    }
}
