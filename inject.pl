#!/usr/bin/perl -w
#
# inject.pl - perl script to install a CVS version of one of the
#             fink packages into an existing Fink tree
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



# vim: ts=4 sw=4 noet
