# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Bootstrap module
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2005 The Fink Package Manager Team
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
use Fink::Services qw(&execute &file_MD5_checksum &enforce_gcc &eval_conditional);
use Fink::CLI qw(&print_breaking &prompt_boolean);
use Fink::Package;
use Fink::PkgVersion;
use Fink::Engine;
use Fink::Command qw(cat mkdir_p rm_rf touch);

use strict;
use warnings;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
	$VERSION	 = 1.00;
	@ISA		 = qw(Exporter);
	@EXPORT		 = qw();
	@EXPORT_OK	 = qw(&bootstrap &get_bsbase &check_host &check_files &fink_packagefiles &locate_Fink &get_packageversion &find_rootmethod &create_tarball &copy_description &inject_package &modify_description &get_version_revision &read_version_revision &additional_packages);
	%EXPORT_TAGS = ( );			# eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

END { }				# module clean-up code here (global destructor)


=head1 NAME

Fink::Bootstrap - Bootstrap a fink installation

=head1 SYNOPSIS

  use Fink::Bootstrap qw(:ALL);

	my $distribution = check_host($host);
	my $result = inject_package($package, $packagefiles, $info_script, $param);
    my ($package_list, $perl_is_supported) = additional_packages();
	bootstrap();
	my $bsbase = get_bsbase();
	my $result = check_files();
	my $packagefiles = fink_packagefiles();
	my ($notlocated, $basepath) = locate_Fink();
	my ($notlocated, $basepath) = locate_Fink($param);
	my ($version, $revision) = get_packageversion();
	find_rootmethod($bpath);
	my $result = create_tarball($bpath, $package, $packageversion, $packagefiles);
	my $result = copy_description($script, $bpath, $package, $packageversion, $packagerevision);
	my $result = copy_description($script, $bpath, $package, $packageversion, $packagerevision, $destination);
	my $result = modify_description($original,$target,$tarball,$package_source,$source_location,$distribution,$coda);
	my ($version, $revisions) = read_version_revision($package_source);
	my ($version, $revision) = get_version_revision($package_source,$distribution);


=head1 DESCRIPTION

This module defines functions that are used to bootstrap a fink installation 
or update to a new version.  The functions are intended to be called from
scripts that are not part of fink itself.  In particular, the scripts 
bootstrap.pl, inject.pl, scripts/srcdist/dist-module.pl, and fink's 
postinstall.pl all depend on functions from this module.

=head2 Functions

These functions are exported on request.  You can export them all with

  use Fink::Bootstrap qw(:ALL);


=over 4

=item check_host

	my $distribution = check_host($host);

Checks the current host OS version and returns which distribution to use,
or "unknown."  $host should be as determined by config.guess.

This function also warns the user about certain bad configurations, or 
incorrect versions of gcc.

After every release of Mac OS X, fink should be tested against the new
release and then this function should be updated.

Called by bootstrap.pl and fink's postinstall.pl.

=cut

