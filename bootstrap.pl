#!/usr/bin/perl -w
# -*- mode: Perl; tab-width: 4; -*-
#
# bootstrap.pl - perl script to install and bootstrap a Fink
#								 installation from source
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2006 The Fink Package Manager Team
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

$| = 1;
use 5.008_001;	 # perl 5.8.1 or newer required
use strict;

use FindBin;

my ($answer);
my ($script, $cmd);

### check the perl version

# acceptable perl versions: "$] value" => "human-readable version string"
my %ok_perl_versions = (
    "5.008001" => "5.8.1",
    "5.008002" => "5.8.2",
    "5.008006" => "5.8.6"
);

if (exists $ok_perl_versions{"$]"}) {
    print "Found perl version $].\n";
} else {
    die "\nSorry, your /usr/bin/perl is version $], but Fink can only use" . (
	join "", map {
	    ( $ok_perl_versions{$_} =~ /0$/ ? "\n  " : ", " ) .
	    "$ok_perl_versions{$_} ($_)"
	} sort keys %ok_perl_versions
    )."\n\n";
}

### check if we are unharmed

print "Checking package...";
my ($homebase, $file);

$homebase = $FindBin::RealBin;
chdir $homebase;

use lib "$FindBin::RealBin/perlmod";
require Fink::Bootstrap;
import Fink::Bootstrap qw(&check_host &check_files);
require Fink::FinkVersion;
import Fink::FinkVersion qw(&fink_version &default_binary_version);

my $res = check_files();
if( $res == 1 ) {
	exit 1;
}
printf " looks good (fink-%s).\n", fink_version();

### load some modules

require Fink::Services;
import Fink::Services qw(&read_config &execute &get_arch);
require Fink::CLI;
import Fink::CLI qw(&print_breaking &prompt &prompt_boolean &prompt_selection);
import Fink::Bootstrap qw(&create_tarball &fink_packagefiles &copy_description &get_version_revision);

### check if we like this system

print "Checking system...";
my ($host, $distribution);

$host = `update/config.guess`;
chomp($host);
if ($host =~ /^\s*$/) {
	print " ERROR: Can't determine host type.\n";
	exit 1;
}
print " $host\n";

$distribution = check_host($host,1);
if ($distribution eq "unknown") {
	exit(1);
}

print "Distribution $distribution\n";

# temporary code to help users until we have a good upgrade path
if (($> == 0) and ($distribution ne "10.3")) {
	$answer = &prompt_boolean("Is this the distribution you wish to use?", default => 1);

	if (!$answer) {
		&print_breaking("There is currently no good upgrade path from the 10.4-transitional distribution to the 10.4 distribution, but if you wish to use 10.4-transitional, set the environment variable FINK_NOTRANS to \"false\" while bootstrapping.  To use 10.4, set it to \"true\" (or don't set it at all).");
		exit 1;
	}
}
# end of temporary code

### get version

my ($packageversion, $packagerevision) = &get_version_revision(".",$distribution);

### choose root method

my ($rootmethod);
if ($> != 0) {
	my $sel_intro = "Fink must be installed and run with superuser (root) ".
	    "privileges. Fink can automatically try to become ".
	    "root when it's run from a user account. Since you're ".
	    "currently running this script as a normal user, the ".
	    "method you choose will also be used immediately for ".
	    "this script. Avaliable methods:";
	$answer = &prompt_selection("Choose a method:",
					intro   => $sel_intro,
					default => [ value => "sudo" ],
					choices => [
					  "Use sudo" => "sudo",
					  "Use su" => "su",
					  "None, fink must be run as root" => "none" ] );
	$cmd = "'$homebase/bootstrap.pl' .$answer";
	if ($#ARGV >= 0) {
		$cmd .= " '".join("' '", @ARGV)."'";
	}
	if ($answer eq "sudo") {
		$cmd = "/usr/bin/sudo $cmd";
	} elsif ($answer eq "su") {
		$cmd = "$cmd | /usr/bin/su";
	} else {
		print "ERROR: Can't continue as non-root.\n";
		exit 1;
	}
	print "\n";
	exit &execute($cmd, quiet=>1);
} else {
	if (defined $ARGV[0] and substr($ARGV[0],0,1) eq ".") {
		$rootmethod = shift;
		$rootmethod = substr($rootmethod,1);
	} else {
		print "\n";
		&print_breaking("Fink must be installed and run with superuser (root) ".
						"privileges. Fink can automatically try to become ".
						"root when it's run from a user account. ".
						"Avaliable methods:");
		$answer = &prompt_selection("Choose a method:",
						default => [ value => "sudo" ],
						choices => [
						  "Use sudo" => "sudo",
						  "Use su" => "su",
						  "None, fink must be run as root" => "none" ] );
		$rootmethod = $answer;
	}
}
umask oct("022");

### run some more system tests

my ($response);

print "Checking cc...";
if (-x "/usr/bin/cc") {
	print " looks good.\n";
} else {
	print " not found.\n";
	&print_breaking("ERROR: There is no C compiler on your system. ".
					"Make sure that the Developer Tools are installed.");
	exit 1;
}

