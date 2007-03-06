#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 13;

my $baseclass = 'Fink::SelfUpdate::Base';
require_ok($baseclass);  # test #1

# check that each can be loaded and has all expected methods (4x3 tests)
foreach my $subclass (qw/ CVS point rsync tarball /) {
    my $class = "Fink::SelfUpdate::$subclass";

    require_ok($class);

    isa_ok( bless({}, $class), $baseclass );

    can_ok($class, qw/ clear_metadata stamp_set stamp_clear stamp_check /);
}
