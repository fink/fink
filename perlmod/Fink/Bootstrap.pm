#
# Fink::Bootstrap module
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2003 The Fink Package Manager Team
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

package Fink::Bootstrap;

use Fink::Config qw($config $basepath);
use Fink::Services qw(&print_breaking &execute);
use Fink::Package;
use Fink::Shlibs;
use Fink::PkgVersion;
use Fink::Engine;

use strict;
use warnings;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
	$VERSION	 = 1.00;
	@ISA		 = qw(Exporter);
	@EXPORT		 = qw();
	@EXPORT_OK	 = qw(&bootstrap &get_bsbase &check_host &check_files);
	%EXPORT_TAGS = ( );			# eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

END { }				# module clean-up code here (global destructor)


### bootstrap a base system

sub bootstrap {
	my ($bsbase, $save_path);
	my ($pkgname, $package, @elist);
	my @plist = ("gettext", "tar", "dpkg-bootstrap");
	my @addlist = ("apt", "apt-shlibs", "storable-pm");
	if ("$]" == "5.006") {
		push @addlist, "storable-pm560";
	} elsif ("$]" == "5.006001") {
		push @addlist, "system-perl561", "storable-pm561";
	} elsif ("$]" == "5.008") {
		push @addlist, "system-perl580";
	} elsif ("$]" == "5.008001") {
		push @addlist, "system-perl581";
	} else {
		die "Sorry, this version of Perl ($]) is currently not supported by Fink.\n";
	}

	$bsbase = &get_bsbase();
	&print_breaking("Bootstrapping a base system via $bsbase.");

	# create directories
	if (-e $bsbase) {
		&execute("rm -rf $bsbase");
	}
	&execute("mkdir -p $bsbase");
	&execute("mkdir -p $bsbase/bin");
	&execute("mkdir -p $bsbase/sbin");
	&execute("mkdir -p $bsbase/lib");

	# create empty dpkg database
	&execute("mkdir -p $basepath/var/lib/dpkg");
	&execute("touch $basepath/var/lib/dpkg/status");
	&execute("touch $basepath/var/lib/dpkg/available");
	&execute("touch $basepath/var/lib/dpkg/diversions");

	# set paths so that everything is found
	$save_path = $ENV{PATH};
	$ENV{PATH} = "$basepath/sbin:$basepath/bin:".
				 "$bsbase/sbin:$bsbase/bin:".
				 $save_path;

	# make sure we have the package descriptions
	Fink::Package->require_packages();
	Fink::Shlibs->require_shlibs();

	# determine essential packages
	@elist = Fink::Package->list_essential_packages();


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


	print "\n";
	&print_breaking("BOOTSTRAP PHASE THREE: installing essential packages to ".
					"$basepath with package management.");
	print "\n";

	# use normal install routines
	Fink::Engine::cmd_install(@elist, @addlist);


	print "\n";
	&print_breaking("BOOTSTRAP DONE. Cleaning up.");
	print "\n";
	&execute("rm -rf $bsbase");

	$ENV{PATH} = $save_path;
}

sub get_bsbase {
	return "$basepath/bootstrap";
}

# check_host
# This checks the current host OS version and returns which 
# distribution to use.  It will also warn the user if there
# are any known issues with the system they are using.
# Takes the host as returned by config.guess
# Returns the distribution to use, "unknown" if it cannot
# determine the distribution.
sub check_host {
	my $host = shift @_;
	my $distribution;

	if ($host =~ /^powerpc-apple-darwin1\.[34]/) {
		&print_breaking("This system is supported and tested.");
		$distribution = "10.1";
	} elsif ($host =~ /^powerpc-apple-darwin5\.[0-5]/) {
		&print_breaking("This system is supported and tested.");
		$distribution = "10.1";
	} elsif ($host =~ /^powerpc-apple-darwin6\.[0-6]/) {
		&print_breaking("This system is supported and tested.");
		$distribution = "10.2";
	} elsif ($host =~ /^powerpc-apple-darwin(6\.[7-9]\.)/) {
		&print_breaking("This system was not released at the time " .
			"this Fink release was made, but should work.");
		$distribution = "10.2";
	} elsif ($host =~ /^powerpc-apple-darwin(7\.[0-9]\.)/) {
		&print_breaking("This system was not released at the time " .
			"this Fink release was made, but should work.");
		$distribution = "10.3";
	} elsif ($host =~ /^i386-apple-darwin(6\.[0-6]|[7-9]\.)/) {
		&print_breaking("Fink is currently not supported on x86 ".
			"Darwin. Various parts of Fink hardcode 'powerpc' ".
			"and assume to run on a PowerPC based operating ".
			"system. Use Fink on this system at your own risk!");
		$distribution = "10.2";
	} elsif ($host =~ /^powerpc-apple-darwin1\.[0-2]/) {
		&print_breaking("This system is outdated and not supported ".
			"by this Fink release. Please update to Mac OS X ".
			"10.0 or Darwin 1.3.");
		$distribution = "unknown";
	} else {
		&print_breaking("This system is unrecognized and not ".
			"supported by Fink.");
		$distribution = "unknown";
	}

	return $distribution;
}

# check_self
# Description: this will iterate over the list of files we're supposed
# to have, and checks if they are present.
# Takes no arguments
# Returns 0 on success, 1 if anything is missing.
sub check_files {
	my ($file);
	foreach $file (qw(fink.in install.sh COPYING VERSION
  		perlmod/Fink mirror update fink.info.in postinstall.pl.in
  		update/config.guess perlmod/Fink/Config.pm mirror/_keys fink-virtual-pkgs.in
 	)) {
		if (not -e $file) {
			print "ERROR: Package incomplete, '$file' is missing.\n";
			return 1;
		}
	}
	return 0;
}

### EOF
1;
