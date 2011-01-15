#!/bin/sh -e
# -*- mode: Shell; tab-width: 4; -*-
#
# install.sh - install fink package
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

if [ $# -ne 2 ]; then
  echo "Usage: ./install.sh <prefix> <architecture>"
  echo "  Example: ./install.sh /tmp/builddirectory/sw i386"
  echo "WARNING: Don't call install.sh directly, use inject.pl instead."
  echo "         You have been warned."
  exit 1
fi

basepath="$1"
architecture="$2"
version=`cat VERSION`

echo "Creating directories..."

mkdir -p "$basepath"
chmod 755 "$basepath"

for dir in bin sbin \
	lib lib/perl5 lib/perl5/Fink \
	lib/perl5/Fink/{Text,Notify,Checksum,Finally,SelfUpdate} \
	lib/fink lib/fink/update lib/fink/update-packages \
	etc etc/dpkg \
	share share/doc share/doc/fink \
	share/man share/man/man{3,5,8} \
	share/fink share/fink/images \
	var var/run var/run/fink var/run/fink/buildlock \
	var/lib var/lib/fink var/lib/fink/path-prefix-g++-{3.3,4.0} \
	var/lib/fink/path-prefix-10.6 ; do
  mkdir "$basepath/$dir"
  chmod 755 "$basepath/$dir"
done

if [ "$architecture" = "i386" ]; then
  mkdir "$basepath/etc/profile.d"
  chmod 755 "$basepath/etc/profile.d"
fi

echo "Copying files..."

if [ "$architecture" = "i386" ]; then
  install -c -p -m 755 fink.csh "$basepath/etc/profile.d"
  install -c -p -m 755 fink.sh "$basepath/etc/profile.d"
fi

install -c -p -m 755 postinstall.pl "$basepath/lib/fink/"
install -c -p -m 644 shlibs.default "$basepath/etc/dpkg/"
install -c -p -m 644 fink.8 "$basepath/share/man/man8/"
install -c -p -m 644 fink.conf.5 "$basepath/share/man/man5/"
install -c -p -m 644 images/*.png "$basepath/share/fink/images/"

# copy executables
for bin in fink fink-{virtual-pkgs,instscripts,scanpackages} pathsetup.sh \
		{dpkg,apt-get}-lockwait; do
	install -c -p -m 755 $bin "$basepath/bin/"
done
install -c -m 755 fink-dpkg-status-cleanup "$basepath/sbin/"

# copy all perl modules
for subdir in . Fink Fink/{Text,Notify,Checksum,Finally,SelfUpdate} ; do
  for file in perlmod/${subdir}/*.pm ; do
    if [ -f $file ]; then
      install -c -p -m 644 $file "$basepath/lib/perl5/$subdir"
    fi
  done
done

for file in update-packages/* ; do
  install -c -p -m 644 $file "$basepath/lib/fink/update-packages/"
done

for file in update/config.guess update/config.sub update/ltconfig ; do
  install -c -p -m 755 $file "$basepath/lib/fink/update/"
done
for file in update/ltmain.sh update/Makefile.in.in ; do
  install -c -p -m 644 $file "$basepath/lib/fink/update/"
done

for file in AUTHORS COPYING README README.html readme.*.html \
            INSTALL INSTALL.html STYLE TODO* USAGE USAGE.html ; do
  install -c -p -m 644  $file "$basepath/share/doc/fink/"
done

# some/place/ChangeLog goes as ChangeLoge.some.place
for cl_src in . perlmod perlmod/Fink update; do
  cl_dst=`echo $cl_src | tr '/' '.' | sed -e 's/^\.*//'`
  [ -n "$cl_dst" ] && cl_dst=".$cl_dst"
  install -c -p -m644 $cl_src/ChangeLog "$basepath/share/doc/fink/ChangeLog$cl_dst"
done

for gccvers in 3.3 4.0; do
	install -c -p -m 755 "g++-wrapper-$gccvers" \
		"$basepath/var/lib/fink/path-prefix-g++-$gccvers/g++"
	ln -s -n -f g++ "$basepath/var/lib/fink/path-prefix-g++-$gccvers/c++" 
done

for file in c++ c++-4.2 c++-4.0 cc gcc gcc-4.0 gcc-4.2 g++ g++-4.0 g++-4.2; do
    ln -s compiler_wrapper "$basepath/var/lib/fink/path-prefix-10.6/$file"
done
install -c -p -m 755 "compiler_wrapper" \
	    "$basepath/var/lib/fink/path-prefix-10.6/compiler_wrapper"

# Gotta do this in install.sh, takes too long for setup.sh
echo "Creating man pages from POD..."
function manify_bin () {
	echo "  $1.$2"
	pod2man --center "Fink documentation" --release "Fink $version" \
		--section $2 $1 "$basepath/share/man/man$2/$1.$2"
}
function manify_pm () {
	echo "  $1.3pm"
	pm=`echo $1 | perl -ne 'chomp; s,::,/,g; print "perlmod/$_.pm"'`
	pod2man --center "Fink documentation" --release "Fink $version" \
		--section 3 "$pm" "$basepath/share/man/man3/$1.3pm"
}
manify_bin fink-scanpackages 8
for p in \
		Fink				\
		Fink::Base			\
		Fink::Bootstrap		\
		Fink::Checksum		\
		Fink::CLI			\
		Fink::Command		\
		Fink::Config		\
		Fink::Configure		\
		Fink::Engine		\
		Fink::Finally		\
		Fink::Finally::BuildConflicts	\
		Fink::Finally::Buildlock		\
		Fink::FinkVersion	\
		Fink::Notify		\
		Fink::Package		\
		Fink::PkgVersion	\
		Fink::Scanpackages	\
		Fink::SelfUpdate	\
		Fink::SelfUpdate::Base	\
		Fink::SelfUpdate::CVS	\
		Fink::SelfUpdate::rsync	\
		Fink::SelfUpdate::point	\
		Fink::Services		\
		Fink::Shlibs		\
		Fink::SysState		\
		Fink::Text::DelimMatch			\
		Fink::Text::ParseWords			\
		Fink::VirtPackage	\
		; do
	manify_pm $p
done

echo "Done."
exit 0
