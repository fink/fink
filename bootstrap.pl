#!/usr/bin/perl -w
#
# bootstrap.pl - perl script to install and bootstrap a Fink
#                installation from source
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
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#

$| = 1;
use v5.6.0;  # perl 5.6.0 or newer required
use strict;

use FindBin;

my ($answer, $packageversion, $packagerevision);
my ($script, $cmd);

### check if we're unharmed

print "Checking package...";
my ($homebase, $file);

$homebase = $FindBin::RealBin;
chdir $homebase;

foreach $file (qw(fink.in install.sh COPYING VERSION
		  perlmod/Fink mirror update 10.1 10.2 fink.info.in
		  update/config.guess perlmod/Fink/Config.pm mirror/_keys
		 )) {
  if (not -e $file) {
    print " INCOMPLETE: '$file' missing\n";
    exit 1;
  }
}
print " looks good.\n";

### load some modules

unshift @INC, "$FindBin::RealBin/perlmod";

require Fink::Services;
import Fink::Services qw(&print_breaking &prompt &prompt_boolean
                         &prompt_selection &read_config &execute);

### get version

chomp($packageversion = `cat VERSION`);
if ($packageversion =~ /cvs/) {
  my @now = gmtime(time);
  $packagerevision = sprintf("%04d%02d%02d.%02d%02d",
			     $now[5]+1900, $now[4]+1, $now[3],
			     $now[2], $now[1]);
} else {
  $packagerevision = "1";
}

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

if ($host =~ /^powerpc-apple-darwin1\.[34]/) {
  &print_breaking("This system is supported and tested.");
  $distribution = "10.1";
} elsif ($host =~ /^powerpc-apple-darwin5\.[0-5]/) {
  &print_breaking("This system is supported and tested.");
  $distribution = "10.1";
} elsif ($host =~ /^powerpc-apple-darwin6\.[0-4]/) {
  &print_breaking("This system is supported and tested.");
  $distribution = "10.2";
} elsif ($host =~ /^(powerpc|i386)-apple-darwin(6\.[5-9]|[7-9]\.)/) {
  &print_breaking("This system was not released at the time this Fink ".
		  "release was made, but should work.");
  $distribution = "10.2";
} elsif ($host =~ /^powerpc-apple-darwin1\.[0-2]/) {
  &print_breaking("This system is outdated and not supported by this Fink ".
		  "release. Please update to Mac OS X 10.0 or Darwin 1.3.");
  exit 1;
} else {
  &print_breaking("This system is unrecognized and not supported by Fink.");
  exit 1;
}

print "Distribution $distribution\n";

### choose root method

my $rootmethods = { "sudo" => "Use sudo", "su" => "Use su",
		    "none" => "None, fink must be run as root" };
my ($rootmethod);
if ($> != 0) {
  print "\n";
  &print_breaking("Fink must be installed and run with superuser (root) ".
		  "privileges. Fink can automatically try to become ".
		  "root when it's run from a user account. Since you're ".
		  "currently running this script as a normal user, the ".
		  "method you choose will also be used immediately for ".
		  "this script. Avaliable methods:");
  $answer = &prompt_selection("Choose a method:",
			      1, $rootmethods, "sudo", "su", "none");
  $cmd = "'$homebase/bootstrap.pl' .$answer";
  if ($#ARGV >= 0) {
    $cmd .= " '".join("' '", @ARGV)."'";
  }
  if ($answer eq "sudo") {
    $cmd = "sudo $cmd";
  } elsif ($answer eq "su") {
    $cmd = "$cmd | su";
  } else {
    print "ERROR: Can't continue as non-root.\n";
    exit 1;
  }
  print "\n";
  exit &execute($cmd, 1);
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
				3, $rootmethods, "sudo", "su", "none");
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

if (-e "packages") {
    rename "packages", "packages-old";
    unlink "packages";
}
symlink "$distribution", "packages" or die "Cannot create symlink";

### choose installation path

my ($installto, $forbidden);

$installto = shift || "";

# ask if the path wasn't passed as a parameter
if (not $installto) {
  print "\n";
  $installto =
    &prompt("Please choose the path where Fink should be installed.",
	    "/sw");
}
print "\n";

# catch formal errors
if ($installto eq "") {
  print "ERROR: Install path is empty.\n";
  exit 1;
}
if (substr($installto,0,1) ne "/") {
  print "ERROR: Install path '$installto' doesn't start with a slash.\n";
  exit 1;
}
if ($installto =~ /\s/) {
  print "ERROR: Install path '$installto' contains whitespace.\n";
  exit 1;
}

