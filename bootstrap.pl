#!/usr/bin/perl -w
#
# bootstrap.pl - perl script to install and bootstrap a Fink
#                installation from source
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
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
use lib "$FindBin::RealBin/perlmod";
use Fink::Services qw(&print_breaking &prompt &prompt_boolean &prompt_selection
                      &read_config &execute);
use Fink::Config qw($basepath $libpath);
use Fink::Engine;
use Fink::Configure;
use Fink::Bootstrap;

my ($answer, $packageversion, $packagerevision);
my ($script, $cmd);

### check if we're unharmed

print "Checking package...";
my ($homebase, $file);

$homebase = $FindBin::RealBin;
chdir $homebase;

foreach $file (qw(fink install.sh COPYING VERSION
		  perlmod/Fink mirror update base-files packages
		  update/config.guess perlmod/Fink/Config.pm mirror/_keys
		 )) {
  if (not -e $file) {
    print " INCOMPLETE: '$file' missing\n";
    exit 1;
  }
}
print " looks good.\n";

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
my ($host);

$host = `update/config.guess`;
chomp($host);
if ($host =~ /^\s*$/) {
  print " ERROR: Can't determine host type.\n";
  exit 1;
}
print " $host\n";

if ($host =~ /^powerpc-apple-darwin1\.3/) {
  &print_breaking("This system is supported and tested.");
} elsif ($host =~ /^powerpc-apple-darwin(1\.[3-9]|[2-9]\.)/) {
  &print_breaking("This system was not released at the time this Fink ".
		  "release was made, but should work.");
} elsif ($host =~ /^powerpc-apple-darwin1\.[0-2]/) {
  &print_breaking("This system is outdated and not supported by this Fink ".
		  "release. Please update to Mac OS X 10.0 or Darwin 1.3.");
  exit 1;
} else {
  &print_breaking("This system is unrecognized and not supported by Fink.");
  exit 1;
}

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
  $cmd = "$homebase/bootstrap.pl .$answer";
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

@dirlist = qw(etc src fink fink/dists fink/dists/stable fink/dists/local);
foreach $dir (qw(stable/bootstrap stable/main stable/crypto local/main)) {
  push @dirlist, "fink/dists/$dir", "fink/dists/$dir/finkinfo",
    "fink/dists/$dir/binary-darwin-powerpc";
}
foreach $dir (@dirlist) {
  if (not -d "$installto/$dir") {
    if (&execute("mkdir $installto/$dir")) {
      print "ERROR: Can't create directory '$installto/$dir'.\n";
      exit 1;
    }
  }
}

### copy package info needed for bootstrap

print "Copying package descriptions...\n";

$script = "cp packages/*.info packages/*.patch $installto/fink/dists/stable/bootstrap/finkinfo/\n";

if (-f "packages/base-files.in") {
  $script .= "rm -f $installto/fink/dists/stable/bootstrap/finkinfo/base-files*\n";
  $script .= "sed -e 's/\@VERSION\@/$packageversion/' -e 's/\@REVISION\@/$packagerevision/' <packages/base-files.in >$installto/fink/dists/stable/bootstrap/finkinfo/base-files-$packageversion.info\n";
}
if (-f "packages/fink.in") {
  $script .= "rm -f $installto/fink/dists/stable/bootstrap/finkinfo/fink*\n";
  $script .= "sed -e 's/\@VERSION\@/$packageversion/' -e 's/\@REVISION\@/$packagerevision/' <packages/fink.in >$installto/fink/dists/stable/bootstrap/finkinfo/fink-$packageversion.info\n";
}

foreach $cmd (split(/\n/,$script)) {
  next unless $cmd;   # skip empty lines

  if (&execute($cmd)) {
    print "ERROR: Can't copy package descriptions.\n";
    exit 1;
  }
}

### create tarballs for bootstrap

print "Creating tarballs...\n";

$script = "";
if (-f "perlmod/Fink/FinkVersion.pm.in") {
  $script .=
    "sed -e 's/\@VERSION\@/$packageversion/' ".
    "<perlmod/Fink/FinkVersion.pm.in ".
    ">perlmod/Fink/FinkVersion.pm\n";
}
$script .=
  "tar -cf $installto/src/fink-$packageversion.tar ".
  "COPYING INSTALL README ChangeLog fink install.sh setup.sh ".
  "perlmod update mirror\n";
$script .=
  "cd base-files && ".
  "tar -cf $installto/src/base-files-$packageversion.tar ".
  "fink-release init.csh.in init.sh.in install.sh setup.sh\n";

foreach $cmd (split(/\n/,$script)) {
  next unless $cmd;   # skip empty lines

  if (&execute($cmd)) {
    print "ERROR: Can't create tarballs.\n";
    exit 1;
  }
}

### setup initial configuration

print "Creating initial configuration...\n";
my ($configpath, $config, $engine);

$configpath = "$installto/etc/fink.conf";
open(CONFIG, ">$configpath") or die "can't create configuration: $!";
print CONFIG <<"EOF";
# Fink configuration, initially created by bootstrap.pl
Basepath: $installto
RootMethod: $rootmethod
Trees: local/main stable/main stable/crypto stable/bootstrap
EOF
close(CONFIG) or die "can't write configuration: $!";

$config = &read_config($configpath);
$libpath = $homebase;   # fink is not yet installed...
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

chdir $homebase;
if (-d "pkginfo") {
  if (&execute("cd pkginfo && ./inject.pl $installto")) {
    # inject failed
    print "\n";
    &print_breaking("Copying the package description tree failed. This ".
		    "is no big harm; your Fink installation should work ".
		    "nonetheless. Use '$installto/bin/init.csh' to set up ".
                    "your environment to use it. You still need package ".
                    "descriptions if you want to compile packages yourself. ".
                    "You can get them from CVS or by installing the ".
                    "packages$showversion.tar.gz tarball. Enjoy.");
  } else {
    # inject worked
    print "\n";
    &print_breaking("You should now have a working Fink installation in ".
		    "'$installto'. Use '$installto/bin/init.csh' to set up ".
		    "your environment to use it. Enjoy.");
  }
} else {
  # this was not the 'full' tarball
  print "\n";
  &print_breaking("You should now have a working Fink installation in ".
		  "'$installto'. Use '$installto/bin/init.csh' to set up ".
		  "your environment to use it. You still need package ".
		  "descriptions if you want to compile packages yourself. ".
		  "You can get them from CVS or by installing the ".
		  "packages$showversion.tar.gz tarball. Enjoy.");
}

print "\n";

### eof
exit 0;
