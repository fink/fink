#!/bin/sh -e
#
# setup.sh - configure fink package
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

if [ $# -ne 1 ]; then
  echo "Usage: ./setup.sh <prefix>"
  echo "  Example: ./setup.sh /sw"
  exit 1
fi

basepath=$1
version=`cat VERSION`

echo "Creating fink..."
sed "s|@BASEPATH@|$basepath|g" <fink.in >fink

echo "Creating FinkVersion.pm..."
sed -e "s|@VERSION@|$version|g" -e "s|@BASEPATH@|$basepath|g" <perlmod/Fink/FinkVersion.pm.in >perlmod/Fink/FinkVersion.pm

echo "Creating man page..."
sed "s|@VERSION@|$version|g ; s|@PREFIX@|$basepath|g" <fink.8.in >fink.8

exit 0
