# -*- mode: Perl; tab-width: 4; -*-
# vim: ts=4 sw=4 noet
#
# Fink::SelfUpdate::CVS class
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

package Fink::SelfUpdate::CVS;

use base qw(Fink::SelfUpdate::Base);

use Fink::CLI qw(&print_breaking &prompt);
use Fink::Config qw($basepath $config $distribution);
use Fink::Package;
use Fink::Command qw(cat chowname mkdir_p mv rm_f rm_rf touch);
use Fink::Services qw(&execute);

use File::Find;

use strict;
use warnings;

our $VERSION = 1.00;

=head1 NAME

Fink::SelfUpdate::CVS - download package descriptions from a CVS server

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
		warn "Before changing your selfupdate method to 'cvs', you must install XCode, available on your original OS X install disk, or from http://connect.apple.com (after free registration).\n";
		return 0;
	}

	return 1;
}

sub clear_metadata {
	my $class = shift;  # class method for now

	my $finkdir = "$basepath/fink";
	if (-d "$finkdir.old") {
		die "There is a left-over \"$finkdir.old\" directory. You have to ".
			"move it out of the way before proceeding.\n";
	}
	&execute("/usr/bin/find $finkdir -name CVS -type d -print0 | xargs -0 /bin/rm -rf");
}

=item do_direct

Returns a null string.

=cut

sub do_direct {
	my $class = shift;  # class method for now

	if (-d "$basepath/fink/dists/CVS") {
		# already have a cvs checkout
		$class->do_direct_cvs();
	} else {
		$class->setup_direct_cvs();
	}
	return 1;
}

=back

=head2 Private Methods

=cut

### set up direct cvs

