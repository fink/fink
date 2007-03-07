# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::SelfUpdate class
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

package Fink::SelfUpdate;

use Fink::Services qw(&execute &version_cmp &aptget_lockwait);
use Fink::Bootstrap qw(&additional_packages);
use Fink::CLI qw(&print_breaking &prompt &prompt_boolean &prompt_selection);
use Fink::Config qw($config $basepath $dbpath $distribution);
use Fink::NetAccess qw(&fetch_url);
use Fink::Engine;  # &aptget_update &cmd_install, but they aren't EXPORT_OK
use Fink::Package;
use Fink::FinkVersion qw(&pkginfo_version);
use Fink::Mirror;
use Fink::Command qw(cat chowname mkdir_p mv rm_f rm_rf touch);

use File::Find;

use strict;
use warnings;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
	$VERSION	 = 1.00;
	@ISA		 = qw(Exporter);
	@EXPORT		 = qw();
	@EXPORT_OK	 = qw();	# eg: qw($Var1 %Hashit &func3);
	%EXPORT_TAGS = ( );		# eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

END { }				# module clean-up code here (global destructor)


=head1 NAME

Fink::SelfUpdate - download package descriptions from server

=head1 DESCRIPTION

=head2 Methods

=over 4

=item check

  Fink::SelfUpdate::check($method);


This is the main entry point for the 'fink selfupdate*' commands. The
local collection of package descriptions is updated according to one
of the following methods:

=over 4

=item "point"

A tarball of the latest Fink binary installer package collection is
downloaded from the fink website.

=item "cvs"

=item "rsync"

"cvs" or "rsync" protocols are used to syncronize with a remote
server.

=back

The optional $method parameter specifies the
selfupdate method to use:

=over 4

=item 0 (or undefined or omitted)

Use the current method

=item 1 or "cvs"

Use the cvs method

=item 2 or "rsync"

Use the rsync method

=back

The current method is specified by name in the SelfUpdateMethod field
in the F<fink.conf> preference file. If there is no current method
preference and a specific $method is not given, the user is prompted
to select a method. If a $method is given that is not the same as the
current method preference, fink.conf is updated according to $method.

=cut

