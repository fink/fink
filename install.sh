#!/bin/sh -e
#
# install.sh - install fink package
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

for dir in bin lib lib/fink lib/perl5 lib/perl5/Fink \
	   lib/fink/mirror lib/fink/update \
	   share share/doc share/doc/fink share/man share/man/man8 ; do
  mkdir $basepath/$dir
  chmod 755 $basepath/$dir
done


echo "Copying files..."

cp fink $basepath/bin/
chmod 755 $basepath/bin/fink

cp fink.8 $basepath/share/man/man8/
chmod 644 $basepath/share/man/man8/fink.8

for file in perlmod/Fink/*.pm ; do
  if [ -f $file ]; then
    cp $file $basepath/lib/perl5/Fink/
    chmod 644 $basepath/lib/perl5/Fink/`basename $file`
  fi
done

for file in mirror/* ; do
  if [ -f $file ]; then
    cp $file $basepath/lib/fink/mirror/
    chmod 644 $basepath/lib/fink/$file
  fi
done

for file in update/config.guess update/config.sub update/ltconfig ; do
  cp $file $basepath/lib/fink/update/
  chmod 755 $basepath/lib/fink/$file
done

for file in update/ltmain.sh update/Makefile.in.in ; do
  cp $file $basepath/lib/fink/update/
  chmod 644 $basepath/lib/fink/$file
done

for file in COPYING README README.html INSTALL INSTALL.html \
            USAGE USAGE.html ; do
  cp $file $basepath/share/doc/fink/
  chmod 644 $basepath/share/doc/fink/$file
done


echo "Done."
exit 0
