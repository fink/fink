#!/usr/bin/perl -w
#
# inject.pl - perl script to install a CVS version of fink into
#             an existing Fink tree
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

my ($basepath, $packageversion, $packagerevision);
my ($script, $cmd);

### check if we're unharmed

my ($file);
foreach $file (qw(fink.in install.sh COPYING VERSION
                  perlmod/Fink mirror update fink.info.in postinstall.pl.in
                  update/config.guess perlmod/Fink/Config.pm mirror/_keys
                 )) {
  if (not -e $file) {
    print "ERROR: Package incomplete, '$file' is missing.\n";
    exit 1;
  }
}

### load some modules

unshift @INC, "$FindBin::RealBin/perlmod";

require Fink::Services;
import Fink::Services qw(&print_breaking &read_config &execute);
require Fink::Config;

### locate Fink installation

my ($guessed, $param, $path);

$guessed = "";
$param = shift;
if (defined $param) {
  $basepath = $param;
} else {
  $basepath = undef;
  if (exists $ENV{PATH}) {
    foreach $path (split(/:/, $ENV{PATH})) {
      if (substr($path,-1) eq "/") {
	$path = substr($path,0,-1);
      }
      if (-f "$path/init.sh" and -f "$path/fink") {
	$path =~ /^(.+)\/[^\/]+$/;
	$basepath = $1;
	last;
      }
    }
  }
  if (not defined $basepath or $basepath eq "") {
    $basepath = "/sw";
  }
  $guessed = " (guessed)";
}
unless (-f "$basepath/bin/fink" and
	-f "$basepath/bin/init.sh" and
	-f "$basepath/etc/fink.conf" and
	-d "$basepath/fink/dists") {
  &print_breaking("The directory '$basepath'$guessed does not contain a ".
		  "Fink installation. Please provide the correct path ".
		  "as a parameter to this script.");
  exit 1;
}

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

### load configuration

my $config = &read_config("$basepath/etc/fink.conf");

### parse config file for root method

# TODO: use setting from config
# for now, we just use sudo...

if ($> != 0) {
  exit &execute("sudo ./inject.pl $basepath");
}
umask oct("022");

### check that local/bootstrap is in the Trees list

my $trees = $config->param("Trees");
if ($trees =~ /^\s*$/) {
  print "Adding a Trees line to fink.conf...\n";
  $config->set_param("Trees", "local/main stable/main stable/crypto local/bootstrap");
  $config->save();
} else {
  if (grep({$_ eq "local/bootstrap"} split(/\s+/, $trees)) < 1) {
    print "Adding local/bootstrap to the Trees line in fink.conf...\n";
    $config->set_param("Trees", "$trees local/bootstrap");
    $config->save();
  }
}

### create and copy description file

print "Copying package description...\n";

$script = "";
if (not -d "$basepath/fink/debs") {
  $script .= "mkdir -p $basepath/fink/debs\n";
}
if (not -d "$basepath/fink/dists/local/bootstrap/finkinfo") {
  $script .= "mkdir -p $basepath/fink/dists/local/bootstrap/finkinfo\n";
}

$script .= "sed -e 's/\@VERSION\@/$packageversion/' -e 's/\@REVISION\@/$packagerevision/' <fink.info.in >$basepath/fink/dists/local/bootstrap/finkinfo/fink-$packageversion.info\n";

foreach $cmd (split(/\n/,$script)) {
  next unless $cmd;   # skip empty lines

  if (&execute($cmd)) {
    print "ERROR: Can't copy package description.\n";
    exit 1;
  }
}

### create tarball for the package

print "Creating tarball...\n";

$script = "";
if (not -d "$basepath/src") {
  $script .= "mkdir -p $basepath/src\n";
}

$script .=
  "tar -cf $basepath/src/fink-$packageversion.tar ".
  "COPYING INSTALL INSTALL.html README README.html USAGE USAGE.html ".
  "ChangeLog VERSION fink.in fink.8.in install.sh setup.sh ".
  "shlibs.default.in postinstall.pl.in perlmod update mirror\n";

foreach $cmd (split(/\n/,$script)) {
  next unless $cmd;   # skip empty lines

  if (&execute($cmd)) {
    print "ERROR: Can't create tarball.\n";
    exit 1;
  }
}

### install the package

print "Installing package...\n";
print "\n";

if (&execute("$basepath/bin/fink install fink")) {
  print "\n";
  &print_breaking("Installing the new fink package failed. ".
		  "The description and the tarball were installed, though. ".
		  "You can retry at a later time by issuing the ".
		  "appropriate fink commands.");
} else {
  print "\n";
  &print_breaking("Your Fink installation in '$basepath' was updated with ".
		  "a new fink package.");
}
print "\n";

### eof
exit 0;
