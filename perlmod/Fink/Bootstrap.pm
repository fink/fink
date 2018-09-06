# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Bootstrap module
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2016 The Fink Package Manager Team
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

package Fink::Bootstrap;

use ExtUtils::Manifest qw(&maniread);

use Fink::Config qw($config $basepath &fink_tree_default);
use Fink::Services qw(&execute &enforce_gcc &eval_conditional);
use Fink::CLI qw(&print_breaking &prompt_boolean);
use Fink::Package;
use Fink::PkgVersion;
use Fink::Engine;
use Fink::Command qw(cat mkdir_p rm_rf touch);
use Fink::Checksum;

use strict;
use warnings;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
	$VERSION	 = 1.00;
	@ISA		 = qw(Exporter);
	@EXPORT		 = qw();
	@EXPORT_OK	 = qw(
		&bootstrap1
		&bootstrap2
		&bootstrap3
		&get_bsbase
		&check_host
		&check_files
		&fink_packagefiles
		&locate_Fink
		&find_rootmethod
		&create_tarball
		&copy_description
		&inject_package
		&modify_description
		&get_version_revision
		&read_version_revision
		&additional_packages
		&is_perl_supported
		&add_injected_to_trees
		&get_selfupdatetrees
		);
	%EXPORT_TAGS = ( );			# eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

END { }				# module clean-up code here (global destructor)


=head1 NAME

Fink::Bootstrap - Bootstrap a fink installation

=head1 SYNOPSIS

  use Fink::Bootstrap qw(:ALL);

	my $distribution = check_host($host);
	my $distribution = check_host($host, $bootstrap);
	my $distribution = check_host($host, $bootstrap, $arch);
	my $result = inject_package($package, $packagefiles, $info_script, $param);
	my $package_list = additional_packages();
	my $perl_is_supported = is_perl_supported();
	bootstrap();
	my $bsbase = get_bsbase();
	my $result = check_files();
	my $packagefiles = fink_packagefiles();
	my ($notlocated, $basepath) = locate_Fink();
	my ($notlocated, $basepath) = locate_Fink($param);
	find_rootmethod($bpath);
	my $result = create_tarball($bpath, $package, $packageversion, $packagefiles);
	my $result = copy_description($script, $bpath, $package, $packageversion, $packagerevision);
	my $result = copy_description($script, $bpath, $package, $packageversion, $packagerevision, $destination);
	my $result = modify_description($original,$target,$tarball,$package_source,$source_location,$distribution,$coda,$version,$revision);
	my ($version, $revisions) = read_version_revision($package_source);
	my ($version, $revision) = get_version_revision($package_source,$distribution);
	my $selfupdatetrees = get_selfupdatetrees($distribution);


=head1 DESCRIPTION

This module defines functions that are used to bootstrap a fink installation
or update to a new version.  The functions are intended to be called from
scripts that are not part of fink itself.  In particular, the scripts
bootstrap, inject.pl, scripts/srcdist/dist-module.pl, and fink's
postinstall.pl all depend on functions from this module.

=head2 Functions

These functions are exported on request.  You can export them all with

  use Fink::Bootstrap qw(:ALL);


=over 4

=item check_host

	my $distribution = check_host($host);
	my $distribution = check_host($host, $bootstrap);
	my $distribution = check_host($host, $bootstrap, $arch);

Checks a given system configuration description and returns which fink
distribution to use, or "unknown" if it could not be determined. The
$host string should be a hyphen-separated triplet of the type and
format as returned by config.guess (CPU-VENDOR-OS).

The first optional argument $bootstrap is a boolean, designating
whether we have been called by bootstrap or not. If absent, it
defaults to false.

The second optional argument $arch specifies the architecture for Fink
which was chosen during bootstrap (from the bootstrap script), or the
architecture under which Fink is currently being installed (when called
from postinstall.pl).  It defaults to the empty string.

This function also warns the user about certain bad configurations, or
incorrect versions of gcc.

After every release of Mac OS X, fink should be tested against the new
release and then this function should be updated.

Called by bootstrap and fink's postinstall.pl.

=cut

