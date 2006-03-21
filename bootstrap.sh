#!/bin/sh
#
# bootstrap.sh - shell script to start bootstrap.pl
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
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#

### welcome message

cat <<EOF

Welcome to Fink.

This script will install Fink into a directory of your choice,
setup a configuration file and conduct a bootstrap of the installation.

EOF

### check requirements for starting bootstrap.pl

if [ ! -x /usr/bin/perl ]; then
  echo "ERROR: /usr/bin/perl doesn't exist."
  exit 1
fi
if [ ! -f bootstrap.pl ]; then
  echo "ERROR: bootstrap.pl doesn't exist in the current directory."
  exit 1
fi
if [ ! -d perlmod/Fink ]; then
  echo "ERROR: perlmod/Fink doesn't exist in the current directory."
  exit 1
fi

### create FinkVersion.pm for bootstrap

if [ -f perlmod/Fink/FinkVersion.pm ]; then
  rm -f perlmod/Fink/FinkVersion.pm
fi
  version=`cat VERSION`
  sed -e "s|@VERSION@|$version|g" <perlmod/Fink/FinkVersion.pm.in >perlmod/Fink/FinkVersion.pm


### start bootstrap.pl

if [ ! -x bootstrap.pl ]; then
  /bin/chmod a+x bootstrap.pl
fi

exec ./bootstrap.pl "$@"
