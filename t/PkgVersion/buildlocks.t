#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';

require_ok('Fink::PkgVersion');

# API function check

can_ok('Fink::PkgVersion','set_buildlock');
can_ok('Fink::PkgVersion','clear_buildlock');

# dpkg needs BDO pkgs
{
my $prog = 'fink-virtual-pkgs';
my $path;
foreach ('.', '..') {
    # test could run with PWD as parent of t/ or t/ itself
    if (-r "$_/$prog") {
	$path = $_;
	last;
    }
}
ok(defined $path, "locating $prog");

my( @result, @vers );
@result = `/usr/bin/perl $path/$prog --version`;
foreach (@result) {
    last if (@vers = /$prog revision (\d+)\.(\d+)/) == 2;  # get major.minor
}
ok(defined $vers[0] && defined $vers[1], "Parse revision of:\n@result");
### FIXME don't commit this to head, it's just for this branch
ok($vers[0] > 1 || ($vers[0] == 1 && $vers[1] >= 2), "$prog revision $vers[0].$vers[1] >= 1.2\n");
}