sub check_host {
	my $host = shift @_;
	my $bootstrap = shift @_ || 0;
	my $arch = shift @_ || "";

	my $distribution = 'undefined';	# return value (default)
	my $gcc;						# compiler-version-dependent dist detail

	# We check to see if gcc is installed, and if it is the correct version.
	# If so, we set $gcc so that 10.2 users will get the 10.2-gcc3.3 tree.

	if (-x '/usr/bin/gcc') {
		$gcc = Fink::Services::enforce_gcc(<<GCC_MSG);
Under CURRENT_SYSTEM, Fink must be bootstrapped or updated with gcc
EXPECTED_GCC, however, you currently have gcc INSTALLED_GCC selected.
Make sure that your developer tools are current for your system and
have not been locally modified.
GCC_MSG
		$gcc = "-gcc" . $gcc;
	}

	unless ($host =~ /^([^-]*)-([^-]*)-([^0-9]*)(.*)$/) {
		&print_breaking("The system identifier '$host' could not be parsed.");
		return 'unknown';
	}

	my ($host_cpu, $host_vendor, $host_os, $host_vers) = ($1, $2, $3, $4);
	my @host_vers = split /\./, $host_vers;  # kernel (not OSX vers)

	if ($host_vendor ne "apple" or $host_os ne "darwin") {
		&print_breaking("The vendor-OS '$host_vendor-$host_os' is not ".
			"supported by this version of Fink.");
	} elsif ($host_vers[0] == 1 and $host_cpu eq 'powerpc') {
		&print_breaking("This system is no longer supported " .
			"for current versions of fink.  Please use fink 0.12.1 or earlier.");
		$distribution = "10.1";
	} elsif ($host_vers[0] == 5 and $host_cpu eq 'powerpc') {
		&print_breaking("This system is no longer supported " .
			"for current versions of fink.  Please use fink 0.12.1 or earlier.");
		$distribution = "10.1";
	} elsif ($host_vers[0] == 6 and ($host_cpu eq 'powerpc' or $host_cpu eq 'i386')) {
		&print_breaking("This system is no longer supported " .
			"for current versions of fink.  Please use fink 0.24.7 or earlier.");
		$distribution = "10.2"; # or 10.2-gcc3.3, but it doesn't matter as we refuse running anyway
	} elsif ($host_vers[0] == 7 and ($host_cpu eq 'powerpc' or $host_cpu eq 'i386')) {
		&print_breaking("This system no longer supported " .
			"for current versions of fink.  Please use fink 0.28.5 or earlier.");
		$distribution = "10.3";
	} elsif ($host_vers[0] == 8 and ($host_cpu eq 'powerpc' or $host_cpu eq 'i386')) {
		&print_breaking("This system no longer supported " .
			"for current versions of fink.  Please use fink 0.30.2 or earlier.");
		$distribution = "10.4";
	} elsif ($host_vers[0] == 9 and ($host_cpu eq 'powerpc' or $host_cpu eq 'i386')) {
		&print_breaking("This system no longer supported " .
			"for current versions of fink.  Please use fink 0.34.10 or earlier.");
		$distribution = "10.5";
	} elsif ($host_vers[0] == 10 and $host_cpu eq 'i386') {
		&print_breaking("This system no longer supported " .
			"for current versions of fink.  Please use fink 0.34.10 or earlier.");
		$distribution = "10.6";
	} elsif ($host_vers[0] == 11 and $host_cpu eq 'i386') {
		&print_breaking("This system no longer supported " .
			"for current versions of fink.  Please use fink 0.38.8 or earlier.");
		$distribution = "10.7";
	} elsif ($host_vers[0] == 12 and $host_cpu eq 'i386') {
		&print_breaking("This system no longer supported " .
			"for current versions of fink.  Please use fink 0.38.8 or earlier.");
		$distribution = "10.8";
	} elsif ($host_vers[0] == 13 and $host_cpu eq 'i386') {
		if ($host_vers[1] <= 5) {
			&print_breaking("This system is supported and tested.");
		} else {
			&print_breaking("This system was not released at the time " .
				"this Fink release was made.  Prerelease versions " .
				"of Mac OS X might work with Fink, but there are no " .
				"guarantees.");
		}
		$distribution = "10.9";
	} elsif ($host_vers[0] == 14 and $host_cpu eq 'i386') {
		if ($host_vers[1] <= 5) {
			&print_breaking("This system is supported and tested.");
		} else {
			&print_breaking("This system was not released at the time " .
				"this Fink release was made.  Prerelease versions " .
				"of Mac OS X might work with Fink, but there are no " .
				"guarantees.");
		}
		$distribution = "10.10";
	} elsif ($host_vers[0] == 15 and $host_cpu eq 'i386') {
		if ($host_vers[1] <= 6) {
			&print_breaking("This system is supported and tested.");
		} else {
			&print_breaking("This system was not released at the time " .
				"this Fink release was made.  Prerelease versions " .
				"of Mac OS X might work with Fink, but there are no " .
				"guarantees.");
		}
		$distribution = "10.11";
	} elsif ($host_vers[0] == 16 and $host_cpu eq 'i386') {
		if ($host_vers[1] <= 7) {
			&print_breaking("This system is supported and tested.");
		} else {
			&print_breaking("This system was not released at the time " .
				"this Fink release was made.  Prerelease versions " .
				"of Mac OS X might work with Fink, but there are no " .
				"guarantees.");
		}
		$distribution = "10.12";
	} elsif ($host_vers[0] == 17 and $host_cpu eq 'i386') {
		if ($host_vers[1] <= 5) {
			&print_breaking("This system is supported and tested.");
		} else {
			&print_breaking("This system was not released at the time " .
				"this Fink release was made.  Prerelease versions " .
				"of Mac OS X might work with Fink, but there are no " .
				"guarantees.");
		}
		$distribution = "10.13";
	} elsif ($host_cpu = 'i386') {
		&print_breaking("This system was not released at the time " .
			"this Fink release was made.  Prerelease versions " .
			"of Mac OS X might work with Fink, but there are no " .
			"guarantees.");
		$distribution = "10." . ($host_vers[0]-4);
	} else {
		&print_breaking("This system is unrecognized and not ".
			"supported by Fink.");
	}

	return $distribution;
}