sub check_host {
	my $host = shift @_;
	my ($distribution, $gcc, $build);

	# We test for an obsolete version of gcc3.3, and refuse to proceed if
    # it is present.
    #
	# (Note: the June 2003 Developer Tools had build 1435, the August 2003 ones
	#  had build 1493.)

	if (-x '/usr/bin/gcc-3.3') {
		foreach(`/usr/bin/gcc-3.3 --version`) {
			if (/build (\d+)\)/) {
				$build = $1;
				last;
			}
		}
		($build >= 1493) or die <<END;

Your version of the gcc 3.3 compiler is out of date.  Please update to the 
August 2003 Developer Tools update, or to Xcode, and try again.

END
}

	# We check to see if gcc is installed, and if it is the correct version.
	# If so, we set $gcc so that 10.2 users will get the 10.2-gcc3.3 tree.

	if (-x '/usr/bin/gcc') {
$gcc = Fink::Services::enforce_gcc("Under CURRENT_SYSTEM, Fink must be bootstrapped or updated using\n" .
"gcc EXPECTED_GCC.  However, you currently have gcc INSTALLED_GCC selected.\n" .
"To correct this problem, run the command:\n\n" .
								   "    sudo gcc_select GCC_SELECT_COMMAND\n\n");
		$gcc = "-gcc" . $gcc;
} else {
## 10.2 users who do not have gcc at all are installing binary only, so they get
## to move to 10.2-gcc3.3 also
	$gcc = "-gcc3.3";
}

	if ($host =~ /^powerpc-apple-darwin1\.[34]/) {
		&print_breaking("\nThis system is no longer supported " .
"for current versions of fink.  Please use fink 0.12.1 or earlier.\n");
		$distribution = "10.1";
	} elsif ($host =~ /^powerpc-apple-darwin5\.[0-5]/) {
		&print_breaking("\nThis system is no longer supported " .
"for current versions of fink.  Please use fink 0.12.1 or earlier.\n");
		$distribution = "10.1";
	} elsif ($host =~ /^powerpc-apple-darwin6\.[0-8]/) {
		if (not $gcc =~ /gcc3.3/) {
             &print_breaking("\nFink no longer supports the old Developer " .
             "Tools on 10.2. Please update to the August 2003 Developer " .
             "Tools, and try again.\n");
							} else {
		     &print_breaking("This system is supported and tested.");
		 }
		$distribution = "10.2$gcc";
	} elsif ($host =~ /^powerpc-apple-darwin6\..*/) {
		&print_breaking("This system was not released at the time " .
			"this Fink release was made, but should work.");
		$distribution = "10.2$gcc";
	} elsif ($host =~ /^powerpc-apple-darwin7\.[0-8]\.0/) {
		&print_breaking("This system is supported and tested.");
		$distribution = "10.3";
	} elsif ($host =~ /^powerpc-apple-darwin7\..*/) {
		&print_breaking("This system was not released at the time " .
			"this Fink release was made, but should work.");
		$distribution = "10.3";
	} elsif ($host =~ /^powerpc-apple-darwin[8-9]\./) {
		&print_breaking("This system was not released at the time " .
			"this Fink release was made.  Prerelease versions " .
			"of Mac OS X might work with Fink, but there are no " .
			"guarantees.");
		$distribution = "10.3";
	} elsif ($host =~ /^i386-apple-darwin7\.[0-2]\.[0-1]/) {
		&print_breaking("Fink is currently not supported on x86 ".
			"Darwin. Various parts of Fink hardcode 'powerpc' ".
			"and assume to run on a PowerPC based operating ".
			"system. Use Fink on this system at your own risk!");
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
	my $distribution = `ls -ld $bpath/fink/dists`;
	chomp($distribution);
	$distribution =~ s/^.*->\s+//;
#	print "DISTRIBUTION $distribution\n";

	### get version
	
#	my ($packageversion, $packagerevision) = &get_packageversion();
	my ($packageversion, $packagerevision) = &get_version_revision(".",$distribution);
	
	### load configuration
	
	my $config = &read_config("$bpath/etc/fink.conf",
							  { Basepath => $bpath });
	
	### parse config file for root method

	&find_rootmethod($bpath);
	
	### check that local/injected is in the Trees list
	
	my $trees = $config->param("Trees");
	if ($trees =~ /^\s*$/) {
		print "Adding a Trees line to fink.conf...\n";
		$config->set_param("Trees", "local/main stable/main stable/crypto local/injected");
		$config->save();
	} else {
		if (grep({$_ eq "local/injected"} split(/\s+/, $trees)) < 1) {
			print "Adding local/injected to the Trees line in fink.conf...\n";
			$config->set_param("Trees", "$trees local/injected");
			$config->save();
		}
	}
	
	### create tarball for the package
	
	my $result = &create_tarball($bpath, $package, $packageversion, $packagefiles);
	if ($result == 1 ) {
		return $result;
	}
	
	### create and copy description file
	
	$result = &copy_description($info_script, $bpath, $package, $packageversion, $packagerevision);
	if ($result == 1 ) {
		return $result;
	}
	
	### install the package
	
	print "Installing package...\n";
	print "\n";
	
	if (&execute("$bpath/bin/fink install $package")) {
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

=item additional_packages

	my ($package_list, $perl_is_supported) = additional_packages();

Returns (1) a reference to the list of non-essential packages which must be 
installed during bootstrap or selfupdate (this answer is affected by the
currently-running version of perl), and (2) a boolean value which is
"True" if the currently-running version of perl is on the list of those
versions supported during bootstrapping, and "False" otherwise.


Called by bootstrap() and by Fink::SelfUpdate::finish().

=cut

sub additional_packages {

	my $perl_is_supported = 1;

	my @addlist = ("apt", "apt-shlibs", "storable-pm", "bzip2-dev", "gettext-dev", "gettext-bin", "libiconv-dev", "ncurses-dev");
	if ("$]" == "5.006") {
		push @addlist, "storable-pm560", "file-spec-pm560", "test-harness-pm560", "test-simple-pm560";
	} elsif ("$]" == "5.006001") {
		push @addlist, "storable-pm561", "file-spec-pm561", "test-harness-pm561", "test-simple-pm561";
	} elsif ("$]" == "5.008") {
	} elsif ("$]" == "5.008001") {
	} elsif ("$]" == "5.008002") {
	} elsif ("$]" == "5.008006") {
	} else {
# unsupported version of perl
		$perl_is_supported = 0;
	}

	return (\@addlist, $perl_is_supported);

}

=item bootstrap 

	bootstrap();

The primary bootstrap routine, called by bootstrap.pl.

=cut

sub bootstrap {
	my ($bsbase, $save_path);
	my ($pkgname, $package, @elist);
	my @plist = ("gettext", "tar", "dpkg-bootstrap");
	my ($package_list, $perl_is_supported) = additional_packages();
	my @addlist = @{$package_list};
	die "Sorry, this version of Perl ($]) is currently not supported by Fink.\n" unless $perl_is_supported;

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

	# make sure we have the package descriptions
	Fink::Package->require_packages();

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

#	# use normal install routines, but do not use buildlocks
#	Fink::Config::set_options( { 'no_buildlock' => 1 } );
	Fink::Engine::cmd_install(@elist, @addlist);
#	Fink::Config::set_options( { 'no_buildlock' => 0 } );

	print "\n";
	&print_breaking("BOOTSTRAP DONE. Cleaning up.");
	print "\n";
	rm_rf $bsbase;

	$ENV{PATH} = $save_path;
}

=item get_bsbase

	my $bsbase = get_bsbase();

Returns the base path for bootstrapping.  Called by bootstrap().

=cut

sub get_bsbase {
	return "$basepath/bootstrap";
}

=item check_files

	my $result = check_files();

Tests whether the current directory contains all of the files needed to 
compile fink.  Returns 0 on success, 1 on failure.

Called by bootstrap.pl and fink's inject.pl.

=cut

sub check_files {
	my ($file);
	foreach $file (qw(fink.in install.sh COPYING VERSION
  		perlmod/Fink update fink.info.in postinstall.pl.in
  		update/config.guess perlmod/Fink/Config.pm fink-virtual-pkgs.in
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

Returns a list of all files which should be contained in the fink tarball.  
Called by bootstrap.pl and fink's inject.pl.

=cut

sub fink_packagefiles {

my $packagefiles = "COPYING INSTALL INSTALL.html README README.html USAGE USAGE.html Makefile ".
  "ChangeLog VERSION REVISION fink.in fink.8.in fink.conf.5.in install.sh setup.sh ".
  "shlibs.default.in pathsetup.sh.in postinstall.pl.in perlmod update t ".
  "fink-virtual-pkgs.in";

return $packagefiles;

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

=item get_packageversion

	my ($version, $revision) = get_packageversion();

Finds the current version (by examining the VERSION file) and the current
revision (which defaults to 1 or a cvs timestamp) of the package being 
compiled.

Formerly called by bootstrap.pl and inject_package(); now obsolete.

=cut

sub get_packageversion {

	my ($packageversion, $packagerevision);
	
	chomp($packageversion = cat "VERSION");
	if ($packageversion =~ /cvs/) {
	my @now = gmtime(time);
		$packagerevision = sprintf("%04d%02d%02d.%02d%02d",
		                           $now[5]+1900, $now[4]+1, $now[3],
		                           $now[2], $now[1]);
	} else {
		$packagerevision = "1";
	}
	return ($packageversion, $packagerevision);
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
		exit &execute("sudo ./inject.pl $bpath");
	}
	umask oct("022");
}

=item create_tarball

	my $result = create_tarball($bpath, $package, $packageversion, $packagefiles);

Create the directory $bpath/src if necessary, then create the tarball 
$bpath/src/$package-$packageversion.tar containing the files $packagefiles.
Returns 0 on success, 1 on failure.

Called by bootstrap.pl and inject_package().

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
	return $result;
}

=item copy_description

	my $result = copy_description($script, $bpath, $package, $packageversion, $packagerevision);
	my $result = copy_description($script, $bpath, $package, $packageversion, $packagerevision, $destination);

Execute the given $script, create the directories $bpath/fink/debs and
$bpath/fink/dists/$destination if necessary, and backup the file
$bpath/fink/dists/$destination/$package.info if it already exists.  

Next, copy $package.info.in (from the current directory) to 
$bpath/fink/dists/$destination/$package.info, supplying the correct
$packageversion and $packagerevision as well as an MD5 sum calculated from
$bpath/src/$package-$packageversion.tar.  Ensure that the created file
has mode 644.

Returns 0 on success, 1 on failure.  The default $destination, if not 
supplied, is "local/injected/finkinfo".

Called by bootstrap.pl and inject_package().

=cut

sub copy_description {
	
	my $script = shift;
	my $bpath = shift;
	my $package = shift;
	my $packageversion = shift;
	my $packagerevision = shift;

	my $destination = shift || "local/injected/finkinfo";
	
	my ($cmd);
	
	print "Copying package description(s)...\n";
	
	if (not -d "$bpath/fink/debs") {
		$script .= "/bin/mkdir -p -m755 $bpath/fink/debs\n";
	}
	if (not -d "$bpath/fink/dists/$destination") {
		$script .= "/bin/mkdir -p -m755 $bpath/fink/dists/$destination\n";
	}
	if (-e "$bpath/fink/dists/$destination/$package.info") {
#		if (-e "$bpath/fink/dists/$destination/$package.info.bak") {
#			my $answer = &prompt_boolean("\nWARNING: The file $bpath/fink/dists/$destination/$package.info.bak exists and will be overwritten.  Do you wish to continue?", 1);
#			if (not $answer) {
#				die "\nOK, you can re-run ./inject.pl after moving the file.\n\n";
#			}
			unlink "$bpath/fink/dists/$destination/$package.info.bak";
#		}
#		&print_breaking("\nNOTICE: the previously existing file $bpath/fink/dists/$destination/$package.info has been moved to $bpath/fink/dists/$destination/$package.info.bak .\n\n");
		&execute("/bin/mv $bpath/fink/dists/$destination/$package.info $bpath/fink/dists/$destination/$package.info.bak");
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
	my $distribution = `ls -ld $bpath/fink/dists`;
	chomp($distribution);
	$distribution =~ s/^.*->\s+//;
#	print "DISTRIBUTION $distribution\n";

	my $coda = "NoSourceDirectory: true\n";

	if (modify_description("$package.info.in","$bpath/fink/dists/$destination/$package.info","$bpath/src/$package-$packageversion.tar",".","%n-%v.tar",$distribution,$coda)) {
			print "ERROR: Can't copy package description(s).\n";
			$result = 1;
		} elsif (&execute("/bin/chmod 644 $bpath/fink/dists/$destination/*.*")) {
			print "ERROR: Can't copy package description(s).\n";
			$result = 1;
		}
	
	return $result;
}			 

=item modify_description

	my $result = modify_description($original,$target,$tarball,$package_source,$source_location,$distribution,$coda);

Copy the file $original to $target, supplying the correct version and
revision (from get_version_revision($package_source,$distribution)) and 
$source_location as well as an MD5 sum calculated from 
$tarball.  Pre-evaluate any conditionals containing %{Distribution}, using
$distribution as the value of %{Distribution}.  Append $coda to the end 
of the file.

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

	my ($version, $revision) = get_version_revision($package_source,$distribution);
	print "Modifying package description...\n";
	my $md5 = &file_MD5_checksum($tarball);

	my $result = 0;

	open(IN,$original) or die "can't open $original: $!";
	open(OUT,">$target") or die "can't write $target: $!";
	while (<IN>) {
		chomp;
		$_ =~ s/\@VERSION\@/$version/;
		$_ =~ s/\@REVISION\@/$revision/;
		$_ =~ s/\@SOURCE\@/$source_location/;
		$_ =~ s/\@MD5\@/$md5/;
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
		while(<IN>) {
			chomp;
			/(.*):\s*(.*)/;
			$revision_data{$1} = $2;
		}
		close(IN);
	}

	my ($packageversion,$packagerevision,$revisions);
	
	chomp($packageversion = cat "$package_source/VERSION");
	if ($packageversion =~ /cvs/) {
		my @now = gmtime(time);
		$packagerevision = sprintf("%04d%02d%02d.%02d%02d",
		                           $now[5]+1900, $now[4]+1, $now[3],
		                           $now[2], $now[1]);
		$revisions = {"all" => $packagerevision};
	} elsif (-f "$package_source/REVISION") {
		open(IN,"$package_source/REVISION") or die "Can't open $package_source/REVISION: $!";
		while(<IN>) {
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

Called by bootstrap.pl, inject_package(), and modify_description().

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

=back

=cut

### EOF
1;
