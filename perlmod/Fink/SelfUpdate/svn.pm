# -*- mode: Perl; tab-width: 4; -*-
# vim: ts=4 sw=4 noet
#
# Fink::SelfUpdate::svn class
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

package Fink::SelfUpdate::svn;

use base qw(Fink::SelfUpdate::Base);

use Fink::CLI qw(&print_breaking &prompt &prompt_selection);
use Fink::Config qw($basepath $config $distribution);
use Fink::Package;
use Fink::Command qw(cat chowname mkdir_p mv rm_f rm_rf touch);
use Fink::Services qw(&execute &version_cmp);

use File::Find;

use strict;
use warnings;

our $VERSION = 1.00;

=head1 NAME

Fink::SelfUpdate::svn - download package descriptions from a svn server

=head1 DESCRIPTION

=head2 Public Methods

See documentation for the Fink::SelfUpdate base class.

=over 4

=item system_check

This method builds packages from source, so it requires the
"dev-tools" virtual package.

=cut

sub system_check {
	require Fink::Config;
	my $class = shift;  # class method for now

	my ($line2,$line4)=("","");
	{
		my $osxversion=Fink::VirtPackage->query_package("macosx");
		if (&version_cmp ("$osxversion", "<<", "10.5")) {
			$line2="Xcode, available on your original OS X install disk, or from "; 
		} elsif (&version_cmp ("$osxversion", "<<", "10.6")) {
			$line2="Xcode, available on your original OS X install disk, from the App Store, or from ";
		} else {
			$line2="Xcode, or at least the Command Line Tools for Xcode, available from the App Store, or from ";
			$line4=". The Command Line Tools package is also available via the Downloads tab of the Xcode 4.3.x Preferences";
		}
	}

	if (not Fink::VirtPackage->query_package("dev-tools")) {
		warn "Before changing your selfupdate method to 'svn', you must install ".
		     $line2.
		     "http://connect.apple.com (after free registration)".
		     $line4.".\n";
		return 0;
	}

	my $svnpath;
	if (-x "$basepath/bin/svn") {
		$svnpath = $config->param_default("SvnPath", "$basepath/bin/svn");
	} else {
		$svnpath = $config->param_default("SvnPath", "/usr/bin/svn");
	}

	if (!(-x "$svnpath")) {
		warn "Before changing your selfupdate method to 'svn', you must install the svn package with 'fink install svn'.\n";
		return 0;
	}

	$config->set_param("SvnPath", $svnpath);
	$config->save;

	return 1;
}

sub clear_metadata {
	my $class = shift;  # class method for now

	my $finkdir = "$basepath/fink";
	if (-d "$finkdir.old") {
		die "There is a left-over \"$finkdir.old\" directory. You have to ".
			"move it out of the way before proceeding.\n";
	}
	&execute("/usr/bin/find $finkdir -name .svn -type d -print0 | xargs -0 /bin/rm -rf");
}

=item do_direct

Returns a null string.

=cut

sub do_direct {
	my $class = shift;  # class method for now

	if (-d "$basepath/fink/dists/.svn") {
		# already have a svn checkout
		$class->do_direct_svn();
	} else {
		$class->setup_direct_svn();
	}
	return 1;
}

=back

=head2 Private Methods

=cut

### set up direct svn