=item inject_package

	my $result = inject_package($package, $packagefiles, $info_script, $param);

The primary routine to update a fink installation, called by inject.pl.
Installs a new version of $package (passing $param to the locate_Fink function
to find out where to install it), whose source files are those listed in
$packagefiles, and executing the script $info_script prior to making the new
package desription.

Returns 0 on success, 1 on failure.

=cut

sub inject_package {

	import Fink::Services qw(&read_config);
	require Fink::Config;

	### Note to developers: Fink::Config loads Fink::FinkVersion, but it is
	### important not to call Fink::FinkVersion::fink_version or
	### Fink::FinkVersion::get_arch during inject_package, because inject.pl
	### may be running a version of fink in which those values are incorrect.

	my $package = shift;
	my $packagefiles = shift;
	my $info_script = shift;

	### locate Fink installation

	my $param = shift;

	my ($notlocated, $bpath) = &locate_Fink($param);

	if ($notlocated) {
		return 1;
	}

	### determine $distribution
	my $distribution = readlink("$bpath/fink/dists");
#	print "DISTRIBUTION $distribution\n";

	### get version

	my ($packageversion, $packagerevision) = &get_version_revision(".",$distribution);

	### load configuration

	my $config = &read_config("$bpath/etc/fink.conf",
							  { Basepath => $bpath });

	### parse config file for root method

	&find_rootmethod($bpath);

	### check that local/injected is in the Trees list

	&add_injected_to_trees($distribution);

	### create tarball for the package

	my $result = &create_tarball($bpath, $package, $packageversion, $packagefiles);
	if ($result == 1 ) {
		return $result;
	}

	### create and copy description file

	$result = &copy_description($info_script, $bpath, $package, $packageversion, $packagerevision, undef, "$package.info", "$package.info.in");
	if ($result == 1 ) {
		return $result;
	}

	### install the package

	print "Installing package...\n";
	print "\n";

	if (&execute("$bpath/bin/fink install $package-$packageversion-$packagerevision")) {
		print "\n";
		&print_breaking("Installing the new $package package failed. ".
		  "The description and the tarball were installed, though. ".
		  "You can retry at a later time by issuing the ".
		  "appropriate fink commands.");
	} else {
		print "\n";
		&print_breaking("Your Fink installation in '$bpath' was updated with ".
		  "a new $package package.");
	}
	print "\n";

	return 0;
}

=item add_injected_to_trees

	my ($exit_value) = add_injected_to_trees($distribution);

Adds local/injected to the Trees list, if not already present.  Now
depends on $distribution because the default Trees list does.  Returns
1 on failure, 0 on success.

Called by inject_package() and fink's postinstall.pl.

=cut

