#!/bin/sh -e
#
# install.sh - the Fink installation shells script
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
  echo "Usage: ./install.sh <directory>"
  echo "  Example: ./install.sh /sw"
  exit 1
fi

basepath=$1

if [ ! -d $basepath ]; then
  echo "Creating directories..."
  mkdir -p $basepath
else
  if [ -d $basepath/fink ]; then
    echo "The directory $basepath already exists and seems to"
    echo "contain a Fink installation. This script will not touch this. Use upgrade.sh"
    echo "instead to upgrade an existing Fink installation."
    exit 1
  fi
  if [ -d $basepath/bin -o -d $basepath/lib -o -d $basepath/include ]; then
    echo "The directory $basepath already exists and seems to"
    echo "contain software. This script will not attempt to install Fink into an"
    echo "existing hierarchy. Either remove the software in $basepath"
    echo "or choose another directory."
    exit 1
  fi
  echo "Creating directories..."
fi

mkdir -p $basepath/fink
mkdir -p $basepath/stow/system/bin
mkdir -p $basepath/stow/local
mkdir -p $basepath/var
mkdir -p $basepath/src

echo "Copying files..."
cp -R COPYING README fink info mirror patch perlmod update $basepath/fink
( cd $basepath/stow/system/bin; ln -s ../../../fink/fink fink )

echo "Creating init scripts..."
sed "s|BASEPATH|$basepath|g" <init.sh.in >$basepath/stow/system/bin/init.sh
sed "s|BASEPATH|$basepath|g" <init.csh.in >$basepath/stow/system/bin/init.csh

echo "Setting up stow hierarchy..."
( cd $basepath; ln -s stow/system/bin bin )
touch $basepath/var/.placeholder

echo "Writing preliminary configuration file..."
echo "# Fink configuration, initially created by install.sh" >$basepath/fink/config
echo "Basepath: $basepath" >>$basepath/fink/config
echo "# end of install.sh generated settings" >>$basepath/fink/config

echo ""
echo "I will now run 'fink bootstrap' to complete setup. Fink will interactively"
echo "create a configuration and install essential packages."
echo ""

$basepath/bin/fink bootstrap

exit 0
