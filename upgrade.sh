#!/bin/sh -e
#
# upgrade.sh - shells script that updates existing Fink installations
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

if [ $# -lt 1 ]; then
  echo "Usage: ./upgrade.sh <directory>"
  echo "  Example: ./upgrade.sh /sw"
  exit 1
fi

basepath=$1

if [ ! -d $basepath ]; then
  echo "The directory $basepath does not exist!"
  exit 1
fi
if [ ! -d $basepath/fink ]; then
  echo "The directory $basepath does not seem to contain a Fink installation."
  echo "Please check this."
  exit 1
fi

echo "Creating directories..."
mkdir -p $basepath/var/run
touch $basepath/var/run/.placeholder
if [ ! -d $basepath/etc ]; then
  mkdir $basepath/etc
  touch $basepath/etc/.placeholder
fi

echo "Copying files..."
cp -Rf COPYING README fink info mirror patch perlmod update $basepath/fink

echo "Creating init scripts..."
sed "s|BASEPATH|$basepath|g" <init.sh.in >$basepath/stow/system/bin/init.sh
sed "s|BASEPATH|$basepath|g" <init.csh.in >$basepath/stow/system/bin/init.csh

echo "Your Fink installation was updated with new files. Be sure to read the"
echo "upgrade notes in the README file."

exit 0