sub add_injected_to_trees {

	my $distribution = shift || die "The API for add_injected_to_trees has
	   changed, and now requires an argument.  If you see this message,
	   complain to your friendly neighborhood fink maintainers.\n";;

	my $trees = $config->param("Trees");
	if ($trees =~ /^\s*$/) {
		print "Adding a Trees line to fink.conf...\n";
		my $fink_trees = Fink::Config::fink_tree_default($distribution);
		$config->set_param("Trees", "$fink_trees local/injected");
		$config->save();
	} else {
		if (grep({$_ eq "local/injected"} split(/\s+/, $trees)) < 1) {
			print "Adding local/injected to the Trees line in fink.conf...\n";
			$config->set_param("Trees", "$trees local/injected");
			$config->save();
		}
	}

	0;
}

=item additional_packages

	my $package_list = additional_packages();

Returns a reference to the list of non-essential packages which must be
installed during bootstrap or selfupdate (this answer is affected by the
currently-running version of perl)


Called by bootstrap() and by Fink::SelfUpdate::finish().

=cut

sub additional_packages {

# note: we must install any package which is a splitoff of an essential
# package here.  If we fail to do so, we could find ourselves in the
# situation where foo-shlibs has been updated, but foo-dev was left at
# the old version (and is installed as the old version).  This could lead
# to problems the next time foo was used to compile something.

# FIXME: We should only list packages here which are neither essential nor
# splitoffs of essential packages. Then, calling code should take care of also
# handling any splitoffs of (essential or other) packages automatically. This
# way, we don't risk running out of sync.

	my @addlist = (
		"apt",
		"apt-shlibs",
		"apt-dev",
		"bzip2-dev",
		"gettext-bin",
		"libgettext8-dev",
		"libiconv-dev",
		"libncurses5",
	);

	return \@addlist;

}


=item is_perl_supported

	my $perl_is_supported = is_perl_supported();

Returns a boolean value which is "True" if the currently-running version of perl
is on the list of those versions supported during bootstrapping, and "False"
otherwise.

Called by bootstrap() and by Fink::SelfUpdate::finish().

=cut

sub is_perl_supported {

	if ("$]" == "5.008001") {
	} elsif ("$]" == "5.008002") {
	} elsif ("$]" == "5.008006") {
	} elsif ("$]" == "5.008008") {
	} elsif ("$]" == "5.010000") {
	} elsif ("$]" == "5.012003") {
	} elsif ("$]" == "5.012004") {
	} elsif ("$]" == "5.016002") {
	} elsif ("$]" == "5.018002") {
	} else {
		# unsupported version of perl
		return 0;
	}

	return 1;

}


=item bootstrap1

	bootstrap1();
    bootstrap1($item1,$item2,...);

The first part of the primary bootstrap routine, called by bootstrap.
The optional arguments specify packages in addition to dpkg-bootstrap
which should be built before package management starts.

=cut

sub bootstrap1 {
	$config->set_flag("bootstrap1");
	my ($bsbase, $save_path);
	my ($pkgname, $package, @elist);
	my @plist = ("dpkg-bootstrap");
	push(@plist, @_);
	print "plist is @plist\n";
	die "Sorry, this version of Perl ($]) is currently not supported by Fink.\n" unless is_perl_supported();

	$bsbase = &get_bsbase();
	&print_breaking("Bootstrapping a base system via $bsbase.");

	# create directories
	if (-e $bsbase) {
		rm_rf $bsbase;
	}
	mkdir_p "$bsbase/bin", "$bsbase/sbin", "$bsbase/lib";

	# create empty dpkg database
	mkdir_p "$basepath/var/lib/dpkg";
	touch "$basepath/var/lib/dpkg/status",
	      "$basepath/var/lib/dpkg/available",
	      "$basepath/var/lib/dpkg/diversions";

	# set paths so that everything is found
	$save_path = $ENV{PATH};
	$ENV{PATH} = "$basepath/sbin:$basepath/bin:".
				 "$bsbase/sbin:$bsbase/bin:".
				 $save_path;

	# disable UseBinaryDist during bootstrap
	Fink::Config::set_options( { 'use_binary' => -1 });
	# bootstrap as root
	Fink::Config::set_options( { 'build_as_nobody' => 0 });

	# make sure we have the package descriptions
	Fink::Package->require_packages();

	# determine essential packages
	@elist = Fink::Package->list_essential_packages();
	my $package_list = additional_packages();
	my @addlist = @{$package_list};

	print "\n";
	&print_breaking("BOOTSTRAP PHASE ONE: download tarballs.");
	print "\n";

	# use normal install routines
	Fink::Engine::cmd_fetch_missing(@plist, @elist, @addlist);


	print "\n";
	&print_breaking("BOOTSTRAP PHASE TWO: installing neccessary packages to ".
					"$bsbase without package management.");
	print "\n";

	# install the packages needed to build packages into the bootstrap tree
	foreach $pkgname (@plist) {
		$package = Fink::PkgVersion->match_package($pkgname);
		unless (defined $package) {
			die "no package found for specification '$pkgname'!\n";
		}

		$package->enable_bootstrap($bsbase);
		$package->phase_unpack();
		$package->phase_patch();
		$package->phase_compile();
		$package->phase_install();
		$package->disable_bootstrap();
	}


	$ENV{PATH} = $save_path;
	$config->clear_flag("bootstrap1");
}

