#!/bin/sh -e
#
# install.sh - install fink base-files package
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
  echo "Usage: ./install.sh <prefix>"
  echo "  Example: ./install.sh /sw"
  exit 1
fi

basepath=$1


echo "Creating directories..."

mkdir -p $basepath
chmod 755 $basepath

for dir in etc etc/profile.d bin sbin lib include \
	   share share/info share/man share/doc \
	   info man \
	   share/base-files \
	   lib/perl5 lib/perl5/darwin lib/perl5/auto lib/perl5/darwin/auto \
	   var var/run var/spool src ; do
  mkdir $basepath/$dir
  chmod 755 $basepath/$dir
done


echo "Copying files..."

cp init.sh $basepath/bin/
chmod 644 $basepath/bin/init.sh
cp init.csh $basepath/bin/
chmod 644 $basepath/bin/init.csh
# generate a dummy file to avoid problems with zsh
touch $basepath/etc/profile.d/dummy.sh
chmod 644 $basepath/etc/profile.d/dummy.sh

cp fink-release $basepath/etc/
chmod 644 $basepath/etc/fink-release

cp dir-base $basepath/share/base-files/
chmod 644 $basepath/share/base-files/dir-base


echo "Done."
exit 0
