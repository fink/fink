#!/usr/bin/perl
# -*- mode: Perl; tab-width: 4; -*-
# vim: ts=4 sw=4 noet

use strict;
use warnings;
use Test::More tests => 13;

my $baseclass = 'Fink::SelfUpdate::Base';
require_ok($baseclass);  # test #1

# check that each loads and has all expected methods (4 classes x 3 tests)
foreach my $subclass (qw/ Base CVS point rsync /) {
	my $class = "Fink::SelfUpdate::$subclass";

	require_ok($class);

	isa_ok( bless({}, $class), $baseclass );

	can_ok($class, (qw(
		description
		system_check
		clear_metadata
		do_direct
		update_version_file
	)));
}