=item bootstrap2

	bootstrap2();

The second part of the primary bootstrap routine, called by bootstrap.
This part must be run under a perl binary which is identical to the one
which will be used to run fink itself, post-bootstrap.

=cut


sub bootstrap2 {
	my ($bsbase, $save_path);
	my ($pkgname, $package, @elist);
	$bsbase = &get_bsbase();
	# set paths so that everything is found
	$save_path = $ENV{PATH};
	$ENV{PATH} = "$basepath/sbin:$basepath/bin:".
				 "$bsbase/sbin:$bsbase/bin:".
				 $save_path;

	# disable UseBinaryDist during bootstrap
	Fink::Config::set_options( { 'use_binary' => -1 });

	# make sure we have the package descriptions
	Fink::Package->require_packages();

	# determine essential packages
	@elist = Fink::Package->list_essential_packages();
	my $package_list = additional_packages();
	my @addlist = @{$package_list};

	print "\n";
	&print_breaking("BOOTSTRAP PHASE THREE: installing essential packages to ".
					"$basepath with package management.");
	print "\n";

	# bootstrap as root
	Fink::Config::set_options( { 'build_as_nobody' => 0 });
	# use normal install routines, but do not use buildlocks
	Fink::Config::set_options( { 'no_buildlock' => 1 } );
	Fink::Engine::cmd_install(@elist, @addlist);
	Fink::Config::set_options( { 'no_buildlock' => 0 } );

	$ENV{PATH} = $save_path;
}


=item bootstrap3

	bootstrap3();

The final part of the primary bootstrap routine, called by bootstrap.

=cut


sub bootstrap3 {
	my $bsbase = &get_bsbase();
	print "\n";
	&print_breaking("BOOTSTRAP DONE. Cleaning up.");
	print "\n";
	rm_rf $bsbase;
}


=item get_bsbase

	my $bsbase = get_bsbase();

Returns the base path for bootstrapping.  Called by bootstrap() and by
bootstrap.

=cut

sub get_bsbase {
	return "$basepath/bootstrap";
}

=item check_files

	my $result = check_files();

Tests whether the current directory contains all of the files needed to
compile fink.  Returns 0 on success, 1 on failure.

Called by bootstrap and fink's inject.pl.

=cut

sub check_files {
	my ($file);
	foreach $file (qw(fink.in install.sh COPYING VERSION
  		perlmod/Fink update fink.info.in postinstall.pl.in
  		update/config.guess perlmod/Fink/Config.pm fink-virtual-pkgs.in
		fink-instscripts.in fink-scanpackages.in fink-dpkg-status-cleanup.in
 	)) {
		if (not -e $file) {
			print "ERROR: Package incomplete, '$file' is missing.\n";
			return 1;
		}
	}
	return 0;
}

=item fink_packagefiles

	my $packagefiles = fink_packagefiles();

Returns a space-separated list of all files which should be contained
in the fink tarball.  Called by bootstrap and fink's inject.pl.
This list is complete: you do not need to recurse through directories,
and simple directories are not even included here.

=cut

sub fink_packagefiles {
	-r 'MANIFEST' or die "Could not read MANIFEST: $!\n";
	my $manifest = maniread;
	my @files = sort keys %$manifest;
	@files = grep { -f $_ } @files;  # catch mistakes in MANIFEST
	return join ' ', @files;
}

