#!/usr/bin/perl
# -*- mode: Perl; tab-width: 4; -*-
# vim: ts=4 sw=4 noet

use strict;
use warnings;
use Test::More tests => 15;
use File::Temp (qw/ tempdir /);
use Fink::CLI (qw/ capture /);
use Fink::Command (qw/ mkdir_p /);
use Fink::Config;

# create a temp fink hierarchy
my $basepath = tempdir('last_done.t_XXXXX', DIR=>'/tmp', CLEANUP=>1);
mkdir_p "$basepath/fink/10.4", "$basepath/etc";
my $config = Fink::Config->new_from_properties({
	'basepath'     => $basepath,
	'distribution' => '10.4',
});

require_ok('Fink::SelfUpdate');  # test #1

{
	my @last;

	# test #2-3
	_write_vfiles(['0.8.1.cvs']);
	@last = &Fink::SelfUpdate::last_done;
	is($last[0], 'cvs', 'gives "cvs" method for VERSION with .cvs flag');
	is($last[2], '0.8.1', 'gives correct version for VERSION with .cvs flag');

	# test #4-5
	_write_vfiles(['0.8.1.rsync']);
	@last = &Fink::SelfUpdate::last_done;
	is($last[0], 'rsync', 'gives "rsync" method for VERSION with .rsync flag');
	is($last[2], '0.8.1', 'gives correct version for VERSION with .rsync flag');

	# test #6-7
	_write_vfiles(['0.8.1']);
	@last = &Fink::SelfUpdate::last_done;
	is($last[0], 'point', 'gives "point" correct method for VERSION with no method flag');
	is($last[2], '0.8.1', 'gives correct version for VERSION with no method flag');

	# test #8-9
	_write_vfiles(['0.8.1'], ['hi mom']);
	{
		my $output;
		capture sub { @last = &Fink::SelfUpdate::last_done; }, \$output, \$output;
	}
	is($last[0], 'point', 'gives correct method for VERSION if VERSION.selfupdate is useless');
	is($last[2], '0.8.1', 'gives correct version for VERSION if VERSION.selfupdate is useless');

	# test #10-11
	_write_vfiles(['0.8.1.rsync'], ['SelfUpdate: cvs@1174360777']);
	@last = &Fink::SelfUpdate::last_done;
	is($last[0], 'cvs', 'gives correct method for VERSION.selfupdate');
	is($last[1], '1174360777', 'gives correct timestamp for VERSION.selfupdate');

	# test #12-14
	_write_vfiles(['0.8.1.rsync'], ['SelfUpdate: cvs@1174360777 foo bar']);
	@last = &Fink::SelfUpdate::last_done;
	is($last[0], 'cvs', 'gives correct method for VERSION.selfupdate');
	is($last[1], '1174360777', 'gives correct timestamp for VERSION.selfupdate');
	is($last[2], 'foo bar', 'gives correct extra data for VERSION.selfupdate');

	# test #15
	_write_vfiles(['0.8.1.rsync'], ['foo','SelfUpdate: cvs@1174360777','bar']);
	@last = &Fink::SelfUpdate::last_done;
	is($last[0], 'cvs', 'gives correct method for multiline VERSION.selfupdate');
}

sub _write_vfiles {
	my $lines_old = shift;
	my $lines_new = shift;
	
	my $vfile_old = "$basepath/fink/10.4/VERSION";
	my $vfile_new = "$basepath/fink/10.4/VERSION.selfupdate";

	unlink $vfile_old, $vfile_new;
	_write_file($vfile_old, @$lines_old) if defined $lines_old;
	_write_file($vfile_new, @$lines_new) if defined $lines_new;
}
sub _write_file {
	my $file = shift;
	my @lines = @_;
	chomp @lines;

	open my $FH, '>', $file or die "Could not write $file: $!\n";
	print $FH map "$_\n", @_;
	close $FH;
}
