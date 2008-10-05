#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';

require_ok('Fink::Validation');

{
    package Foo;
    Fink::Validation->import;
    ::is_deeply( \%Foo::, {}, 'exports nothing by default' );
}

use_ok( 'Fink::Validation', qw(&validate_info_file &validate_dpkg_file &validate_dpkg_unpacked) );
