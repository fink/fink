#
# Fink::Bootstrap module
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

package Fink::Bootstrap;

use Fink::Config qw($config $basepath);
use Fink::Services qw(&print_breaking &execute);
use Fink::PkgVersion;
use Fink::Engine;

use strict;
use warnings;

BEGIN {
  use Exporter ();
  our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
  $VERSION = 1.00;
  @ISA         = qw(Exporter);
  @EXPORT      = qw();
  @EXPORT_OK   = qw(&bootstrap);
  %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

END { }       # module clean-up code here (global destructor)


### bootstrap a base system

sub bootstrap {
  my ($bsbase, $save_path);
  my ($pkgname, $package);
  my @plist = ("gettext", "tar", "dpkg");

  $bsbase = "$basepath/bootstrap";
  &print_breaking("Bootstrapping a base system via $bsbase.");

  # create directories
  if (-d $bsbase) {
    &execute("rm -rf $bsbase");
  }
  &execute("mkdir -p $bsbase");
  &execute("mkdir -p $bsbase/bin");
  &execute("mkdir -p $bsbase/sbin");
  &execute("mkdir -p $bsbase/lib");
  &execute("mkdir -p $bsbase/var/lib/dpkg");

  # set paths so that everything is found
  $save_path = $ENV{PATH};
  $ENV{PATH} = "$basepath/sbin:$basepath/bin:".
               "$bsbase/sbin:$bsbase/bin:".
               $save_path;


  print "\n";
  &print_breaking("BOOTSTRAP PHASE ONE: installing neccessary packages to ".
		  "$bsbase without package management.");
  print "\n";

  foreach $pkgname (@plist) {
    $package = Fink::PkgVersion->match_package($pkgname);
    unless (defined $package) {
      die "no package found for specification '$pkgname'!\n";
    }

    $package->enable_bootstrap($bsbase);
    $package->phase_unpack();
    $package->phase_patch();
    $package->phase_compile();
    $package->phase_install();
    $package->disable_bootstrap();
  }


  print "\n";
  &print_breaking("BOOTSTRAP PHASE TWO: installing essential packages to ".
		  "$basepath with package management.");
  print "\n";

  Fink::Engine::cmd_install(@plist);


  #&execute("rm -rf $bsbase");
  $ENV{PATH} = $save_path;
}


### EOF
1;