sub setup_direct_cvs {
	my $class = shift;  # class method for now

	my ($finkdir, $tempdir, $tempfinkdir);
	my ($username, $cvsuser, @testlist);
	my ($use_hardlinks, $cutoff, $cmd);
	my ($cmdd);
	# Thanks to Tanaka Atushi for information about the quoting syntax which
	# allows CVS proxies to function.
	my $proxcmd=''; # default to null
	
	my $http_proxy=$config->param_default("ProxyHTTP", ""); # get HTTP proxy information from fink.conf
	if ($http_proxy) { # HTTP proxy has been set            
		my $proxy_port;
		$http_proxy =~ s|http://||; # strip leading 'http://', if present.
		if  ($http_proxy =~ /:\d+/) { # extract TCP port number if present
			my @tokens=split /:/,$http_proxy;
			$proxy_port=pop @tokens ; # port is the last item following a colon
			$http_proxy=join ':',@tokens ; # since we may have a username:password combo 
		}
		$proxcmd=";proxy=$http_proxy";
		$proxcmd="$proxcmd;proxyport=$proxy_port" if $proxy_port;
	}
 
	$username = "root";
	if (exists $ENV{SUDO_USER}) {
		$username = $ENV{SUDO_USER};
	}

	print "\n";
	$username =
		&prompt("Fink has the capability to run the CVS commands as a ".
				"normal user. That has some advantages - it uses that ".
				"user's CVS settings files and allows the package ".
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
	$cvsuser =
		&prompt("For Fink developers only: ".
				"Enter your SourceForge login name to set up full CVS access. ".
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

	# start the CVS fun
	chdir $tempdir or die "Can't cd to $tempdir: $!\n";

	# add cvs quiet flag if verbosity level permits
	my $verbosity = "-q";
	if ($config->verbosity_level() > 1) {
		$verbosity = "";
	}
	my $cvsrepository = "fink.cvs.sourceforge.net:/cvsroot/fink";
	if (-f "$basepath/lib/fink/URL/cvs-repository") {
		$cvsrepository = cat "$basepath/lib/fink/URL/cvs-repository";
		chomp($cvsrepository);
		$cvsrepository .= ':/cvsroot/fink';
	}
	if ($cvsuser eq "anonymous") {
		if (-f "$basepath/lib/fink/URL/anonymous-cvs") {
			$cvsrepository = cat "$basepath/lib/fink/URL/anonymous-cvs";
			chomp($cvsrepository);
		}
		&print_breaking("Now logging into the CVS server. When CVS asks you ".
						"for a password, just press return (i.e. the password ".
						"is empty).");
		if ($cvsrepository =~ s/^:local://)  {
			$cmd = "cvs ${verbosity} -z3 -d$cvsrepository";
 		}
 		else {
			$cmd = qq(cvs -d":pserver${proxcmd}:anonymous\@$cvsrepository" login);
			if ($username ne "root") {
				$cmd = "/usr/bin/su $username -c '$cmd'";
			}
			if (&execute($cmd)) {
				die "Logging into the CVS server for anonymous read-only access failed.\n";
			}
			else {
				$cmd = qq(cvs ${verbosity} -z3 -d":pserver${proxcmd}:anonymous\@$cvsrepository");
			}
 		}
	} else {
		if (-f "$basepath/lib/fink/URL/developer-cvs") {
			$cvsrepository = cat "$basepath/lib/fink/URL/developer-cvs";
			chomp($cvsrepository);
		}
		$cmd = qq(cvs ${verbosity} -z3 "-d:ext${proxcmd}:$cvsuser\@$cvsrepository");
		$ENV{CVS_RSH} = "ssh";
	}
	$cmdd = "$cmd checkout -l -d fink dists";
	if ($username ne "root") {
		$cmdd = "/usr/bin/su $username -c '$cmdd'";
	}
	&print_breaking("Setting up base Fink directory...");
	if (&execute($cmdd)) {
		die "Downloading package descriptions from CVS failed.\n";
	}

	my @trees = split(/\s+/, $config->param_default("SelfUpdateTrees", $config->param_default("SelfUpdateCVSTrees", $distribution)));
	chdir "fink" or die "Can't cd to fink\n";

	for my $tree (@trees) {
		&print_breaking("Checking out $tree tree...");

		my $cvsdir = "dists/$tree";
		$cvsdir = "packages/dists" if ($tree eq "10.1");
		$cmdd = "$cmd checkout -d $tree $cvsdir";

		if ($username ne "root") {
			$cmdd = "/usr/bin/su $username -c '$cmdd'";
		}
		if (&execute($cmdd)) {
			die "Downloading package descriptions from CVS failed.\n";
		}
	}
	chdir $tempdir or die "Can't cd to $tempdir: $!\n";

	if (not -d $tempfinkdir) {
		die "The CVS didn't report an error, but the directory '$tempfinkdir' ".
			"doesn't exist as expected. Strange.\n";
	}

	&print_breaking("Merging old data to new tree...");
	# merge the old tree
	$cutoff = length($finkdir)+1;
	find(sub {
				 if ($_ eq "CVS") {
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
					"direct CVS updating. The directory \"$finkdir.old\" ".
					"contains your old package description tree. Its ".
					"contents were merged into the new one, but the old ".
					"tree was left intact for safety reasons. If you no ".
					"longer need it, remove it manually.");
	print "\n";
}

### call cvs update

sub do_direct_cvs {
	my $class = shift;  # class method for now

	my ($descdir, @sb, $cmd, $cmd_recursive, $username, $msg);

	# add cvs quiet flag if verbosity level permits
	my $verbosity = "-q";
	if ($config->verbosity_level() > 1) {
		$verbosity = "";
	}

	$descdir = "$basepath/fink";
	chdir $descdir or die "Can't cd to $descdir: $!\n";

	@sb = stat("$descdir/CVS");

	$cmd = "cvs ${verbosity} -z3 update -d -P -l";

	$msg = "I will now run the cvs command to retrieve the latest package descriptions. ";

	if ($sb[4] != 0 and $> != $sb[4]) {
		($username) = getpwuid($sb[4]);
		$msg .= "The 'su' command will be used to run the cvs command as the ".
				"user '$username'. ";
	}

	$msg .= "After that, the core packages will be updated right away; ".
			"you should then update the other packages using commands like ".
			"'fink update-all'.";

	print "\n";
	&print_breaking($msg);
	print "\n";

	$ENV{CVS_RSH} = "ssh";

	# first, update the top-level stuff

	my $errors = 0;

	$cmd = "/usr/bin/su $username -c '$cmd'" if ($username);
	if (&execute($cmd)) {
		$errors++;
	}

	# then, update the trees

	my @trees = split(/\s+/, $config->param_default("SelfUpdateTrees", $config->param_default("SelfUpdateCVSTrees", $distribution)));
	for my $tree (@trees) {
		$cmd = "cvs ${verbosity} -z3 update -d -P ${tree}";
		$cmd = "/usr/bin/su $username -c '$cmd'" if ($username);
		if (&execute($cmd)) {
			$errors++;
		} else {
			$class->update_version_file(distribution => $tree);
		}
	}

	die "Updating using CVS failed. Check the error messages above.\n" if ($errors);
}

=over 4

=back

=cut

1;
