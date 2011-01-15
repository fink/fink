#!/bin/sh
#
# dpkg-checkall.sh -- A script to check if everything which dpkg thinks
#                     is installed, is actually installed.  Outputs a
#                     list of packages with problems.
#
#                     Script written by Alexander Strange, enhanced by Martin Costabel.
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
fink_path=`which dpkg | sed -e 's:/bin/dpkg::'`
NONE=1
echo "Checking for missing files (Package - Missing files):"
echo " "
for FILELIST in $fink_path/var/lib/dpkg/info/*.list
do
  PACKAGE=`basename $FILELIST .list`
# trick to allow for spaces in file names: remove them from IFS 
IFS="
"
for FILE in `cat $FILELIST`
  do
    if ! test -e "$FILE" 
    then
        NONE=0
        echo $PACKAGE "-" $FILE
    fi
  done
done
[ $NONE -gt 0 ] &&  echo "No files missing. Congratulations!"

