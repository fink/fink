#
# Fink::SelfUpdate class
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

package Fink::SelfUpdate;

use Fink::Services qw(&execute &version_cmp &print_breaking);
use Fink::Config qw($config $basepath);
use Fink::NetAccess qw(&fetch_url);
use Fink::Engine;
use Fink::Package;
use Fink::FinkVersion qw(&distribution_version);

use strict;
use warnings;

BEGIN {
  use Exporter ();
  our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
  $VERSION = 1.00;
  @ISA         = qw(Exporter);
  @EXPORT      = qw();
  @EXPORT_OK   = qw();  # eg: qw($Var1 %Hashit &func3);
  %EXPORT_TAGS = ( );   # eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

END { }       # module clean-up code here (global destructor)


### check for new Fink release

sub check {
  my ($destdir, $dir);
  my ($latest_fink, $installed_version, $pkgtarball, $url);
  my ($verbosity, $unpack_cmd);

  $destdir = "$basepath/src";
  chdir $destdir;

  # get the file with the latest number
  if (&fetch_url("http://fink.sourceforge.net/LATEST-FINK", $destdir)) {
    die "Can't get latest version info\n";
  }

  # check if we need to upgrade
  $latest_fink = `cat LATEST-FINK`;
  chomp($latest_fink);
  $installed_version = &distribution_version();
  if (&version_cmp($latest_fink, $installed_version) <= 0) {
    print "\n";
    &print_breaking("You already have the latest Fink release. ".
		    "(installed:$installed_version available:$latest_fink)");
    return;
  }

  print "\n";
  &print_breaking("A new Fink distribution release is available. ".
		  "I will now download the package descriptions for ".
		  "Fink $latest_fink and update the core packages. ".
		  "After that, you should update the other packages ".
		  "using commands like 'fink update-all'.");
  print "\n";

  # go ahead and upgrade
  # first, download the packages tarball
  $dir = "packages-$latest_fink";
  $pkgtarball = "$dir.tar.gz";
  $url = "http://prdownloads.sourceforge.net/fink/$pkgtarball";

  if (not -f $pkgtarball) {
    if (&fetch_url($url, $destdir)) {
      die "Downloading the update tarball '$pkgtarball' from the URL '$url' failed.\n";
    }
  }

  # unpack it
  if (-e $dir) {
    if (&execute("rm -rf $dir")) {
      die "can't remove existing directory $dir\n";
    }
  }

  $verbosity = "";
  if ($config->param_boolean("Verbose")) {
    $verbosity = "v";
  }
  $unpack_cmd = "gzip -dc $pkgtarball | tar -x${verbosity}f -";
  if (&execute($unpack_cmd)) {
    die "unpacking $pkgtarball failed\n";
  }

  # inject it
  chdir $dir;
  if (&execute("./inject.pl $basepath")) {
    die "injecting the new package definitions from $pkgtarball failed\n";
  }
  chdir $destdir;
  if (-e $dir) {
    &execute("rm -rf $dir");
  }

  # re-read package info
  Fink::Package->forget_packages();
  Fink::Package->require_packages();

  # update the package manager itself first
  Fink::Engine::cmd_install("fink");

  # re-execute ourselves before we update the rest
  print "Re-executing fink to use the new version...";
  exec "$basepath/bin/fink selfupdate-finish";

  # the exec doesn't return, but just in case...
  die "re-executing fink failed, run 'fink selfupdate-finish' manually";
}

### finish self-update (after upgrading fink itself and re-exec)

sub finish {
  my (@elist);

  # determine essential packages
  @elist = Fink::Package->list_essential_packages();
  # add some non-essential but important ones
  push @elist, qw(apt);  # maybe add libxpg4 in the future

  # update them
  Fink::Engine::cmd_install(@elist);  

  # tell the user what has happened
  print "\n";
  &print_breaking("The core packages have been updated. ".
		  "You should now update the other packages ".
		  "using commands like 'fink update-all'.");
  print "\n";
}


### EOF
1;
