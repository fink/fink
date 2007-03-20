# -*- mode: Perl; tab-width: 4; -*-
# vim: ts=4 sw=4 noet
#
# Fink::SelfUpdate::rsync class
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

package Fink::SelfUpdate::rsync;

use base qw(Fink::SelfUpdate::Base);

use Fink::CLI qw(&print_breaking);
use Fink::Config qw($basepath $config $distribution);
use Fink::Mirror;
use Fink::Package;
use Fink::Command qw(chowname rm_f mkdir_p touch);

use strict;
use warnings;

=head1 NAME

Fink::SelfUpdate::rsync - download package descriptions from an rsync server

=head1 DESCRIPTION

=head2 Public Methods

See documentation for the Fink::SelfUpdate base class.

=cut

sub system_check {
	my $class = shift;  # class method for now

	# We temporarily disable rsync updating for 10.5, until we've decided how to handle it
	if ($distribution eq '10.5') {
		warn "Sorry, fink doesn't support rsync updating in the 10.5 distribution at present.\n";
		return 0;
	}

	if (not Fink::VirtPackage->query_package("dev-tools")) {
		warn "Selfupdate method 'rsync' requires the package 'dev-tools'\n";
		return 0;
	}

	return 1;
}

sub stamp_set {
	my $class = shift;  # class method for now

	my $finkdir = "$basepath/fink";
	touch "$finkdir/dists/stamp-rsync-live";
}

sub stamp_clear {
	my $class = shift;  # class method for now

	my $finkdir = "$basepath/fink";
	rm_f "$finkdir/stamp-rsync-live", "$finkdir/dists/stamp-rsync-live";
}

sub stamp_check {
	my $class = shift;  # class method for now

	my $finkdir = "$basepath/fink";
	return (-f "$finkdir/stamp-rsync-live" || -f "$finkdir/dists/stamp-rsync-live");
}

sub do_direct {
	my $class = shift;  # class method for now

	my $dist = $distribution;

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
		if ($oldts =~ /\D/) {
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

	# If the Distributions line has been updated...
	if (! -d "$descdir/$dist") {
		mkdir_p "$descdir/$dist";
	}
	my @sb = stat("$descdir/$dist");

	# We need to remove the CVS directories, since what we're
	# going to put there isn't from cvs.  Leaving those directories
	# there will thoroughly confuse things if someone later does 
	# selfupdate-cvs.  However, don't actually do the removal until
	# we've tried to put something there.
	
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
	} else {
		foreach my $tree (@trees) {
			&execute("/usr/bin/find '$basepath/fink/$dist/$tree' -name CVS -type d -print0 | xargs -0 /bin/rm -rf");
		}
	}

	$class->stamp_set();

	# cleanup after ourselves
	unlink "$descdir/TIMESTAMP";
	rename "$descdir/TIMESTAMP.tmp", "$descdir/TIMESTAMP";
}

=head2 Private Methods

None yet.

=over 4

=back

=cut

1;
