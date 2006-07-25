#!/usr/bin/perl -w
# -*- mode: Perl; tab-width: 4; -*-
# vim: ts=4 sw=4 noet

use strict;
use Test::More tests => 2;


SKIP: {
	skip "You must be root for this test", 2 if $> != 0;

	# put a recognizable unique token in PERL5LIB
	my $path = sprintf '/foofoo.%i.%i', $$, time;
	skip "$path is already in PERL5LIB", 2 if defined $ENV{PERL5LIB} && $ENV{PERL5LIB} =~ /(\A|:)$path(:|\Z)/;
	$ENV{PERL5LIB} = defined $ENV{PERL5LIB} ? "$ENV{PERL5LIB}:$path" : $path;

	foreach my $sudo_method (
		[ '/usr/bin/sudo', '/usr/bin/sudo' ],
		[ 'sudo', "first 'sudo' in PATH=$ENV{PATH}" ],
	) {
		my @vars = qx{ $sudo_method->[0] /usr/bin/env };
		chomp @vars;
		my %sudo_env = map { $_ =~ /^([^=]+)=(.*)$/ } @vars;
		ok defined $sudo_env{PERL5LIB} && $sudo_env{PERL5LIB} =~ /(\A|:)$path(:|\Z)/, "PERL5LIB propagation through sudo ($sudo_method->[1])";
	}
}
