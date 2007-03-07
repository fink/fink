#!/usr/bin/perl
# -*- mode: Perl; tab-width: 4; -*-
# vim: ts=4 sw=4 noet

use strict;
use warnings;
use Test::More tests => 10;

my $baseclass = 'Fink::SelfUpdate::Base';
require_ok($baseclass);  # test #1

# check that each can be loaded and has all expected methods (3x3 tests)
foreach my $subclass (qw/ CVS point rsync /) {
	my $class = "Fink::SelfUpdate::$subclass";

	require_ok($class);

	isa_ok( bless({}, $class), $baseclass );

	can_ok($class, qw/ clear_metadata stamp_set stamp_clear stamp_check /);
}
