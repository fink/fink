#!/bin/sh
#
# dpkg-checkall.sh -- A script to check if everything which dpkg thinks
#                     is installed, is actually installed.  Outputs a
#                     list of packages with problems.
#
#                     Script written by Alexander Strange.
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

fink_path=`which dpkg | sed -e 's:/bin/dpkg::'`
for foo in `cat $fink_path/var/lib/dpkg/info/*.list`
do
if (! test -e "$foo")
then
if (! test -L "$foo")
then
echo $foo not found
echo $foo is part of `dpkg -S $foo | awk '{print $1}' | sed -e 's;:;;g' | sort | uniq`
fi
fi
done
