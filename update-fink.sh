#!/bin/sh
#
# update-fink.sh -- A script to update Fink for Mac OS X, 10.2
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2002 The Fink Package Manager Team
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

# Remove two packages which will interfere with the update if they aren't
# at the latest versions
fink remove openldap-ssl cyrus-sasl

# Force-remove a disfunctional package which won't be used in 10.2
sudo dpkg -r --force-depends manconf

# Create Packages.gz and Release files for the last time in 10.1 directories
# before they are moved to another location (so that apt-get can find them
# even after the upgrade)
fink scanpackages

# Install the new version of fink, whose post-install script modifies the
# directory structure for 10.2
./inject.pl

# Finish the setup with fink selfupdate-cvs, fink scanpackages, and apt-get
# update

fink selfupdate-cvs
fink scanpackages
sudo apt-get update

exit 0


