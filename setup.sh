#!/bin/sh -e
#
# setup.sh - configure fink package
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2025 The Fink Package Manager Team
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

if [ $# -ne 2 ]; then
  echo "Usage: ./setup.sh <prefix> <architecture>"
  echo "  Example: ./setup.sh /opt/sw i386"
  exit 1
fi

basepath=$1
architecture=$2
version=`cat VERSION`

perlexe="/usr/bin/perl"

osMajorVer=`uname -r | cut -d. -f1`
osMinorVer=`uname -r | cut -d. -f2`

if [ $osMajorVer -eq 11 -o $osMajorVer -eq 12 ]; then
  perlexe="/usr/bin/arch -arch $architecture /usr/bin/perl5.12"
elif [ $osMajorVer -eq 13 ]; then
  perlexe="/usr/bin/arch -arch $architecture /usr/bin/perl5.16"
elif [ $osMajorVer -gt 13 -a $osMajorVer -le 19 ]; then
  perlexe="/usr/bin/arch -arch $architecture /usr/bin/perl5.18"
elif [ $osMajorVer -eq 20 -a $osMinorVer -le 3 ]; then
  perlexe="/usr/bin/arch -arch $architecture /usr/bin/perl5.28"
elif [ $osMajorVer -ge 20 -a $osMajorVer -le 22 ]; then
  perlexe="/usr/bin/arch -arch $architecture /usr/bin/perl5.30"
elif [ $osMajorVer -eq 23 -a $osMinorVer -le 3 ]; then
  perlexe="/usr/bin/arch -arch $architecture /usr/bin/perl5.30"
elif [ $osMajorVer -ge 23 -a $osMajorVer -le 25 ]; then
  perlexe="/usr/bin/arch -arch $architecture /usr/bin/perl5.34"
fi


echo "Creating $fink..." 
sed -e "s|@BASEPATH@|$basepath|g" -e "s|@PERLEXE@|$perlexe|g" < fink.in > fink

for bin in fink-{virtual-pkgs,instscripts,scanpackages}; do
	echo "Creating $bin..."
	sed -e "s|@BASEPATH@|$basepath|g" -e "s|@LIBPATH@|\$basepath/lib/perl5|g" < "$bin.in" > "$bin"
done

echo "Creating pathsetup.sh..."
sed "s|@PREFIX@|$basepath|g" <pathsetup.sh.in >pathsetup.sh

echo "Creating FinkVersion.pm..."
sed -e "s|@VERSION@|$version|g" -e "s|@ARCHITECTURE@|$architecture|g" <perlmod/Fink/FinkVersion.pm.in >perlmod/Fink/FinkVersion.pm

echo "Creating Fink.pm..."
sed -e "s|@BASEPATH@|$basepath|g" <perlmod/Fink.pm.in >perlmod/Fink.pm

echo "Creating man pages..."
sed "s|@PREFIX@|$basepath|g" <fink.8.in \
  | perl -MTime::Local -MPOSIX=strftime -p -e '$d="Date:";if (s/(\.Dd \$$d) (\d+)\/(\d+)\/(\d+) (\d+):(\d+):(\d+) \$/\1/) {$epochtime = timegm($7,$6,$5,$4,$3-1,$2-1900);$datestr = strftime "%B %e, %Y", localtime($epochtime); s/(\.Dd )\$$d/$1$datestr/;}' \
  >fink.8

sed "s|@PREFIX@|$basepath|g" <fink.conf.5.in \
  | perl -MTime::Local -MPOSIX=strftime -p -e '$d="Date:";if (s/(\.Dd \$$d) (\d+)\/(\d+)\/(\d+) (\d+):(\d+):(\d+) \$/\1/) {$epochtime = timegm($7,$6,$5,$4,$3-1,$2-1900);$datestr = strftime "%B %e, %Y", localtime($epochtime); s/(\.Dd )\$$d/$1$datestr/;}' \
  >fink.conf.5

sed "s|@PREFIX@|$basepath|g" <fink.sb.5.in \
  | perl -MTime::Local -MPOSIX=strftime -p -e '$d="Date:";if (s/(\.Dd \$$d) (\d+)\/(\d+)\/(\d+) (\d+):(\d+):(\d+) \$/\1/) {$epochtime = timegm($7,$6,$5,$4,$3-1,$2-1900);$datestr = strftime "%B %e, %Y", localtime($epochtime); s/(\.Dd )\$$d/$1$datestr/;}' \
  >fink.sb.5

echo "Creating shlibs default file..."
sed "s|@PREFIX@|$basepath|g" <shlibs.default.in >shlibs.default

echo "Creating postinstall script..."
sed "s|@PREFIX@|$basepath|g" <postinstall.pl.in >postinstall.pl

echo "Creating dpkg helper script..."
sed "s|@PREFIX@|$basepath|g" <fink-dpkg-status-cleanup.in >fink-dpkg-status-cleanup

# note: because they are used at different times during bootstrapping,
# it is important to NOT use the full path to the dpkg executable in
# dpkg-lockwait, but to GIVE the full path to the apt-get executable in
# apt-get-lockwait

# set arguments for pack() up in an architecture-appropriate manner
# These are appropriate for x86_64:
packargs='"qqiss", 0, 0'

echo "Creating lockwait wrappers..."
for prog in dpkg; do
	sed -e "s|@PREFIX@|$basepath|g" -e "s|@PROG@|$prog|g" -e "s|@PACKARGS@|$packargs|" <lockwait.in >$prog-lockwait
done
for prog in apt-get; do
	sed -e "s|@PREFIX@|$basepath|g" -e "s|@PROG@|$basepath/bin/$prog|g" -e "s|@PACKARGS@|$packargs|" <lockwait.in >$prog-lockwait
done

echo "Creating g++ wrappers..."
for gccvers in 3.3 4.0; do
	sed -e "s|@GCCVERS@|$gccvers|g" <g++-wrapper.in \
		>"g++-wrapper-$gccvers"
done

echo "Creating compiler wrapper"
sed -e "s|@ARCHITECTURE@|$architecture|g" -e "s|@PREFIX@|$basepath|g" < compiler_wrapper-10.6.in >"compiler_wrapper"
sed -e "s|@PREFIX@|$basepath|g" < compiler_wrapper-10.7.in >"compiler_wrapper-10.7"
sed -e "s|@PREFIX@|$basepeath|g" < compiler_wrapper-10.9.in >"compiler_wrapper-10.9"

exit 0