=item locate_Fink

	my ($notlocated, $basepath) = locate_Fink();
	my ($notlocated, $basepath) = locate_Fink($param);

If called without a parameter, attempts to guess the base path of the fink
installation.  If the guess is successful, returns (0, base path).  If
the guess is unsuccessful, returns (1, guessed value) and suggests to the
user to call the script with a parameter.

When a parameter is passed, it is returned as the base path value via
(0, base path).

This function is called by inject_package().

=cut

sub locate_Fink {

	my $param = shift;

	my ($guessed, $path, $bpath);

	$guessed = "";

	if (defined $param) {
		$bpath = $param;
	} else {
		$bpath = undef;
		if (exists $ENV{PATH}) {
			foreach $path (split(/:/, $ENV{PATH})) {
				if (substr($path,-1) eq "/") {
					$path = substr($path,0,-1);
				}
				if (-f "$path/init.sh" and -f "$path/fink") {
					$path =~ /^(.+)\/[^\/]+$/;
					$bpath = $1;
					last;
				}
			}
		}
		if (not defined $bpath or $bpath eq "") {
			$bpath = "/sw";
		}
		$guessed = " (guessed)";
	}
	unless (-f "$bpath/bin/fink" and
	        -f "$bpath/bin/init.sh" and
	        -f "$bpath/etc/fink.conf" and
	        -d "$bpath/fink/dists") {
		&print_breaking("The directory '$bpath'$guessed does not contain a ".
						"Fink installation. Please provide the correct path ".
						"as a parameter to this script.");
		return (1,"");
	}
	return (0,$bpath);
}

=item find_rootmethod

	find_rootmethod($bpath);

Reexecute "./inject.pl $bpath" as sudo, if appropriate.  Called by
inject_package().

=cut

sub find_rootmethod {
	# TODO: use setting from config
	# for now, we just use sudo...

my $bpath = shift;

	if ($> != 0) {
		my $env = '';
		$env = "/usr/bin/env PERL5LIB='$ENV{'PERL5LIB'}'" if (exists $ENV{'PERL5LIB'} and defined $ENV{'PERL5LIB'});
		exit &execute("/usr/bin/sudo $env ./inject.pl $bpath");
	}
	umask oct("022");
}

=item create_tarball

	my $result = create_tarball($bpath, $package, $packageversion, $packagefiles);

Create the directory $bpath/src if necessary, then create the tarball
$bpath/src/$package-$packageversion.tar containing the files $packagefiles.
Returns 0 on success, 1 on failure.

Called by bootstrap and inject_package().

=cut

sub create_tarball {

	my $bpath = shift;
	my $package = shift;
	my $packageversion = shift;
	my $packagefiles = shift;

	my ($cmd, $script);

	print "Creating $package tarball...\n";

	$script = "";
	if (not -d "$bpath/src") {
		$script .= "mkdir -p $bpath/src\n";
	}

	# Don't allow Apple's tar to use copyfile
	my %env_bak = %ENV;
	$ENV{COPY_EXTENDED_ATTRIBUTES_DISABLE} = 1;
	$ENV{COPYFILE_DISABLE} = 1;

	$script .=
	  "tar -cf $bpath/src/$package-$packageversion.tar $packagefiles\n";

	my $result = 0;

	foreach $cmd (split(/\n/,$script)) {
		next unless $cmd;   # skip empty lines

		if (&execute($cmd)) {
			print "ERROR: Can't create tarball.\n";
			$result = 1;
		}
	}

	%ENV = %env_bak;
	return $result;
}

=item copy_description

	my $result = copy_description($script, $bpath, $package, $packageversion, $packagerevision);
	my $result = copy_description($script, $bpath, $package, $packageversion, $packagerevision, $destination);
	my $result = copy_description($script, $bpath, $package, $packageversion, $packagerevision, $destination, $target_file);
	my $result = copy_description($script, $bpath, $package, $packageversion, $packagerevision, $destination, $target_file, $template_file);

Execute the given $script, create the directories $bpath/fink/debs and
$bpath/fink/dists/$destination if necessary, and backup the file
$bpath/fink/dists/$destination/$target_file if it already exists.

Next, copy $template_file (from the current directory) to
$bpath/fink/dists/$destination/$target_file, supplying the correct
$packageversion and $packagerevision as well as the MD5 and SHA256 sums calculated from
$bpath/src/$package-$packageversion.tar.  Ensure that the created file
has mode 644.

