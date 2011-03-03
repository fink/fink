# -*- mode: Perl; tab-width: 4; -*-
# vim: ts=4 sw=4 noet
#
# bootstrap-phase2.pl - perl script to install and bootstrap a Fink
#                       installation from source
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2011 The Fink Package Manager Team
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
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110, USA.
#

use 5.008_001;	 # perl 5.8.1 or newer required
use strict;
use warnings;

$ENV{'PATH'} = "/usr/bin:/bin:/usr/sbin:/sbin:/usr/X11R6/bin";

use FindBin;
use lib "$FindBin::RealBin/perlmod";
use IO::Handle;

$| = 1;

my $homebase = $FindBin::RealBin;
chdir $homebase;

my $installto = shift;

require Fink::Config;
require Fink::Engine;
require Fink::Configure;
require Fink::Bootstrap;
require Fink::Services;
import Fink::Services qw(&read_config);

### bootstrap phase 2

my $configpath = "$installto/etc/fink.conf";
my $config = &read_config($configpath);
# override path to data files (update, mirror)
no warnings 'once';
$Fink::Config::libpath = $homebase;
use warnings 'once';
Fink::Engine->new_with_config($config);

Fink::Bootstrap::bootstrap2();

### eof
exit 0;