print "Checking make...";
if (-x "/usr/bin/make") {
	$response = `/usr/bin/make --version 2>&1`;
	if ($response =~ /GNU Make/si) {
		print " looks good.\n";
	} else {
		print " is not GNU make.\n";
		&print_breaking("ERROR: /usr/bin/make exists, but is not the ".
						"GNU version. You must correct this situation before ".
						"installing Fink. /usr/bin/make should be a symlink ".
						"pointing to /usr/bin/gnumake.");
		exit 1;
	}
} else {
	print " not found.\n";
	&print_breaking("ERROR: There is no make utility on your system. ".
					"Make sure that the Developer Tools are installed.");
	exit 1;
}

print "Checking head...";
if (-x "/usr/bin/head") {
	$response = `/usr/bin/head -1 /dev/null 2>&1`;
	if ($response =~ /Unknown option/si) {
		print " is broken.\n";
		&print_breaking("ERROR: /usr/bin/head seems to be corrupted. ".
						"This can happen if you manually installed Perl libwww. ".
						"You'll have to restore /usr/bin/head from another ".
						"machine or from installation media.");
		exit 1;
	} else {
		print " looks good.\n";
	}
} else {
	print " not found.\n";
	&print_breaking("ERROR: There is no head utility on your system. ".
					"Make sure that the Developer Tools are installed.");
	exit 1;
}

### setup the correct packages directory
# (no longer needed: we just use $distribution directly...)
#
#if (-e "packages") {
#		rename "packages", "packages-old";
#		unlink "packages";
#}
#symlink "$distribution", "packages" or die "Cannot create symlink";

### choose installation path

# Check if a location has installed software
sub has_installed_software {
	my $loc = shift;
	return (-d "$loc/bin" or -d "$loc/lib" or -d "$loc/include");
}

my $retrying = 0;
my $nonstandard_warning = 0;

my $installto = shift || "";