The default $destination, if not supplied, is "local/injected/finkinfo".
The default $target_file, if not supplied, is "$package.info".
The default $template_file, if not supplied, is "$target_file.in".

Returns 0 on success, 1 on failure.

Called by bootstrap and inject_package().

=cut

sub copy_description {

	my $script = shift;
	my $bpath = shift;
	my $package = shift;
	my $packageversion = shift;
	my $packagerevision = shift;

	my $destination = shift || "local/injected/finkinfo";
	my $target_file = shift || "$package.info";
	my $template_file = shift || "$target_file.in";

	my ($cmd);

	print "Copying package description(s)...\n";

	if (not -d "$bpath/fink/debs") {
		$script .= "/bin/mkdir -p -m755 $bpath/fink/debs\n";
	}
	if (not -d "$bpath/fink/dists/$destination") {
		$script .= "/bin/mkdir -p -m755 $bpath/fink/dists/$destination\n";
	}
	if (-e "$bpath/fink/dists/$destination/$target_file") {
#		if (-e "$bpath/fink/dists/$destination/$target_file.bak") {
#			my $answer = &prompt_boolean("\nWARNING: The file $bpath/fink/dists/$destination/$target_file.bak exists and will be overwritten.  Do you wish to continue?", default => 1);
#			if (not $answer) {
#				die "\nOK, you can re-run ./inject.pl after moving the file.\n\n";
#			}
			unlink "$bpath/fink/dists/$destination/$target_file.bak";
#		}
#		&print_breaking("\nNOTICE: the previously existing file $bpath/fink/dists/$destination/$target_file has been moved to $bpath/fink/dists/$destination/$target_file.bak .\n\n");
		&execute("/bin/mv $bpath/fink/dists/$destination/$target_file $bpath/fink/dists/$destination/$target_file.bak");
		}

	my $result = 0;

	foreach $cmd (split(/\n/,$script)) {
		next unless $cmd;   # skip empty lines

		if (&execute($cmd)) {
			print "ERROR: Can't copy package description(s).\n";
			$result = 1;
		}
	}

# determine $distribution
	my $distribution = readlink("$bpath/fink/dists");
#	print "DISTRIBUTION $distribution\n";

	my $coda = "NoSourceDirectory: true\n";

	if (modify_description($template_file, "$bpath/fink/dists/$destination/$target_file","$bpath/src/$package-$packageversion.tar",".","%n-%v.tar",$distribution,$coda, $packageversion, $packagerevision)) {
			print "ERROR: Can't copy package description(s).\n";
			$result = 1;
		} elsif (&execute("/bin/chmod 644 $bpath/fink/dists/$destination/*.*")) {
			print "ERROR: Can't copy package description(s).\n";
			$result = 1;
		}

	return $result;
}

=item modify_description

	my $result = modify_description($original,$target,$tarball,$package_source,$source_location,$distribution,$coda,$version,$revision);

Copy the file $original to $target, supplying the correct version, revision,
and distribution (from get_version_revision($package_source,$distribution))
as well as $source_location and the MD5 and SHA256 sums calculated from $tarball.
Pre-evaluate any conditionals containing %{Distribution}, using
$distribution as the value of %{Distribution}.  Append $coda to the end
of the file.

Wrap the file in Info4, unless $distribution = 10.3 or 10.4.

Returns 0 on success, 1 on failure.

Called by copy_description() and scripts/srcdist/dist-module.pl .

=cut

