#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';

require_ok('Fink::Mirror');

{
    package Foo;
    Fink::Mirror->import;
    ::is_deeply( \%Foo::, {}, 'exports nothing by default' );
}
