#
# Fink::SelfUpdate class
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

package Fink::SelfUpdate;

use Fink::Services qw(&execute &version_cmp &print_breaking
                      &prompt &prompt_boolean);
use Fink::Config qw($config $basepath);
use Fink::NetAccess qw(&fetch_url);
use Fink::Engine;
use Fink::Package;
use Fink::FinkVersion qw(&pkginfo_version);

use File::Find;

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
  my $usecvs = shift || 0;
  my ($srcdir, $finkdir, $latest_fink, $installed_version, $answer);

  $srcdir = "$basepath/src";
  $finkdir = "$basepath/fink";

  if (-d "$finkdir/CVS") {
    if ($usecvs) {
      $answer = 1;
    } else {
      print "\n";
      $answer =
	&prompt_boolean("Your Fink installation is set up to update package ".
			"descriptions directly from CVS. Do you want to ".
			"use this setup and update now?", 1);
    }
    if (not $answer) {
      return;
    }

    &do_direct_cvs();
    &do_finish();
    return;
  }

  $installed_version = &pkginfo_version();
  if ($installed_version eq "cvs" or -d "$finkdir/dists/CVS") {
    print "\n";
    $answer =
      &prompt_boolean("You have previously used CVS to update package ".
		      "descriptions, but your Fink installation is not ".
		      "set up for direct CVS updating (without inject.pl). ".
		      "Do you want to set up direct CVS updating now?", 1);
    if (not $answer) {
      return;
    }

    &setup_direct_cvs();
    &do_finish();
    return;
  }


  if ($usecvs or not $config->param_boolean("SelfUpdateNoCVS")) {
    print "\n";
    $answer =
      &prompt_boolean("The selfupdate function can track point releases ".
		      "or it can set up your Fink installation to update ".
		      "package descriptions from CVS. Updating from CVS ".
		      "has the advantage that it is more up to date than ".
		      "the last point release. On the other hand, ".
		      "the point release may be more mature or have ".
		      "less bugs. Nevertheless, CVS is recommended. ".
		      "Do you want to set up direct CVS updating?",
		      $usecvs);
    if (not $answer) {
      print "\n";
      &print_breaking("Okay, the selfupdate command will stick to point ".
		      "releases from now on. If you ever rethink your ".
		      "decision, run 'fink selfupdate-cvs' to be asked ".
		      "again.");
      print "\n";
    }
  } else {
    $answer = 0;
  }
  if ($answer) {
    &setup_direct_cvs();
    &do_finish();
    return;
  }

  # remember the choice
  $config->set_param("SelfUpdateNoCVS", "true");
  $config->save();

  # get the file with the current release number
  if (&fetch_url("http://fink.sourceforge.net/LATEST-FINK", $srcdir)) {
    die "Can't get latest version info\n";
  }

  # check if we need to upgrade
  $latest_fink = `cat $srcdir/LATEST-FINK`;
  chomp($latest_fink);
  if (&version_cmp($latest_fink, $installed_version) <= 0) {
    print "\n";
    &print_breaking("You already have the package descriptions from ".
		    "the latest Fink point release. ".
		    "(installed:$installed_version available:$latest_fink)");
    return;
  }

  &do_tarball($latest_fink);
  &do_finish();
}

### set up direct cvs

