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
  echo "  Example: ./install.sh /tmp/builddirectory/sw"
  echo "WARNING: Don't call install.sh directly, use inject.pl instead."
  echo "         You have been warned."
  exit 1
fi

basepath="$1"


echo "Creating directories..."

mkdir -p "$basepath"
chmod 755 "$basepath"

for dir in bin lib lib/fink lib/perl5 lib/perl5/Fink \
	   lib/fink/mirror lib/fink/update \
	   share share/doc share/doc/fink share/man share/man/man8 ; do
  mkdir "$basepath/$dir"
  chmod 755 "$basepath/$dir"
done


echo "Copying files..."

install -c -p -m 755 postinstall.pl "$basepath/lib/fink/"
install -c -p -m 644 shlibs.default "$basepath/etc/dpkg/"
install -c -p -m 755 fink "$basepath/bin/"
install -c -p -m 644 fink.8 "$basepath/share/man/man8/"

for file in perlmod/Fink/*.pm ; do
  if [ -f $file ]; then
    install -c -p -m 644 $file "$basepath/lib/perl5/Fink/"
  fi
done

for file in mirror/* ; do
  if [ -f $file ]; then
    install -c -p -m 644 $file "$basepath/lib/fink/mirror/"
  fi
done

for file in update/config.guess update/config.sub update/ltconfig ; do
  install -c -p -m 755 $file "$basepath/lib/fink/update/"
done
for file in update/ltmain.sh update/Makefile.in.in ; do
  install -c -p -m 644 $file "$basepath/lib/fink/update/"
done

for file in COPYING README README.html INSTALL INSTALL.html \
            USAGE USAGE.html ; do
  install -c -p -m 644  $file "$basepath/share/doc/fink/"
done

install -c -p -m 644  ChangeLog "$basepath/share/doc/fink/ChangeLog"
install -c -p -m 644  mirror/ChangeLog "$basepath/share/doc/fink/ChangeLog.mirror"
install -c -p -m 644  perlmod/Fink/ChangeLog "$basepath/share/doc/fink/ChangeLog.perlmod"
install -c -p -m 644  update/ChangeLog "$basepath/share/doc/fink/ChangeLog.update"

echo "Done."
exit 0
