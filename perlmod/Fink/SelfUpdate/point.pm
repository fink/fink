# -*- mode: Perl; tab-width: 4; -*-
# vim: ts=4 sw=4 noet
#
# Fink::SelfUpdate::point class
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2011 The Fink Package Manager Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110, USA.
#

package Fink::SelfUpdate::point;

use base qw(Fink::SelfUpdate::Base);

use Fink::Services qw(&version_cmp &execute &filename);
use Fink::CLI qw(&print_breaking);
use Fink::Config qw($basepath $config $distribution);
use Fink::NetAccess qw(&fetch_url &fetch_url_to_file);
use Fink::Command qw(cat);

use strict;
use warnings;

our $VERSION = 1.00;

=head1 NAME

Fink::SelfUpdate::point - download package descriptions for a point release

=head1 DESCRIPTION

=head2 Public Methods

See documentation for the Fink::SelfUpdate base class.

=over 4

=cut

sub description {
	my $class = shift;  # class method for now

	return 'Stick to point releases';
}

=item system_check

point method cannot remove .info files, so we don't support using
point if some other method has already been used.

=cut

sub system_check {
	my $class = shift;  # class method for now

	my $default_method = lc($config->param_default( 'SelfUpdateMethod', '' ));
	if (length $default_method and $default_method ne 'point') {
		warn "Fink does not presently support switching to selfupdate-point from any other selfupdate method\n";
		return 0;
	}

	return 1;
}

=item do_direct

Returns point version string.

=cut

sub do_direct {
	my $class = shift;  # class method for now

	# get the file with the current release number
	my $currentfink;
	$currentfink = "CURRENT-FINK-$distribution";
	### if we are in 10.1, need to use "LATEST-FINK" not "CURRENT-FINK"
	if ($distribution eq "10.1") {
		$currentfink = "LATEST-FINK";
	}
	my $website = "http://www.finkproject.org";
	if (-f "$basepath/lib/fink/URL/website") {
		$website = cat "$basepath/lib/fink/URL/website";
		chomp($website);
	}
	my $srcdir = "$basepath/src";
# we now use &fetch_url_to_file so that we can pass the option
# 'try_all_mirrors' which forces re-download of the file even if it already
# exists
	my $urlhash;
	$urlhash->{'url'} = "$website/$currentfink";
	$urlhash->{'filename'} = &filename("$website/$currentfink");
	$urlhash->{'skip_master_mirror'} = 1;
	$urlhash->{'download_directory'} = $srcdir;
	$urlhash->{'try_all_mirrors'} = 1;
	if (&fetch_url_to_file($urlhash)) {
		die "Can't get latest version info\n";
	}
	my $latest_fink = cat "$srcdir/$currentfink";
	chomp($latest_fink);

	require Fink::SelfUpdate;
	my @last_selfupdate = &Fink::SelfUpdate::last_done;
	if ($last_selfupdate[0] ne 'point') {
			print "\n";
			&print_breaking('Fink does not presently support switching to selfupdate-point from any other selfupdate method');
			return;
	}
	
	if (&version_cmp($latest_fink . '-1', '<=', $distribution . '-' . $last_selfupdate[2] . '-1')) {
		print "\n";
		&print_breaking("You already have the package descriptions ".
						"from the latest Fink point release. ".
						"(installed:$distribution-$last_selfupdate[2] ".
						"available:$latest_fink)\n\n" .
						"If you wish to change your update method to ".
						"one which updates more frequently, run ".
						"the command 'fink selfupdate-rsync'.");
		return;
	}
	
	my $newversion = $latest_fink;
	my ($downloaddir, $dir);
	my ($pkgtarball, $url, $verbosity, $unpack_cmd);

	print "\n";
	&print_breaking("I will now download the package descriptions for ".
					"Fink $newversion and update the core packages. ".
					"After that, you should update the other packages ".
					"using commands like 'fink update-all'.");
	print "\n";

	$downloaddir = "$basepath/src";
	chdir $downloaddir or die "Can't cd to $downloaddir: $!\n";

	# go ahead and upgrade
	# first, download the packages tarball
	$dir = "dists-$newversion";

	### if we are in 10.1, need to use "packages" not "dists"
	if ($distribution eq "10.1") {
			$dir = "packages-$newversion";
	}
	
	$pkgtarball = "$dir.tar.gz";
	$url = "mirror:sourceforge:fink/$pkgtarball";

	if (not -f $pkgtarball) {
		if (&fetch_url($url, $downloaddir)) {
			die "Downloading the update tarball '$pkgtarball' from the URL '$url' failed.\n";
		}
	}

	# unpack it
	if (-e $dir) {
		rm_rf $dir or
			die "can't remove existing directory $dir\n";
	}

	$verbosity = "";
	if ($config->verbosity_level() > 1) {
		$verbosity = "v";
	}
	$unpack_cmd = "tar -xz${verbosity}f $pkgtarball";
	if (&execute($unpack_cmd)) {
		die "unpacking $pkgtarball failed\n";
	}

	# inject it
	chdir $dir or die "Can't cd into $dir: $!\n";
	if (&execute("./inject.pl $basepath -quiet")) {
		die "injecting the new package definitions from $pkgtarball failed\n";
	}
	chdir $downloaddir or die "Can't cd to $downloaddir: $!\n";
	if (-e $dir) {
		rm_rf $dir;
	}

	$class->update_version_file(data => $newversion);
	return 1;
}

=back

=head2 Private Methods

None yet.

=over 4

=back

=cut

1;
