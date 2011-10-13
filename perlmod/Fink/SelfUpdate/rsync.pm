# -*- mode: Perl; tab-width: 4; -*-
# vim: ts=4 sw=4 noet
#
# Fink::SelfUpdate::rsync class
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

package Fink::SelfUpdate::rsync;

use base qw(Fink::SelfUpdate::Base);

use Fink::CLI qw(&print_breaking);
use Fink::Config qw($basepath $config $distribution);
use Fink::Mirror;
use Fink::Package;
use Fink::Command qw(chowname rm_f mkdir_p touch);
use Fink::Services qw(&execute);

use strict;
use warnings;

our $VERSION = 1.00;

=head1 NAME

Fink::SelfUpdate::rsync - download package descriptions from an rsync server

=head1 DESCRIPTION

=head2 Public Methods

See documentation for the Fink::SelfUpdate base class.

=over 4

=item system_check

This method builds packages from source, so it requires the
"dev-tools" virtual package.

=cut

sub system_check {
	my $class = shift;  # class method for now

	if (not Fink::VirtPackage->query_package("dev-tools")) {
		warn "Before changing your selfupdate method to 'rsync', you must install XCode, available on your original OS X install disk, or from http://connect.apple.com (after free registration).\n";
		return 0;
	}

	return 1;
}

=item do_direct

Returns a null string.

=cut

sub do_direct {
	my $class = shift;  # class method for now

	my @dists = ($distribution);

	{
		my $temp_dist = $distribution;

		# workaround for people who upgraded to 10.5 without a fresh bootstrap
		if (not $config->has_param("SelfUpdateTrees")) {
			$temp_dist = "10.4" if ($temp_dist ge "10.4");
		}
		$temp_dist = $config->param_default("SelfUpdateTrees", $temp_dist);
		@dists = split(/\s+/, $temp_dist);
	}

	# add rsync quiet flag if verbosity level permits
	my $verbosity = "-q";
	if ($config->verbosity_level() > 1) {
		$verbosity = "-v";
	}

	# get a needed filesystem-specific flag for the rsync command
	my $nohfs ="";
	if (system("rsync -help 2>&1 | grep 'nohfs' >/dev/null") == 0) {
		$nohfs = "--nohfs";
	}

	my $descdir = "$basepath/fink";
	chdir $descdir or die "Can't cd to $descdir: $!\n";


	my $origmirror = Fink::Mirror->get_by_name("rsync");
	my $rsynchost;

RSYNCAGAIN:
	$rsynchost = $origmirror->get_site_retry("", 0);
	if( !grep(/^rsync:/,$rsynchost) ) {
		print "No mirror worked. This seems unusual, please submit a short summary of this event to mirrors\@finkmirrors.net\n Thank you\n";
		exit 1;
	}

	# Fetch the timestamp for comparison
	if (&execute("rsync -az $verbosity $nohfs $rsynchost/TIMESTAMP $descdir/TIMESTAMP.tmp")) {
		print "Failed to fetch the timestamp file from the rsync server: $rsynchost.  Check the error messages above.\n";
		goto RSYNCAGAIN;
	}
	# If there's no TIMESTAMP file, then we haven't synced from rsync
	# before, so there's no checking we can do.  Blaze on past.
	if ( -f "$descdir/TIMESTAMP" ) {
		my $ts_FH;
		open $ts_FH, '<', "$descdir/TIMESTAMP";
		my $oldts = <$ts_FH>;
		close $ts_FH;
		chomp $oldts;
		# Make sure the timestamp only contains digits
		if ($oldts =~ /\D/) {
			unlink("$descdir/TIMESTAMP.tmp");
			die "The timestamp file $descdir/TIMESTAMP contains non-numeric characters.  This is illegal.  Refusing to continue.\n";
		}

		open $ts_FH, '<', "$descdir/TIMESTAMP.tmp";
		my $newts = <$ts_FH>;
		close $ts_FH;
		chomp $newts;
		# Make sure the timestamp only contains digits
		if ($newts =~ /\D/) {
			unlink("$descdir/TIMESTAMP.tmp");
			die "The timestamp file fetched from $rsynchost contains non-numeric characters.  This is illegal.  Refusing to continue.\n";
		}
		
		if ( $oldts > $newts ) {
			# error out complaining that we're trying to update
			# from something older than what we already have.
			unlink("$descdir/TIMESTAMP.tmp");
			print "The timestamp of the server is older than what you already have.\n";
			exit 1;
		}

	} 

	for my $dist (@dists) {

		# If the Distributions line has been updated...
		if (! -d "$descdir/$dist") {
			mkdir_p "$descdir/$dist";
		}
		my @sb = stat("$descdir/$dist");
	
		$rsynchost =~ s/\/*$//;
		$dist      =~ s/\/*$//;
		
		my $rinclist = "";
		
		my @trees = grep { m,^(un)?stable/, } $config->get_treelist();
		die "Can't find any trees to update\n" unless @trees;
		map { s/\/*$// } @trees;
		
		foreach my $tree (@trees) {
			my $oldpart = $dist;
			my @line = split /\//,$tree;
	
			$rinclist .= " --include='$dist/'";
			for(my $i = 0; defined $line[$i]; $i++) {
				$oldpart = "$oldpart/$line[$i]";
				$rinclist .= " --include='$oldpart/'";
			}
			$rinclist .= " --include='$oldpart/finkinfo/' --include='$oldpart/finkinfo/*/' --include='$oldpart/finkinfo/*' --include='$oldpart/finkinfo/**/*'";
	
			if (! -d "$basepath/fink/$dist/$tree" ) {
				mkdir_p "$basepath/fink/$dist/$tree";
			}
		}
		my $cmd = "rsync -rtz --delete-after --delete $verbosity $nohfs $rinclist --include='VERSION' --include='DISTRIBUTION' --include='README' --exclude='**' '$rsynchost' '$basepath/fink/'";
		if ($sb[4] != 0 and $> != $sb[4]) {
			my $username;
			($username) = getpwuid($sb[4]);
			if ($username) {
				$cmd = "/usr/bin/su $username -c \"$cmd\"";
				chowname $username, "$basepath/fink/$dist";
			}
		}
		&print_breaking("I will now run the rsync command to retrieve the latest package descriptions. \n");
	
		if (&execute($cmd)) {
			print "Updating using rsync failed. Check the error messages above.\n";
			goto RSYNCAGAIN;
		}
	}

	# cleanup after ourselves
	unlink "$descdir/TIMESTAMP";
	rename "$descdir/TIMESTAMP.tmp", "$descdir/TIMESTAMP";

	$class->update_version_file();
	return 1;
}

=back

=head2 Private Methods

None yet.

=over 4

=back

=cut

1;