sub check {
	my $method = shift;

	{
		my %methods = (
			0       => undef,
			1       => 'cvs',
			2       => 'rsync',
			'cvs'   => 'cvs',
			'rsync' => 'rsync',
		);
		$method = 0 if ! defined $method;
		if (! exists $methods{lc $method}) {
			die "Invalid method '$method' passed to Selfupdate::check\n";
		}
		$method = $methods{lc $method};
	}

	if (defined $method) {
		&print_breaking("\n Please note: the command 'fink selfupdate' "
				. "should be used for routine updating; you only need to use " 
				. "'fink selfupdate-cvs' or 'fink selfupdate-rsync' if you are "
				. "changing your update method. \n\n");
	}
	if (! defined $config->param("SelfUpdateMethod") and defined $method) {
		my $answer = $method;
		$answer = 'point' if !defined $answer;
		&need_devtools($answer);
		&print_breaking("fink is setting your default update method to $answer \n");
		$config->set_param("SelfUpdateMethod", $answer);
		$config->save();
	}

	# The user has not chosen a selfupdatemethod yet, always ask
	# if the fink.conf setting is not there.
	if (! defined $config->param("SelfUpdateMethod") and ! defined $method) {
		my $answer = &prompt_selection("Choose an update method",
						intro   => "fink needs you to choose a SelfUpdateMethod.",
						default => [ value => "rsync" ],
						choices => [
						  "rsync" => "rsync",
						  "cvs" => "cvs",
						  "Stick to point releases" => "point"
						] );
		&need_devtools($answer);
		$config->set_param("SelfUpdateMethod", $answer);
		$config->save();	
	}

	# We temporarily disable rsync updating for 10.5, until we've decided
	# how to handle it

	if (($config->param("SelfUpdateMethod") eq "rsync") and ($distribution eq "10.5")) {
		die "Sorry, fink doesn't support rsync updating in the 10.5 distribution at present.\n\n";
	}

	# By now the config param SelfUpdateMethod should be set.
	if ($config->param("SelfUpdateMethod") eq 'cvs' and $method ne 'rsync') {
		&need_devtools('cvs');
		Fink::SelfUpdate::rsync->stamp_clear();
		if (-d "$basepath/fink/dists/CVS") {
			&do_direct_cvs();
			&do_finish();
			return;
		} else {
			&setup_direct_cvs();
			&do_finish();
			return;
		}
	}
	elsif ($config->param("SelfUpdateMethod") eq 'rsync' and $method ne 'cvs'){
		&need_devtools('rsync');
		Fink::SelfUpdate::rsync->do_direct();
		&do_finish();
		return;
	}
	# Hm, we were called with a different option than the default :(
	my $selfupdatemethod = $config->param("SelfUpdateMethod");
	if ($selfupdatemethod ne 'rsync' and $method eq 'rsync') {

	# We temporarily disable rsync updating for 10.5, until we've decided
	# how to handle it

		if ($distribution eq "10.5") {
			die "Sorry, fink doesn't support rsync updating in the 10.5 distribution at present.\n\n";
		}

		my $answer =
			&prompt_boolean("The current selfupdate method is $selfupdatemethod. " 
					. "Do you wish to change the default selfupdate method ".
				"to rsync?", default => 1);
		if (! $answer) {
			return;
		}
		&need_devtools('rsync');
		$config->set_param("SelfUpdateMethod", "rsync");
		$config->save();	
		Fink::SelfUpdate::rsync->do_direct();
		&do_finish();
		return;		
	}
	if ($selfupdatemethod ne 'cvs' and $method eq 'cvs') {
		my $answer =
			&prompt_boolean("The current selfupdate method is $selfupdatemethod. " 
					. "Do you wish to change the default selfupdate method ".
				"to cvs?", default => 1);
		if (! $answer) {
			return;
		}
		&need_devtools('cvs');
		$config->set_param("SelfUpdateMethod", "cvs");
		$config->save();	
		&setup_direct_cvs();
		&do_finish();
		return;
	}
	if (($config->param("SelfUpdateMethod") eq "point")) {
		Fink::SelfUpdate::point->do_direct();
		&do_finish();
	}
}

=item need_devtools

  Fink::SelfUpdate::need_devtools($method);

If selfupdating using the given $method (passed by name) requires
components of Apple dev-tools (xcode) instead of just standard
components of OS X, check that the "dev-tools" virtual package is
installed. If it is required for the $method but is not present, die.

=cut

sub need_devtools {
	my $method = shift;

	if ($method eq 'cvs' || $method eq 'rsync') {
		Fink::VirtPackage->query_package("dev-tools")
			or die "selfupdate method '$method' requires the package 'dev-tools'\n";
	}
}

### set up direct cvs