sub modify_description {

	my $original = shift;
	my $target = shift;
	my $tarball = shift;
	my $package_source = shift;
	my $source_location = shift;
	my $distribution = shift;
	my $coda = shift;
	my $version = shift;
	my $revision = shift;

	print "Modifying package description...\n";
	my $md5obj = Fink::Checksum->new('MD5');
	my $md5 = $md5obj->get_checksum($tarball);
	my $sha256obj = Fink::Checksum->new('SHA256');
	my $sha256 = $sha256obj->get_checksum($tarball);

	my $result = 0;

	open(IN,$original) or die "can't open $original: $!";
	open(OUT,">$target") or die "can't write $target: $!";
	print OUT "Info4: <<\n" unless (($distribution eq "10.3") or ($distribution eq "10.4"));
	while (<IN>) {
		chomp;
		$_ =~ s/\@VERSION\@/$version/;
		$_ =~ s/\@REVISION\@/$revision/;
		$_ =~ s/\@SOURCE\@/$source_location/;
		$_ =~ s/\@MD5\@/$md5/;
		$_ =~ s/\@SHA256\@/$sha256/;
		$_ =~ s/\@DISTRIBUTION\@/$distribution/;
# only remove conditionals which match "%{Distribution}" (and we will
# remove the entire line if the condition fails)
		if ($_ =~ s/%\{Distribution\}/$distribution/) {
			if (s/^(\s*)\((.*?)\)\s*(.*)/$1$3/) {
				# we have a conditional; remove the cond expression,
				my $cond = $2;
#               print "\tfound conditional '$cond'\n";
				# if cond is false, clear entire line
				undef $_ unless &eval_conditional($cond, "modify_description");
			}
		}
		print OUT "$_\n" if defined($_);
	}
	close(IN);
	print OUT "$coda\n";
	print OUT "<<\n" unless (($distribution eq "10.3") or ($distribution eq "10.4"));
	close(OUT);

	return $result;
}

=item read_version_revision

	my ($version, $revisions) = read_version_revision($package_source);

Finds the current version and possible revisions by examining the files
$package_source/VERSION and $package_source/REVISION.  $revisions is
a reference to a hash which either specifies a revision for each
distribution, or else specifies a single revision with the key "all".

Called by get_version_revision() and scripts/srcdist/dist-module.pl.

=cut

sub read_version_revision {

	my $package_source = shift;

	my %revision_data;

	if (-f "$package_source/REVISION") {
		open(IN,"$package_source/REVISION") or die "Can't open $package_source/REVISION: $!";
		while (<IN>) {
			chomp;
			/(.*):\s*(.*)/;
			$revision_data{$1} = $2;
		}
		close(IN);
	}

	my ($packageversion,$packagerevision,$revisions);

	chomp($packageversion = cat "$package_source/VERSION");
	if ($packageversion =~ /(cvs|svn|git)/) {
		my @now = gmtime(time);
		$packagerevision = sprintf("%04d%02d%02d.%02d%02d",
		                           $now[5]+1900, $now[4]+1, $now[3],
		                           $now[2], $now[1]);
		$revisions = {"all" => $packagerevision};
	} elsif (-f "$package_source/REVISION") {
		open(IN,"$package_source/REVISION") or die "Can't open $package_source/REVISION: $!";
		while (<IN>) {
			chomp;
			/(.*):\s*(.*)/;
			$revision_data{$1} = $2;
		}
		close(IN);
		$revisions = \%revision_data;
	} else {
		$packagerevision = "1";
		$revisions = {"all" => $packagerevision};
	}
	return ($packageversion, $revisions);
}

=item get_version_revision

	my ($version, $revision) = get_version_revision($package_source,$distribution);

Calculate the version and revision numbers for the .info file, based on the
current $distribution, and the data given in $package_source/VERSION and
$package_source/REVISION.

Called by bootstrap, inject_package(), and modify_description().

=cut

sub get_version_revision {

	my $package_source = shift;
	my $distribution = shift;

	my ($version, $revisions) = read_version_revision($package_source);

	if (defined(${$revisions}{$distribution})) {
#	print "CALCULATED from $distribution:" .  ${$revisions}{$distribution} . "\n";
	return ($version, ${$revisions}{$distribution});
} elsif (defined(${$revisions}{'all'})) {
#	print "CALCULATED from ALL:" .  ${$revisions}{'all'} . "\n";
	return ($version, ${$revisions}{'all'});
}
}

=item get_selfupdatetrees

	my $selfupdatetrees = get_selfupdatetrees($distribution);

Find the correct value for $selfupdatetrees for the given $distribution.

Called by bootstrap and postinstall.pl.

=cut

sub get_selfupdatetrees {

	my $distribution = shift;

	my %selfupdatetrees = (
		"10.3" => "10.3",
		"10.4" => "10.4",
		"10.5" => "10.4",
		"10.6" => "10.4",
		"10.7" => "10.7",
		"10.8" => "10.7",
		"10.9" => "10.9-libcxx",
		"10.10" => "10.9-libcxx",
		"10.11" => "10.9-libcxx",
		"10.12" => "10.9-libcxx",
		"10.13" => "10.9-libcxx",
		);

	return $selfupdatetrees{$distribution};
}


=back

=cut

### EOF
1;
# vim: ts=4 sw=4 noet