sub setup_direct_cvs {
  my ($finkdir, $tempdir, $tempfinkdir);
  my ($username, $cvsuser, @testlist);
  my ($use_hardlinks, $cutoff, $cmd);

  $username = "root";
  if (exists $ENV{SUDO_USER}) {
    $username = $ENV{SUDO_USER};
  }

  print "\n";
  $username =
    &prompt("Fink has the capability to run the CVS commands as a ".
	    "normal user. That has some advantages - it uses that ".
	    "user's CVS settings files and allows the package ".
	    "descriptions to be edited and updated without becoming ".
	    "root. Please specify the user login name that should be ".
	    "used:",
	    $username);

  # sanity check
  @testlist = getpwnam($username);
  if (scalar(@testlist) <= 0) {
    die "The user \"$username\" does not exist on the system.\n";
  }

  print "\n";
  $cvsuser =
    &prompt("For Fink developers only: ".
	    "Enter your SourceForge login name to set up full CVS access. ".
	    "Other users, just press return to set up anonymous ".
	    "read-only access.",
	    "anonymous");
  print "\n";

  # start by creating a temporary directory with the right permissions
  $finkdir = "$basepath/fink";
  $tempdir = "$finkdir.tmp";
  $tempfinkdir = "$tempdir/fink";

  if (-d $tempdir) {
    if (&execute("rm -rf $tempdir")) {
      die "Can't remove left-over temporary directory '$tempdir'\n";
    }
  }
  if (&execute("mkdir -p $tempdir")) {
    die "Can't create temporary directory '$tempdir'\n";
  }
  if ($username ne "root") {
    if (&execute("chown $username $tempdir")) {
      die "Can't set ownership of temporary directory '$tempdir'\n";
    }
  }

  # check if hardlinks from the old directory work
  &print_breaking("Checking to see if we can use hard links to merge ".
		  "the existing tree. Please ignore errors on the next ".
		  "few lines.");
  if (&execute("ln $finkdir/README $tempdir/README")) {
    $use_hardlinks = 0;
  } else {
    $use_hardlinks = 1;
  }
  unlink "$tempdir/README";

  # start the CVS fun
  chdir $tempdir or die "Can't cd to $tempdir: $!\n";
  if ($cvsuser eq "anonymous") {
    &print_breaking("Now logging into the CVS server. When CVS asks you ".
		    "for a password, just press return (i.e. the password ".
		    "is empty).");
    $cmd = "cvs -d:pserver:anonymous\@cvs.sourceforge.net:/cvsroot/fink login";
    if ($username ne "root") {
      $cmd = "su $username -c '$cmd'";
    }
    if (&execute($cmd)) {
      die "Logging into the CVS server for anonymous read-only access failed.\n";
    }

    $cmd = "cvs -z3 -d:pserver:anonymous\@cvs.sourceforge.net:/cvsroot/fink";
  } else {
    $cmd = "cvs -z3 -d:ext:$cvsuser\@cvs.sourceforge.net:/cvsroot/fink";
    $ENV{CVS_RSH} = "ssh";
  }
  $cmd = "$cmd checkout -d fink packages";
  if ($username ne "root") {
    $cmd = "su $username -c '$cmd'";
  }
  &print_breaking("Now downloading package descriptions...");
  if (&execute($cmd)) {
    die "Downloading package descriptions from CVS failed.\n";
  }
  if (not -d $tempfinkdir) {
    die "The CVS didn't report an error, but the directory '$tempfinkdir' ".
      "doesn't exist as expected. Strange.\n";
  }

  # merge the old tree
  $cutoff = length($finkdir)+1;
  find(sub {
	 if ($_ eq "CVS") {
	   $File::Find::prune = 1;
	   return;
	 }
	 return if (length($File::Find::name) <= $cutoff);
	 my $rel = substr($File::Find::name, $cutoff);
	 if (-l and not -e "$tempfinkdir/$rel") {
	   my $linkto;
	   $linkto = readlink($_)
	     or die "Can't read target of symlink $File::Find::name: $!\n";
           if (&execute("ln -s '$linkto' '$tempfinkdir/$rel'")) {
             die "Can't create symlink \"$tempfinkdir/$rel\"\n";
           }
	 } elsif (-d and not -d "$tempfinkdir/$rel") {
	   if (&execute("mkdir '$tempfinkdir/$rel'")) {
	     die "Can't create directory \"$tempfinkdir/$rel\"\n";
	   }
	 } elsif (-f and not -f "$tempfinkdir/$rel") {
	   my $cmd;
	   if ($use_hardlinks) {
	     $cmd = "ln";
	   } else {
	     $cmd = "cp -p"
	   }
	   $cmd .= " '$_' '$tempfinkdir/$rel'";
           if (&execute($cmd)) {
             die "Can't copy file \"$tempfinkdir/$rel\"\n";
           }
	 }
       }, $finkdir);

  # switch $tempfinkdir to $finkdir
  chdir $basepath or die "Can't cd to $basepath: $!\n";
  if (&execute("mv $finkdir $finkdir.old")) {
    die "Can't move \"$finkdir\" out of the way\n";
  }
  if (&execute("mv $tempfinkdir $finkdir")) {
    die "Can't move new tree \"$tempfinkdir\" into place at \"$finkdir\". ".
      "Warning: Your Fink installation is in an inconsistent state now.\n";
  }
  &execute("rm -rf $tempdir");

  print "\n";
  &print_breaking("Your Fink installation was successfully set up for ".
		  "direct CVS updating. The directory \"$finkdir.old\" ".
		  "contains your old package description tree. Its ".
		  "contents were merged into the new one, but the old ".
		  "tree was left intact for safety reasons. If you no ".
		  "longer need it, remove it manually.");
  print "\n";
}

