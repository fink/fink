#!/bin/sh -e
#
# mkrelease.sh - shell script to prepare release tarballs
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

### configuration

cvsroot=':pserver:anonymous@cvs.sourceforge.net:/cvsroot/fink'

### init

if [ $# -lt 2 ]; then
  echo "Usage: $0 <temporary-directory> <version-number> [<tag>]"
  exit 1
fi

tmpdir=$1
version=$2
tag=$3
if [ -z "$tag" ]; then
  tag=release_`echo $version | sed 's/\./_/g'`
fi

echo "packaging release $version, CVS tag $tag"

### setup temp directory

mkdir -p $tmpdir
cd $tmpdir
umask 022

if [ -d fink -o -d packages -o -d "fink-$version" ]; then
  echo "There are left-over directories in $tmpdir."
  echo "Remove them, then try again."
  exit 1
fi

### check code out from CVS

echo "Exporting module fink, tag $tag from CVS:"
cvs -d "$cvsroot" export -r "$tag" fink
if [ ! -d fink ]; then
  echo "CVS export failed, directory fink doesn't exist!"
  exit 1
fi

echo "Exporting module packages, tag $tag from CVS:"
cvs -d "$cvsroot" export -r "$tag" packages
if [ ! -d packages ]; then
  echo "CVS export failed, directory packages doesn't exist!"
  exit 1
fi

### versioning

echo "$version" >fink/VERSION
echo "$version" >fink/base-files/fink-release

sed -e "s/@VERSION@/$version/" -e "s/@REVISION@/1/" \
  <fink/packages/base-files.in \
  >fink/packages/base-files-$version.info
rm -f fink/packages/base-files.in

sed -e "s/@VERSION@/$version/" -e "s/@REVISION@/1/" \
  <fink/packages/fink.in \
  >fink/packages/fink-$version.info
rm -f fink/packages/fink.in

sed -e "s/@VERSION@/$version/" \
  <perlmod/Fink/FinkVersion.pm.in \
  >perlmod/Fink/FinkVersion.pm
rm -f perlmod/Fink/FinkVersion.pm.in

### create package directories

# big package
cp -R fink "fink-$version-full"
cp -R packages "fink-$version-full/pkginfo"

# individual packages
cp -R fink/base-files "base-files-$version"
mv fink "fink-$version"
mv packages "packages-$version"

### roll tarballs

for dirname in "fink-$version-full" "fink-$version" \
    "packages-$version" "base-files-$version" ; do

  echo "Creating tarball $dirname.tar.gz:"
  rm -f $dirname.tar $dirname.tar.gz
  tar -cvf $dirname.tar $dirname
  gzip -9 $dirname.tar

  if [ ! -f $dirname.tar.gz ]; then
    echo "Packaging failed, $dirname.tar.gz doesn't exist!"
    exit 1
  fi
done

### finish up

echo "Done:"
ls -l *.tar.gz

exit 0
