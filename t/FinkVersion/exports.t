#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';

require_ok('Fink::FinkVersion');

{
    package Foo;
    Fink::FinkVersion->import;
    ::is_deeply( \%Foo::, {}, 'exports nothing by default' );
}

{
    package Bar;
    Fink::FinkVersion->import(':ALL');
    ::can_ok( __PACKAGE__, qw(fink_version) );
}

