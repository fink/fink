#!/usr/bin/perl -w
#
# inject.pl - perl script to install a CVS version of one of the
#             fink packages into an existing Fink tree
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2012 The Fink Package Manager Team
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
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110, USA.
#

$| = 1;
use 5.008_001;  # perl 5.8.1 or newer required
use strict;

use FindBin;
use lib "$FindBin::RealBin/perlmod";
use File::Copy;

require Fink::Services;
import Fink::Services qw(&execute);

### quit immediately if pod2man isn't executable, to avoid folks nearly building
### fink and then having it crap out.

# we appear always to be using /usr/bin/pod2man, so just test for that
{
	my $death_script = "\n/usr/bin/pod2man is either not executable (the most common case)\n"
					.  "or not present.\n"
					.  "If it is present but not executable, then open Disk Utility and run\n"
					.  "'Repair Disk Permissions' on your system hard drive.\n"
					.  "If that doesn't work, then run\n\n"
					.  "\tsudo chmod a+x /usr/bin/pod2man\n\n"
					.  "to make it executable.\n"
					.  "If it is absent, then you'll need to get a new copy, e.g. by\n"
					.  "reinstalling the BSD package from your OS X media, or by copying\n"
					.  "it from another machine running the same OS X version.\n\n";
	die $death_script unless -x "/usr/bin/pod2man";
}

### use sudo

if ($> != 0) {
    print "This script must be run under sudo, which requires your password.\n";
    my $cmd = "/usr/bin/sudo $FindBin::RealBin/$0";
    if ($#ARGV >= 0) {
	$cmd .= " '".join("' '", @ARGV)."'";
    }
    exit &execute($cmd,quiet=>1);
}

### create FinkVersion.pm from FinkVersion.pm.in (we don't care about the
### @ARCHITECTURE@ and @VERSION@ strings, because this copy of Fink is just
### here for the purpose of running the inject_packages() script, which
### doesn't need that information)

my $output = "$FindBin::RealBin/perlmod/Fink/FinkVersion.pm";
my $input = $output . '.in';

copy("$input", "$output") or die "Copy failed: $!";

require Fink::Bootstrap;

### which package are we injecting?

my $package = "fink";

### check if we're unharmed, and specify files for tarball

import Fink::Bootstrap qw(&check_files &fink_packagefiles);

my $res = check_files();
if ($res == 1 ) {
	exit 1;
}

my $packagefiles = fink_packagefiles();

my $info_script = "";

### run the inject_package script

import Fink::Bootstrap qw(&inject_package);

my $param = shift;

my $result = inject_package($package, $packagefiles, $info_script, $param);
if ($result == 1) {
    exit 1;
}

### eof
exit 0;