sub setup_direct_svn {
	my $class = shift;  # class method for now

	my ($finkdir, $tempdir, $tempfinkdir);
	my ($username, $svnuser, @testlist);
	my ($use_hardlinks, $cutoff, $cmd);
	my ($cmdd);

	$username = "root";
	if (exists $ENV{SUDO_USER}) {
		$username = $ENV{SUDO_USER};
	}

	print "\n";
	$username =
		&prompt("Fink has the capability to run the svn commands as a ".
				"normal user. That has some advantages - it uses that ".
				"user's svn settings files and allows the package ".
				"descriptions to be edited and updated without becoming ".
				"root. Please specify the user login name that should be ".
				"used:",
				default => $username);

	# sanity check
	@testlist = getpwnam($username);
	if (scalar(@testlist) <= 0) {
		die "The user \"$username\" does not exist on the system.\n";
	}

	print "\n";
	$svnuser =
		&prompt("For Fink developers only: ".
				"Enter your GitHub login name to set up full svn access. ".
				"Other users, just press return to set up anonymous ".
				"read-only access.",
				default => "anonymous");
	print "\n";

	# start by creating a temporary directory with the right permissions
	$finkdir = "$basepath/fink";
	$tempdir = "$finkdir.tmp";
	$tempfinkdir = "$tempdir/fink";

	if (-d "$finkdir.old") {
		die "There is a left-over \"$finkdir.old\" directory. You have to ".
			"move it out of the way before proceeding.\n";
	}

	if (-d $tempdir) {
		rm_rf $tempdir or
			die "Can't remove left-over temporary directory '$tempdir'\n";
	}
	mkdir_p $tempdir or
		die "Can't create temporary directory '$tempdir'\n";
	if ($username ne "root") {
		chowname $username, $tempdir or
			die "Can't set ownership of temporary directory '$tempdir'\n";
	}

	# check if hardlinks from the old directory work
	&print_breaking("Checking to see if we can use hard links to merge ".
					"the existing tree. Please ignore errors on the next ".
					"few lines.");
	unless (touch "$finkdir/README" and link "$finkdir/README", "$tempdir/README") {
		$use_hardlinks = 0;
	} else {
		$use_hardlinks = 1;
	}
	unlink "$tempdir/README";

	# start the svn fun
	chdir $tempdir or die "Can't cd to $tempdir: $!\n";

	# add svn quiet flag if verbosity level permits
	my $verbosity = "--quiet";
	if ($config->verbosity_level() > 1) {
		$verbosity = "";
	}
	my $svnpath = $config->param("SvnPath");
	my $svnrepository = "https://github.com/danielj7/fink-dists.git/trunk";
	if (-f "$basepath/lib/fink/URL/svn-repository") {
		$svnrepository = cat "$basepath/lib/fink/URL/svn-repository";
		chomp($svnrepository);
	}
	if ($svnuser eq "anonymous") {
		if (-f "$basepath/lib/fink/URL/anonymous-svn") {
			$svnrepository = cat "$basepath/lib/fink/URL/anonymous-svn";
			chomp($svnrepository);
		}
	} else {
		$svnrepository = 'https://USERNAME@github.com/danielj7/fink-dists.git/trunk';
		if (-f "$basepath/lib/fink/URL/developer-svn") {
			$svnrepository = cat "$basepath/lib/fink/URL/developer-svn";
			chomp($svnrepository);
		}
		$svnrepository =~ s/USERNAME/$svnuser/;
	}
	$cmd = "$svnpath ${verbosity}";
	$cmdd = "$cmd checkout --depth=files ${svnrepository} fink";
	if ($username ne "root") {
		$cmdd = "/usr/bin/su $username -c '$cmdd'";
	}
	&print_breaking("Setting up base Fink directory...");
	if (&execute($cmdd)) {
		die "Downloading package descriptions from svn failed.\n";
	}

	my @trees = split(/\s+/, $config->param_default("SelfUpdateTrees", $config->param_default("SelfUpdateCVSTrees", $distribution)));
	chdir "fink" or die "Can't cd to fink\n";

	for my $tree (@trees) {
		&print_breaking("Checking out $tree tree...");

		$cmdd = "$cmd update $tree";

		if ($username ne "root") {
			$cmdd = "/usr/bin/su $username -c '$cmdd'";
		}
		if (&execute($cmdd)) {
			die "Downloading package descriptions from svn failed.\n";
		}
	}
	chdir $tempdir or die "Can't cd to $tempdir: $!\n";

	if (not -d $tempfinkdir) {
		die "The svn didn't report an error, but the directory '$tempfinkdir' ".
			"doesn't exist as expected. Strange.\n";
	}

	&print_breaking("Merging old data to new tree...");
	# merge the old tree
	$cutoff = length($finkdir)+1;
	find(sub {
				 if ($_ eq ".svn") {
					 $File::Find::prune = 1;
					 return;
				 }
				 return if (length($File::Find::name) <= $cutoff);
				 my $rel = substr($File::Find::name, $cutoff);
				 if (-l and not -e "$tempfinkdir/$rel") {
					 my $linkto;
					 $linkto = readlink($_)
						 or die "Can't read target of symlink \"$File::Find::name\": $!\n";
					 symlink $linkto, "$tempfinkdir/$rel" or
						 die "Can't create symlink \"$tempfinkdir/$rel\": $!\n";
				 } elsif (-d and not -d "$tempfinkdir/$rel") {
					 &print_breaking("Merging $basepath/$rel...\n") 
					 	if ($config->verbosity_level() > 1);
					 mkdir_p "$tempfinkdir/$rel" or
						 die "Can't create directory \"$tempfinkdir/$rel\": $!\n";
				 } elsif (-f and not -f "$tempfinkdir/$rel") {
					 if ($use_hardlinks) {
						 if (not link "$_",  "$tempfinkdir/$rel") {
						 	die "Can't link file \"$_\" to \"$tempfinkdir/$rel\": $!\n";
						 }
					 } else {
						 if (&execute("cp -p '$_' '$tempfinkdir/$rel'")) {
							 die "Can't copy file \"$tempfinkdir/$rel\": $!\n";
						 }
					 }
				 }
			 }, $finkdir);

	# switch $tempfinkdir to $finkdir
	chdir $basepath or die "Can't cd to $basepath: $!\n";
	mv $finkdir, "$finkdir.old" or
		die "Can't move \"$finkdir\" out of the way\n";
	mv $tempfinkdir, $finkdir or
		die "Can't move new tree \"$tempfinkdir\" into place at \"$finkdir\". ".
			"Warning: Your Fink installation is in an inconsistent state now.\n";
	rm_rf $tempdir;

	# need to do this after the actual download since the download
	# goes to a temp area before being activated, and activation
	# happens all at once for the whole @trees set
	for my $tree (@trees) {
		$class->update_version_file(distribution => $tree);
	}

	print "\n";
	&print_breaking("Your Fink installation was successfully set up for ".
					"direct svn updating. The directory \"$finkdir.old\" ".
					"contains your old package description tree. Its ".
					"contents were merged into the new one, but the old ".
					"tree was left intact for safety reasons. If you no ".
					"longer need it, remove it manually.");
	print "\n";
}

