# -*- mode: Perl; tab-width: 4; -*-
# vim: ts=4 sw=4 noet
#
# Fink::SelfUpdate::point class
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2007 The Fink Package Manager Team
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
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA	 02111-1307, USA.
#

package Fink::SelfUpdate::point;

use base qw(Fink::SelfUpdate::Base);

use Fink::Config qw($basepath $config $distribution);
use Fink::Command qw(cat);

use strict;
use warnings;

=head1 NAME

Fink::SelfUpdate::CVS - download package descriptions for a point release

=head1 DESCRIPTION

=head2 Public Methods

See documentation for the Fink::SelfUpdate base class.

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
	if (&fetch_url("$website/$currentfink", $srcdir)) {
		die "Can't get latest version info\n";
	}
	my $latest_fink = cat "$srcdir/$currentfink";
	chomp($latest_fink);
	if ( ! Fink::SelfUpdate::CVS->stamp_check() and ! Fink::SelfUpdate::rsync->stamp_check() ) {
		# no evidence of cvs or rsync selfupdates, so assume on-disk
		# package descriptions are a point/tarball release, therefore
		# can skip doing another point/tarball release if we already
		# have the latest release version
		my $installed_version = &pkginfo_version();
		if (&version_cmp($latest_fink . '-1', '<=', $distribution . '-' . $installed_version . '-1')) {
			print "\n";
			&print_breaking("You already have the package descriptions from ".
							"the latest Fink point release. ".
							"(installed:$installed_version available:$latest_fink)");
			return;
		}
	}
	Fink::SelfUpdate::CVS->stamp_clear();
	Fink::SelfUpdate::rsync->stamp_clear();
	Fink::SelfUpdate::CVS->clear_metadata();
	
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
}

=head2 Private Methods

None yet.

=over 4

=back

=cut

1;
