#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';
use Fink::Config qw($basepath);

my $config = Fink::Config->new_with_path('basepath/etc/fink.conf');

require_ok('Fink::Package');

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
		Fink::Package->scan("Package/duplicate_fullname_trees/$_")
			foreach @{$test->{trees}};
	};
	if (!$@ && scalar(Fink::Package->list_packages())) {
		ok($test->{works}, "Scanning " . $test->{msg} . " succeeded");
	} else {
		ok(!$test->{works}, "Scanning " . $test->{msg} . " failed: $@");
	}
}