### call svn update

sub do_direct_svn {
	my $class = shift;  # class method for now

	my ($descdir, @sb, $cmd, $cmd_recursive, $username, $msg);

	# add svn quiet flag if verbosity level permits
	my $verbosity = "--quiet";
	if ($config->verbosity_level() > 1) {
		$verbosity = "";
	}

	my $svnpath = $config->param("SvnPath");

	$descdir = "$basepath/fink";
	chdir $descdir or die "Can't cd to $descdir: $!\n";

	@sb = stat("$descdir/.svn");

	$cmd = "$svnpath ${verbosity} update";

	$msg = "I will now run the svn command to retrieve the latest package descriptions. ";

	if ($sb[4] != 0 and $> != $sb[4]) {
		($username) = getpwuid($sb[4]);
		$msg .= "The 'su' command will be used to run the svn command as the ".
				"user '$username'. ";
	}

	$msg .= "After that, the core packages will be updated right away; ".
			"you should then update the other packages using commands like ".
			"'fink update-all'.";

	print "\n";
	&print_breaking($msg);
	print "\n";

	# first, update the top-level stuff

	my $errors = 0;

	$cmd = "$cmd --depth=files";
	$cmd = "/usr/bin/su $username -c '$cmd'" if ($username);
	if (&execute($cmd)) {
		$errors++;
	}

	# then, update the trees

	my @trees = split(/\s+/, $config->param_default("SelfUpdateTrees", $config->param_default("SelfUpdateCVSTrees", $distribution)));
	for my $tree (@trees) {
		$cmd = "$svnpath ${verbosity} update ${tree}";
		$cmd = "/usr/bin/su $username -c '$cmd'" if ($username);
		if (&execute($cmd)) {
			$errors++;
		} else {
			$class->update_version_file(distribution => $tree);
		}
	}

	die "Updating using svn failed. Check the error messages above.\n" if ($errors);
}

=over 4

=back

=cut

1;
