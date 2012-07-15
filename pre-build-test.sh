#!/bin/sh -e
#
# setup.sh - configure fink package
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2012 The Fink Package Manager Team
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

# Tests for system-provided items which have historically caused problems.

# Presence/excecutability of pod2man
if [ ! -x /usr/bin/pod2man ] ; then
	printf "\n/usr/bin/pod2man is either not executable (the most common case)\n"
	printf "or not present.\n"
	printf "If it is present but not executable, then open Disk Utility and run\n"
	printf "'Repair Disk Permissions' on your system hard drive.\n"
	printf "If that doesn't work, then run\n\n"
	printf "\tsudo chmod a+x /usr/bin/pod2man\n\n"
	printf "to make it executable.\n"
	printf "If it is absent, then you'll need to get a new copy, e.g. by\n"
	printf "reinstalling the BSD package from your OS X media, or by copying\n"
	printf "it from another machine running the same OS X version.\n\n"
	exit 1
fi

exit 0
