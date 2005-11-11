#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';
use Fink::Config qw($basepath);

my $config = Fink::Config->new_with_path('basepath/etc/fink.conf');

require_ok('Fink::Package');
require_ok('Fink::PkgVersion');

my @tests = (
	{	trees => [ qw(epoch1) ],				works => 1,
		msg => "just one package"
	},
	{	trees => [ qw(epoch1 epoch1again) ],	works => 1,
		msg => "two indentical packages"
	},
	{	trees => [ qw(epoch1 epoch2) ],			works => 0,
	  	msg => "different epochs, same fullname"
	},
);

for my $test (@tests) {
	Fink::Package->forget_packages();
	eval {
		foreach ( @{$test->{trees}} ) {
			my $file = "Package/duplicate_fullname_trees/$_/finkinfo/" .
				"duplicate-fullname.info";
			my @pv = Fink::PkgVersion->pkgversions_from_info_file($file);
			Fink::Package->insert_pkgversions(@pv);
		}
	};
	if (!$@ && scalar(Fink::Package->list_packages())) {
		ok($test->{works}, "Scanning " . $test->{msg} . " succeeded");
	} else {
		ok(!$test->{works}, "Scanning " . $test->{msg} . " failed: $@");
	}
}
