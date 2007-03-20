#!/usr/bin/perl
# -*- mode: Perl; tab-width: 4; -*-
# vim: ts=4 sw=4 noet

use strict;
use warnings;
use Test::More tests => 6;
use File::Temp (qw/ tempdir /);
use Fink::Command (qw/ mkdir_p /);
use Fink::Config;

# create a temp fink hierarchy
my $basepath = tempdir('last_done.t_XXXXX', DIR=>'/tmp', CLEANUP=>1);
mkdir_p "$basepath/fink/10.4", "$basepath/etc";
my $config = Fink::Config->new_from_properties({
	'basepath'     => $basepath,
	'distribution' => '10.4',
});

require_ok('Fink::SelfUpdate');;

{
	my @last;
	@last = &Fink::SelfUpdate::last_done;
	is($last[0], undef, 'gives undef if no such file');

	_write_vfile('0.8.1');
	@last = &Fink::SelfUpdate::last_done;
	is($last[0], undef, 'gives undef if no SelfUpdate token');

	_write_vfile('0.8.1', 'SelfUpdate: cvs');
	@last = &Fink::SelfUpdate::last_done;
	is($last[0], undef, 'gives undef if malformed SelfUpdate token');

	_write_vfile('0.8.1', 'SelfUpdate: cvs@1174360777');
	@last = &Fink::SelfUpdate::last_done;
	is($last[0], 'cvs', 'gives correct SelfUpdate method');
	is($last[1], '1174360777', 'gives correct SelfUpdate timestamp');
}

sub _write_vfile {
	my @lines = @_;
	chomp @lines;

	my $vfile = "$basepath/fink/10.4/VERSION";
	open my $FH, '>', $vfile or die "Could not write $vfile: $!\n";
	print $FH map "$_\n", @_;
	close $FH;
}