### call cvs update

sub do_direct_cvs {
  my ($descdir, @sb, $cmd, $username, $msg);

  $descdir = "$basepath/fink";
  chdir $descdir or die "Can't cd to $descdir: $!\n";

  @sb = stat("$descdir/CVS");
  $cmd = "cvs -z3 update -d -P";
  $msg = "I will now run the cvs command to retrieve the latest package ".
    "descriptions. ";

  if ($sb[4] != 0 and $> != $sb[4]) {
    ($username) = getpwuid($sb[4]);
    $cmd = "su $username -c '$cmd'";
    $msg .= "The 'su' command will be used to run the cvs command as the ".
      "user '$username'. ";
  }

  $msg .= "After that, the core packages will be updated right away; ".
    "you should then update the other packages using commands like ".
    "'fink update-all'.";

  print "\n";
  &print_breaking($msg);
  print "\n";

  $ENV{CVS_RSH} = "ssh";
  if (&execute($cmd)) {
    die "Updating using CVS failed. Check the error messages above.\n";
  }
}

### update from packages tarball
# parameter: version number

sub do_tarball {
  my $newversion = shift;
  my ($destdir, $dir);
  my ($pkgtarball, $url, $verbosity, $unpack_cmd);

  print "\n";
  &print_breaking("I will now download the package descriptions for ".
		  "Fink $newversion and update the core packages. ".
		  "After that, you should update the other packages ".
		  "using commands like 'fink update-all'.");
  print "\n";

  $destdir = "$basepath/src";
  chdir $destdir or die "Can't cd to $destdir: $!\n";

  # go ahead and upgrade
  # first, download the packages tarball
  $dir = "packages-$newversion";
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
  if (Fink::Config::is_verbose()) {
    $verbosity = "v";
  }
  $unpack_cmd = "tar -xz${verbosity}f $pkgtarball";
  if (&execute($unpack_cmd)) {
    die "unpacking $pkgtarball failed\n";
  }

  # inject it
  chdir $dir or die "Can't cd into $dir: $!\n";
  if (&execute("./inject.pl $basepath -quiet")) {
    die "injecting the new package definitions from $pkgtarball failed\n";
  }
  chdir $destdir or die "Can't cd to $destdir: $!\n";
  if (-e $dir) {
    &execute("rm -rf $dir");
  }
}

### last steps: reread descriptions, update fink, re-exec

sub do_finish {
  # re-read package info
  Fink::Package->forget_packages();
  Fink::Package->force_update_db();
  Fink::Package->require_packages();

  # update the package manager itself first
  Fink::Engine::cmd_install("fink");

  # re-execute ourselves before we update the rest
  print "Re-executing fink to use the new version...\n";
  exec "$basepath/bin/fink selfupdate-finish";

  # the exec doesn't return, but just in case...
  die "re-executing fink failed, run 'fink selfupdate-finish' manually\n";
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
