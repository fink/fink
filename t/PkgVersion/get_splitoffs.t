#!/usr/bin/perl -w
# -*- mode: Perl; tab-width: 4; -*-

use strict;
use Test::More tests => 32;
use Fink::Services qw(read_properties);
use Fink::Config;

my $config = Fink::Config->new_with_path('basepath/etc/fink.conf');

require_ok('Fink::Package'); # 1
can_ok('Fink::Package', qw/
	   forget_packages
	   packages_from_info_file
	   insert_pkgversions
	   package_by_name
	   /); # 2

# $tests{$package} = \@results
# $results[n] is ordered for get_splitoffs(@$gsargs[n])
# gsargs sets are for PkgVersion::get_splitoffs, which is prototyped as:
#   ($include_parent, $include_self)
my @gsargs = ( [0,0], [0,1], [1,0], [1,1] );
my %tests = (
			 'p1'    => [ "",            "",            "",            "p1" ],

			 'p2'    => [ "p2.s1",       "p2.s1",       "p2.s1",       "p2 p2.s1" ],
			 'p2.s1' => [ "",            "p2.s1",       "p2",          "p2 p2.s1" ],

			 'p3'    => [ "p3.s1 p3.s2", "p3.s1 p3.s2", "p3.s1 p3.s2", "p3 p3.s1 p3.s2" ],
			 'p3.s1' => [ "p3.s2",       "p3.s1 p3.s2", "p3 p3.s2",    "p3 p3.s1 p3.s2" ],
			 'p3.s2' => [ "p3.s1",       "p3.s1 p3.s2", "p3 p3.s1",    "p3 p3.s1 p3.s2" ],
		 );

Fink::Package->forget_packages();
foreach (qw/ p1 p2 p3 / ) {
	Fink::Package->insert_pkgversions(
		Fink::PkgVersion->pkgversions_from_info_file(
			"PkgVersion/get_splitoffs-tree/finkinfo/$_.info"));
}
print "Loaded our .info files\n";

foreach my $name (sort keys %tests) {
	my $po = Fink::Package->package_by_name($name);
	ok(defined $po, "Package for $name"); # 3 8 13 18 23 28
	my ($pvo) = $po->get_all_versions();
	for (my $argset = 0; $argset < @gsargs; $argset++) {
		my @args = @{$gsargs[$argset]};
		my $wanted = join ' ', $tests{$name}->[$argset];
		my $result = join ' ', map $_->get_name, $pvo->get_splitoffs(@args);
		is($result, $wanted, "$name->get_splitoffs(".join(',',@args).")"); # 4 test per $name
	}
}
