#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';

require_ok('Fink::Notify');

{
    package Foo;
    Fink::Notify->import;
    ::is_deeply( \%Foo::, {}, 'exports nothing by default' );
}
