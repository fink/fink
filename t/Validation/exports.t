#!/usr/bin/perl
use warnings;
use strict;

use Test::More 'no_plan';
use Data::Dumper;

use_ok( 'Fink::Validation', qw(&validate_info_file &validate_dpkg_file &validate_dpkg_unpacked) );
