#!/bin/sh -e
#
# pre-build-test.sh - check for missing system-provided items 
# 					  necessary to build fink.
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2015 The Fink Package Manager Team
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

# Presence of pod2man
if [ ! -e /usr/bin/pod2man ] ; then
	printf "\n/usr/bin/pod2man is not present.\n"
	printf "You will need to get a new copy, for example by\n"
	printf "reinstalling the BSD package from your OS X media, or by copying\n"
	printf "it from another machine running the same OS X version.\n\n"
	exit 1
elif [ ! -x /usr/bin/pod2man ] ; then
	# test whether it's a perl script
	pmtest=`file -L /usr/bin/pod2man | grep perl`
	# if so, and it's executable, give option to make it so
	if [ "x$pmtest" != "x" ] ; then
		printf "\n/usr/bin/pod2man is not executable.\n"
		printf "\nI can reset the permissions for you to\n"
		read -p "make it so.  Proceed (y/n)?"
		if [ "$REPLY" == "y" ] ; then 
			printf "Attempting to make /usr/bin/pod2man executable..."
			# make sure it's executable
			if [ -z "`chmod a+x /usr/bin/pod2man 2>&1`" ] ; then
				printf "SUCCESS\n"
				printf "\n/usr/bin/pod2man is now executable.\n"
				printf "After installing fink, open Disk Utility and run\n"
				printf "'Repair Disk Permissions' on your system hard drive\n"
				printf "in case there are other permissions problems.\n"
				sleep 5
				exit 0
			else 
				printf "FAILED\n"
				printf "\nI couldn't change the permissions of /usr/bin/pod2man\n"
				printf "for some reason.  You will need to change them\n"
				printf "yourself.  Open Disk Utility and run\n"
				printf "'Repair Disk Permissions' on your system hard drive.\n"
				printf "If that doesn't work, then run\n\n"
				printf  "\tsudo chmod a+x /usr/bin/pod2man\n\n"
				printf "to make it executable.\n"
				exit 1
			fi
		else
				printf "\nYou will need to change the permissions of\n"
				printf "/usr/bin/pod2man before you can install fink.\n"
				printf "Open Disk Utility and run\n"
				printf "'Repair Disk Permissions' on your system hard drive.\n"
				printf "If that doesn't work, then run\n\n"
				printf  "\tsudo chmod a+x /usr/bin/pod2man\n\n"
				printf "to make it executable.\n"
				exit 1	
		fi
	else
		#/usr/bin/pod2man isn't a perl script (probably)
		printf "\nYour /usr/bin/pod2man appears not to be\n"
		printf "an executable perl script.  You will\n"
		printf "need to install a new copy, for example by\n"
		printf "reinstalling BSD.pkg from your OS X media, or\n"
		printf "getting a copy from another machine.\n"
	fi   
	exit 1
fi
# exists and is currently executable
exit 0