# remove trailing slash
if (length($installto) > 1 and substr($installto,-1) eq "/") {
  $installto = substr($installto,0,-1);
}
# check well-known paths
foreach $forbidden (qw(/ /etc /usr /var /bin /sbin /lib /tmp /dev
		       /usr/lib /usr/include /usr/bin /usr/sbin /usr/share
		       /usr/libexec /usr/X11R6
		       /root /private /cores /boot)) {
  if ($installto eq $forbidden) {
    print "ERROR: Refusing to install into '$installto'.\n";
    exit 1;
  }
}
if ($installto eq "/usr/local") {
  $answer =
    &prompt_boolean("Installing Fink in /usr/local is not recommended. ".
		    "It may conflict with third party software also ".
		    "installed there. It will be more difficult to get ".
		    "rid of Fink when something breaks. Are you sure ".
		    "you want to install to /usr/local?", 0);
  if ($answer) {
    &print_breaking("You have been warned. Think twice before reporting ".
		    "problems as a bug.");
  } else {
    exit 1;
  }
} elsif (-d $installto) {
  # check existing contents
  if (-d "$installto/bin" or -d "$installto/lib" or -d "$installto/include") {
    &print_breaking("ERROR: '$installto' exists and contains installed ".
		    "software. Refusing to install there.");
    exit 1;
  } else {
    &print_breaking("WARNING: '$installto' already exists. If bootstrapping ".
		    "fails, try removing the directory altogether and ".
		    "re-run bootstrap.sh.");
  }
} else {
  &print_breaking("OK, installing into '$installto'.");
}
print "\n";

### create directories

print "Creating directories...\n";
my ($dir, @dirlist);

if (not -d $installto) {
  if (&execute("mkdir -p $installto")) {
    print "ERROR: Can't create directory '$installto'.\n";
    exit 1;
  }
}

@dirlist = qw(etc etc/alternatives src fink fink/debs);
push @dirlist, "fink/$distribution", "fink/$distribution/stable", "fink/$distribution/local";
foreach $dir (qw(local/bootstrap stable/main stable/crypto local/main)) {
  push @dirlist, "fink/$distribution/$dir", "fink/$distribution/$dir/finkinfo",
    "fink/$distribution/$dir/binary-darwin-powerpc";
}
foreach $dir (@dirlist) {
  if (not -d "$installto/$dir") {
    if (&execute("mkdir $installto/$dir")) {
      print "ERROR: Can't create directory '$installto/$dir'.\n";
      exit 1;
    }
  }
}

symlink "$distribution", "$installto/fink/dists" or die "ERROR: Can't create symlink $installto/fink/dists";

### copy package info needed for bootstrap

print "Copying package descriptions...\n";

$script = "cp packages/*.info packages/*.patch $installto/fink/dists/local/bootstrap/finkinfo/\n";

$script .= "sed -e 's/\@VERSION\@/$packageversion/' -e 's/\@REVISION\@/$packagerevision/' -e 's|\@PREFIX\@|$installto|' <fink.info.in >$installto/fink/dists/local/bootstrap/finkinfo/fink-$packageversion.info\n";

$script .= "chmod 644 $installto/fink/dists/local/bootstrap/finkinfo/*.*\n";

foreach $cmd (split(/\n/,$script)) {
  next unless $cmd;   # skip empty lines

  if (&execute($cmd)) {
    print "ERROR: Can't copy package descriptions.\n";
    exit 1;
  }
}

### create fink tarball for bootstrap

print "Creating fink tarball...\n";

$script =
  "tar -cf $installto/src/fink-$packageversion.tar ".
  "COPYING INSTALL INSTALL.html README README.html USAGE USAGE.html ".
  "ChangeLog VERSION fink.in fink.8.in fink.conf.5.in install.sh setup.sh ".
  "postinstall.pl.in perlmod update mirror shlibs.default.in\n";

foreach $cmd (split(/\n/,$script)) {
  next unless $cmd;   # skip empty lines

  if (&execute($cmd)) {
    print "ERROR: Can't create tarball.\n";
    exit 1;
  }
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
Trees: local/main stable/main stable/crypto local/bootstrap
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

### copy included package info tree if present

my $showversion = "";
if ($packageversion !~ /cvs/) {
  $showversion = "-$packageversion";
}

my $endmsg = "Internal error.";

chdir $homebase;
if (-d "pkginfo") {
  if (&execute("cd pkginfo && ./inject.pl $installto -quiet")) {
    # inject failed
    $endmsg = <<"EOF";
Copying the package description tree failed. This is no big harm;
your Fink installation should work nonetheless.
You can add the package descriptions at a later time if you want to
compile packages yourself.
You can get them from CVS or by installing the packages$showversion.tar.gz
tarball.
EOF
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
You can get them from CVS or by installing the packages$showversion.tar.gz
tarball.
EOF
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
&print_breaking("Run 'source $installto/bin/init.csh ; rehash' to set ".
		"up this Terminal's environment to use Fink. To make the ".
		"software installed by Fink available in all of your ".
		"shells, add 'source $installto/bin/init.csh' to the ".
		"init script '.cshrc' in your home directory. Enjoy.");
print "\n";

### eof
exit 0;
