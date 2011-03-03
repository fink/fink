#!/bin/sh -e
#
# install.sh - install fink-mirrors package
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
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110, USA.
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

for dir in lib lib/fink lib/fink/mirror lib/fink/URL share share/doc share/doc/fink-mirrors  share/doc/fink ; do
  mkdir "$basepath/$dir"
  chmod 755 "$basepath/$dir"
done


echo "Copying files..."

for file in ChangeLog _keys _list apache apt cpan ctan debian freebsd gimp gnome gnu kde master postgresql rsync sourceforge; do
  if [ -f $file ]; then
    install -c -p -m 644 $file "$basepath/lib/fink/mirror/"
  fi
done

for file in _urls anonymous-cvs cvs-repository developer-cvs website; do
  if [ -f $file ]; then
    install -c -p -m 644 $file "$basepath/lib/fink/URL/"
  fi
done

install -c -p -m 755 postinstall.pl "$basepath/lib/fink/mirror/"

for file in COPYING README README.contacts; do
  install -c -p -m 644  $file "$basepath/share/doc/fink-mirrors/"
done

install -c -p -m 644  ChangeLog "$basepath/share/doc/fink/ChangeLog.mirror"

echo "Done."
exit 0