OPT_BASEPATH: { ### install path redo block

# ask if the path wasn't passed as a parameter
if ($retrying || not $installto) {
	my $default = '/sw';
	while (1) {
		last if !has_installed_software($default);
		$default =~ /^(.*?)(\d*)$/;
		$default = $1 . (($2 || 1) + 1);
	}
	
	print "\n";
	if ($default ne '/sw' && !$nonstandard_warning) {
		print "It looks like you already have Fink installed in /sw, trying "
		.	"$default instead.\n\n"
		.	"WARNING: This is a non-standard location.\n\n";
		$nonstandard_warning = 1;
	}
	my $prompt = "Please choose the path where Fink should be installed. Note "
		. "that you will be able to use the binary distribution only if you "
		. "choose '/sw'.";
	$installto =
		&prompt($prompt, default => $default);
}
$retrying = 1;
print "\n";

# catch formal errors
if ($installto eq "") {
	print "ERROR: Install path is empty.\n";
	redo OPT_BASEPATH;
}
if (substr($installto,0,1) ne "/") {
	print "ERROR: Install path '$installto' doesn't start with a slash.\n";
	redo OPT_BASEPATH;
}
if ($installto =~ /\s/) {
	print "ERROR: Install path '$installto' contains whitespace.\n";
	redo OPT_BASEPATH;
}

# remove any trailing slash(es)
$installto =~ s,^(/.*?)/*$,$1,;

# check well-known path (NB: these are regexes!)
foreach my $forbidden (
	qw(/ /etc /usr /var /bin /sbin /lib /tmp /dev
	   /usr/lib /usr/include /usr/bin /usr/sbin /usr/share
	   /usr/libexec /usr/X11R6
	   /root /private /cores /boot
	   /debian /debian/.*)
) {
	if ($installto =~ /^$forbidden$/i) {
		print "ERROR: Refusing to install into '$installto'.\n";
		redo OPT_BASEPATH;
	}
}
if ($installto =~ /^\/usr\/local$/i) {
	$answer =
		&prompt_boolean("Installing Fink in /usr/local is not recommended. ".
						"It may conflict with third party software also ".
						"installed there. It will be more difficult to get ".
						"rid of Fink when something breaks. Are you sure ".
						"you want to install to /usr/local?", default => 0);
	if ($answer) {
		&print_breaking("You have been warned. Think twice before reporting ".
						"problems as a bug.");
	} else {
		redo OPT_BASEPATH;
	}
} elsif (-d $installto) {
	# check existing contents
	if (has_installed_software $installto) {
		&print_breaking("ERROR: '$installto' exists and contains installed ".
						"software. Refusing to install there.");
		redo OPT_BASEPATH;
	} else {
		&print_breaking("WARNING: '$installto' already exists. If bootstrapping ".
						"fails, try removing the directory altogether and ".
						"re-run bootstrap.sh.");
	}
} else {
	&print_breaking("OK, installing into '$installto'.");
}
print "\n";
}

### create directories

print "Creating directories...\n";
my ($dir, @dirlist);

if (not -d $installto) {
	if (&execute("/bin/mkdir -p -m755 $installto")) {
		print "ERROR: Can't create directory '$installto'.\n";
		exit 1;
	}
}

my $arch = get_arch();

@dirlist = qw(etc etc/alternatives etc/apt src fink fink/debs var var/lib var/lib/fink);
push @dirlist, "fink/$distribution", "fink/$distribution/stable", "fink/$distribution/local";
foreach $dir (qw(stable/main stable/crypto local/main)) {
	push @dirlist, "fink/$distribution/$dir", "fink/$distribution/$dir/finkinfo",
		"fink/$distribution/$dir/binary-darwin-$arch";
}
foreach $dir (@dirlist) {
	if (not -d "$installto/$dir") {
		if (&execute("/bin/mkdir -m755 $installto/$dir")) {
			print "ERROR: Can't create directory '$installto/$dir'.\n";
			exit 1;
		}
	}
}

unlink "$installto/fink/dists";

symlink "$distribution", "$installto/fink/dists" or die "ERROR: Can't create symlink $installto/fink/dists";

### create fink tarball for bootstrap

my $packagefiles = &fink_packagefiles();

my $result = &create_tarball($installto, "fink", $packageversion, $packagefiles);
if ($result == 1 ) {
	exit 1;
}

### copy package info needed for bootstrap

$script = "/bin/mkdir -p $installto/fink/dists/stable/main/finkinfo/base\n";
$script .= "/bin/cp $distribution/*.info $distribution/*.patch $installto/fink/dists/stable/main/finkinfo/base/\n";

$result = &copy_description($script,$installto, "fink", $packageversion, $packagerevision, "stable/main/finkinfo/base");
if ($result == 1 ) {
	exit 1;
}

### load the Fink modules

require Fink::Config;
require Fink::Engine;
require Fink::Configure;
require Fink::Bootstrap;

### setup initial configuration

print "Creating initial configuration...\n";
my ($configpath, $config, $engine);

$configpath = "$installto/etc/fink.conf";
open(CONFIG, ">$configpath") or die "can't create configuration: $!";
print CONFIG <<"EOF";
# Fink configuration, initially created by bootstrap.pl
Basepath: $installto
RootMethod: $rootmethod
Trees: local/main stable/main stable/crypto
Distribution: $distribution
EOF
close(CONFIG) or die "can't write configuration: $!";

$config = &read_config($configpath);
# override path to data files (update, mirror)
no warnings 'once';
$Fink::Config::libpath = $homebase;
use warnings 'once';
$engine = Fink::Engine->new_with_config($config);

### interactive configuration

Fink::Configure::configure();

### bootstrap

Fink::Bootstrap::bootstrap();

### remove dpkg-bootstrap.info, to avoid later confusion

&execute("/bin/rm -f $installto/fink/dists/stable/main/finkinfo/base/dpkg-bootstrap.info");

### copy included package info tree if present

my $showversion = "";
if ($packageversion !~ /cvs/) {
	$showversion = "-$packageversion";
}

my $endmsg = "Internal error.";

chdir $homebase;
my $dbv = default_binary_version($distribution);
if (-d "pkginfo") {
	if (&execute("cd pkginfo && ./inject.pl $installto -quiet")) {
		# inject failed
		$endmsg = <<"EOF";
Copying the package description tree failed. This is no big harm;
your Fink installation should work nonetheless.
You can add the package descriptions at a later time if you want to
compile packages yourself.
You can get them
EOF
if (not $dbv eq "none") {
$endmsg .= "by installing the dists-$distribution-$dbv.tar.gz
tarball, or";
}
		$endmsg .= " by running the command 'fink selfupdate'.";
	} else {
		# inject worked
		$endmsg = <<"EOF";
You should now have a working Fink installation in '$installto'.
EOF
	}
} else {
	# this was not the 'full' tarball
	$endmsg = <<"EOF";
You should now have a working Fink installation in '$installto'.
You still need package descriptions if you want to compile packages yourself.
You can get them
EOF
if (not $dbv eq "none") {
$endmsg .= "by installing the dists-$distribution-$dbv.tar.gz
tarball, or";
}
	$endmsg .= " by running the command 'fink selfupdate'.";
}

### create Packages.gz files for apt

# set PATH so we find dpkg-scanpackages
$ENV{PATH} = "$installto/sbin:$installto/bin:".$ENV{PATH};

Fink::Engine::cmd_scanpackages();

### the final words...

$endmsg =~ s/\s+/ /gs;
$endmsg =~ s/ $//;

print "\n";
&print_breaking($endmsg);
print "\n";
&print_breaking(
    "Run '. $installto/bin/init.sh' to set up this terminal session ".
    "environment to use Fink. To make the software installed by Fink ".
    "available in all of your future terminal shells, add ".
    "'. $installto/bin/init.sh' to the init script '.profile' or ".
    "'.bash_profile' in your home directory. The program ".
    "$installto/bin/pathsetup.sh can help with this. Enjoy."
);
print "\n";

### eof
exit 0;


# vim: ts=4 sw=4 noet