sub setup_direct_cvs {
	my ($finkdir, $tempdir, $tempfinkdir);
	my ($username, $cvsuser, @testlist);
	my ($use_hardlinks, $cutoff, $cmd);
	my ($cmdd);


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
		$cmd = "cvs -d:pserver:anonymous\@$cvsrepository login";
		if ($username ne "root") {
			$cmd = "/usr/bin/su $username -c '$cmd'";
		}
		if (&execute($cmd)) {
			die "Logging into the CVS server for anonymous read-only access failed.\n";
		}

		$cmd = "cvs ${verbosity} -z3 -d:pserver:anonymous\@$cvsrepository";
	} else {
		if (-f "$basepath/lib/fink/URL/developer-cvs") {
			$cvsrepository = cat "$basepath/lib/fink/URL/developer-cvs";
			chomp($cvsrepository);
		}
		$cmd = "cvs ${verbosity} -z3 -d:ext:$cvsuser\@$cvsrepository";
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

	my @trees = split(/\s+/, $config->param_default("SelfUpdateCVSTrees", $distribution));
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
						 or die "Can't read target of symlink $File::Find::name: $!\n";
					 symlink $linkto, "$tempfinkdir/$rel" or
						 die "Can't create symlink \"$tempfinkdir/$rel\"\n";
				 } elsif (-d and not -d "$tempfinkdir/$rel") {
					 mkdir_p "$tempfinkdir/$rel" or
						 die "Can't create directory \"$tempfinkdir/$rel\"\n";
				 } elsif (-f and not -f "$tempfinkdir/$rel") {
					 my $cmd;
					 if ($use_hardlinks) {
						 $cmd = "ln";
					 } else {
						 $cmd = "cp -p"
					 }
					 $cmd .= " '$_' '$tempfinkdir/$rel'";
					 if (&execute($cmd)) {
						 die "Can't copy file \"$tempfinkdir/$rel\"\n";
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

	my @trees = split(/\s+/, $config->param_default("SelfUpdateCVSTrees", $distribution));
	for my $tree (@trees) {
		$cmd = "cvs ${verbosity} -z3 update -d -P ${tree}";
		$cmd = "/usr/bin/su $username -c '$cmd'" if ($username);
		if (&execute($cmd)) {
			$errors++;
		}
	}

	Fink::SelfUpdate::CVS->stamp_set();
	Fink::SelfUpdate::rsync->stamp_clear();
	die "Updating using CVS failed. Check the error messages above.\n" if ($errors);

}

=item do_finish

  Fink::SelfUpdate::do_finish;

Perform some final actions after updating the package descriptions collection:

=over 4

=item 1.

Update apt indices

=item 2.

Reread package descriptions (update local package database)

=item 3.

If a new version of the "fink" package itself is available, install
that new version.

=item 4.

If a new fink was installed, relaunch this fink session using it.
Otherwise, do some more end-of-selfupdate tasks (see L<finish>).

=back

=cut

sub do_finish {
	my $package;

	# update the apt-get database
	Fink::Engine::aptget_update()
		or &print_breaking("Running 'fink scanpackages' may fix indexing problems.");

	# forget the package info
	Fink::Package->forget_packages();

	# ...and then read it back in
	Fink::Package->require_packages();

	# update the package manager itself first if necessary (that is, if a
	# newer version is available).
	$package = Fink::PkgVersion->match_package("fink");
	if (not $package->is_installed()) {
		Fink::Engine::cmd_install("fink");
	
		# re-execute ourselves before we update the rest
		print "Re-executing fink to use the new version...\n";
		exec "$basepath/bin/fink selfupdate-finish";
	
		# the exec doesn't return, but just in case...
		die "re-executing fink failed, run 'fink selfupdate-finish' manually\n";
	} else {
		# package manager was not updated, just finish selfupdate directly
		&finish();
	}
}

=item finish

  Fink::SelfUpdate::finish;

Update all the packages that are part of fink itself or that have an
Essential or other high importance.

=cut

sub finish {
	my (@elist);

	# determine essential packages
	@elist = Fink::Package->list_essential_packages();

	# add some non-essential but important ones
    my ($package_list, $perl_is_supported) = additional_packages();

	print_breaking("WARNING! This version of Perl ($]) is not currently supported by Fink.  Updating anyway, but you may encounter problems.\n") unless $perl_is_supported;

	foreach my $important (@$package_list) {
		my $po = Fink::Package->package_by_name($important);
		if ($po && $po->is_any_installed()) {
			# only worry about "important" ones that are already installed
			push @elist, $important;
		}
	}

	# update them
	Fink::Engine::cmd_install(@elist);	

	# tell the user what has happened
	print "\n";
	&print_breaking("The core packages have been updated. ".
					"You should now update the other packages ".
					"using commands like 'fink update-all'.");
	print "\n";
}

=back

=cut

### EOF
1;
# vim: ts=4 sw=4 noet
