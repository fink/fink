#!/usr/bin/perl -w
#
# inject.pl - perl script to install a CVS version of one of the
#             fink packages into an existing Fink tree
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
use 5.006;  # perl 5.6.0 or newer required
use strict;

use FindBin;
use lib "$FindBin::RealBin/perlmod";

### which package are we injecting?

my $package = "fink";

### check if we're unharmed, and specify files for tarball

use Fink::Bootstrap qw(&check_files);

my $res = check_files();
if ($res == 1 ) {
	exit 1;
}

my $packagefiles = &fink_packagefiles();

my $info_script = "";

### below this, the code should be the same no matter which package we're
### injecting

### load some modules

require Fink::Services;
import Fink::Services qw(&print_breaking &read_config &execute &file_MD5_checksum);
#import Fink::Services qw(&read_config &execute);
require Fink::Config;

my $param = shift;

my $result = &inject_package($package, $packagefiles, $info_script, $param);
if ($result == 1) {
    exit 1;
}

### eof
exit 0;

sub inject_package {

my $package = shift;
my $packagefiles = shift;
my $info_script = shift;

### locate Fink installation

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
  $result = 1;
  return $result;
}

### get version

my ($packageversion, $packagerevision) = &get_packageversion();

### load configuration

my $config = &read_config("$bpath/etc/fink.conf",
                          { Basepath => $bpath });

### parse config file for root method

# TODO: use setting from config
# for now, we just use sudo...

if ($> != 0) {
  exit &execute("sudo ./inject.pl $bpath");
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

### create tarball for the package

$result = &create_tarball($bpath, $package, $packageversion, $packagefiles);
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

sub get_packageversion {

    my ($packageversion, $packagerevision);

    chomp($packageversion = `cat VERSION`);
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

sub bootstrap_Trees {

    my $bpath = shift;

### load configuration

my $config = &read_config("$bpath/etc/fink.conf");

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

}

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
  "tar -cf $bpath/src/$package-$packageversion.tar ".
    "$packagefiles\n";

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

sub copy_description {

my $script = shift;
my $bpath = shift;
my $package = shift;
my $packageversion = shift;
my $packagerevision = shift;

my ($cmd);

print "Copying package description(s)...\n";

if (not -d "$bpath/fink/debs") {
  $script .= "mkdir -p $bpath/fink/debs\n";
}
if (not -d "$bpath/fink/dists/local/bootstrap/finkinfo") {
  $script .= "mkdir -p $bpath/fink/dists/local/bootstrap/finkinfo\n";
}
my $md5 = &file_MD5_checksum("$bpath/src/$package-$packageversion.tar");
$script .= "/usr/bin/sed -e 's/\@VERSION\@/$packageversion/' -e 's/\@REVISION\@/$packagerevision/' -e 's/\@MD5\@/$md5/' <$package.info.in >$bpath/fink/dists/local/bootstrap/finkinfo/$package-$packageversion.info\n";
$script .= "/bin/chmod 644 $bpath/fink/dists/local/bootstrap/finkinfo/*.*\n";

my $result = 0;

foreach $cmd (split(/\n/,$script)) {
  next unless $cmd;   # skip empty lines

  if (&execute($cmd)) {
    print "ERROR: Can't copy package description(s).\n";
    $result = 1;
  }
}
return $result;
}


sub install_package {

my $bpath = shift;
my $package = shift;

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

}

sub fink_packagefiles {

my $packagefiles = "COPYING INSTALL INSTALL.html README README.html USAGE USAGE.html Makefile ".
  "ChangeLog VERSION fink.in fink.8.in fink.conf.5.in install.sh setup.sh ".
  "shlibs.default.in pathsetup.command.in postinstall.pl.in perlmod update t ".
  "fink-virtual-pkgs.in mirror";

return $packagefiles;

}

