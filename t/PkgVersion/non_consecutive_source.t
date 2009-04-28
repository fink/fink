#!/usr/bin/perl -w

use strict;
use Test::More tests => 9;
use Fink::Services qw(read_properties);
use Fink::Config;

my $config = Fink::Config->new_with_path('basepath/etc/fink.conf');

require_ok('Fink::PkgVersion');	# 1

# Can't test validation?

my $pv = (Fink::PkgVersion->pkgversions_from_info_file(
	"PkgVersion/non-consecutive-test.info"
))[0];

isa_ok( $pv, "Fink::PkgVersion", "non-consecutive-test.info" );	# 2

my @sufs = $pv->get_source_suffixes;
is(scalar(@sufs), 2, "count doesn't depend on consec, 014 not found");			# 3
is($pv->get_source(), "non-consecutive-test-1.0.tar.gz",
	"implicit source is there");								# 4
is($pv->get_source(13),
	"http://www.example.com/non-consecutive-test-addons.tgz",
	"gets source by non-consec N");									# 5
is($pv->get_source(2), "none", "doesn't get source by position");	# 6
is($pv->get_checksum(13), 43, "gets checksums by N");				# 7

# Can anybody think of a good way to test TarFilesRename?

like($pv->get_tarball(), qr/gz$/,
	"can generate implicit tarball");								# 8

$pv = (Fink::PkgVersion->pkgversions_from_info_file(
	"PkgVersion/non-consecutive-test2.info"
))[0];
is($pv->get_source(),
	"mirror:gnu:non-consecutive-test2/non-consecutive-test2-1.0.tar.gz",
	"old gnu/gnome mirror syntax works");								# 9
