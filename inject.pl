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

my ($basepath, $packageversion, $packagerevision);
my ($script, $cmd);

### check if we're unharmed

my ($file);
foreach $file (qw(fink install.sh COPYING VERSION
                  perlmod/Fink mirror update base-files packages
                  update/config.guess perlmod/Fink/Config.pm mirror/_keys
                 )) {
  if (not -e $file) {
    print "ERROR: Package incomplete, '$file' is missing.\n";
    exit 1;
  }
}

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

### parse config file for root method

# TODO: really parse the file, support both su and sudo
# for now, we just use sudo...

if ($> != 0) {
  exit &execute("sudo ./inject.pl $basepath");
}
umask oct("022");

### create and copy description files

print "Copying package descriptions...\n";

$script = "";
if (not -d "$basepath/fink/debs") {
  $script .= "mkdir -p $basepath/fink/debs\n";
}
if (not -d "$basepath/fink/dists/stable/bootstrap/finkinfo") {
  $script .= "mkdir -p $basepath/fink/dists/stable/bootstrap/finkinfo\n";
}

if (-f "packages/base-files.in") {
  $script .= "sed -e 's/\@VERSION\@/$packageversion/' -e 's/\@REVISION\@/$packagerevision/' <packages/base-files.in >$basepath/fink/dists/stable/bootstrap/finkinfo/base-files-$packageversion.info\n";
} else {
  $script .= "cp packages/base-files*.info $basepath/fink/dists/stable/bootstrap/finkinfo/\n";
}
if (-f "packages/fink.in") {
  $script .= "sed -e 's/\@VERSION\@/$packageversion/' -e 's/\@REVISION\@/$packagerevision/' <packages/fink.in >$basepath/fink/dists/stable/bootstrap/finkinfo/fink-$packageversion.info\n";
} else {
  $script .= "cp packages/fink*.info $basepath/fink/dists/stable/bootstrap/finkinfo/\n";
}

foreach $cmd (split(/\n/,$script)) {
  next unless $cmd;   # skip empty lines

  if (&execute($cmd)) {
    print "ERROR: Can't copy package descriptions.\n";
    exit 1;
  }
}

### create tarballs for the packages

print "Creating tarballs...\n";

$script = "";
if (not -d "$basepath/src") {
  $script .= "mkdir -p $basepath/src\n";
}

if (-f "perlmod/Fink/FinkVersion.pm.in") {
  $script .=
    "sed -e 's/\@VERSION\@/$packageversion/' ".
    "<perlmod/Fink/FinkVersion.pm.in ".
    ">perlmod/Fink/FinkVersion.pm\n";
}
$script .=
  "tar -cf $basepath/src/fink-$packageversion.tar ".
  "COPYING INSTALL README USAGE ChangeLog fink install.sh setup.sh ".
  "perlmod update mirror\n";
$script .=
  "cd base-files && ".
  "tar -cf $basepath/src/base-files-$packageversion.tar ".
  "fink-release init.csh.in init.sh.in dir-base install.sh setup.sh\n";

foreach $cmd (split(/\n/,$script)) {
  next unless $cmd;   # skip empty lines

  if (&execute($cmd)) {
    print "ERROR: Can't create tarballs.\n";
    exit 1;
  }
}

### install the packages

print "Installing packages...\n";
print "\n";

if (&execute("$basepath/bin/fink install fink base-files")) {
  print "\n";
  &print_breaking("Installing the new packages failed. The descriptions and ".
		  "tarballs were installed, though. You can retry at a ".
		  "later time by issuing the appropriate fink commands.");
} else {
  print "\n";
  &print_breaking("Your Fink installation in '$basepath' was updated with ".
		  "new fink packages.");
}
print "\n";

### helper functions

sub execute {
  my $cmd = shift;
  my $quiet = shift || 0;
  my ($retval, $prog);

  print "$cmd\n";
  $retval = system($cmd);
  $retval >>= 8 if defined $retval and $retval >= 256;
  if ($retval and not $quiet) {
    ($prog) = split(/\s+/, $cmd);
    print "### $prog failed, exit code $retval\n";
  }
  return $retval;
}

sub print_breaking {
  my $s = shift;
  my ($pos, $t);
  my $linelength = 77;

  chomp($s);
  while (length($s) > $linelength) {
    $pos = rindex($s," ",$linelength);
    if ($pos < 0) {
      $t = substr($s,0,$linelength);
      $s = substr($s,$linelength);
    } else {
      $t = substr($s,0,$pos);
      $s = substr($s,$pos+1);
    }
    print "$t\n";
  }
  print "$s\n";
}

### eof
exit 0;
