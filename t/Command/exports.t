#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';

require_ok('Fink::Command');

{
    package Foo;
    Fink::Command->import;
    ::is_deeply( \%Foo::, {}, 'exports nothing by default' );
}
