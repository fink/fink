#
# Fink::Engine class
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

package Fink::Engine;

use Fink::Services qw(&prompt_boolean &print_breaking &print_breaking_prefix
                      &latest_version &execute);
use Fink::Package;
use Fink::PkgVersion;
use Fink::Config qw($config $basepath);
use Fink::Configure;
use Fink::Bootstrap;
use Fink::SelfUpdate;
use Fink::Validation qw(&validate_info_file &validate_dpkg_file);

use strict;
use warnings;

BEGIN {
  use Exporter ();
  our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
  $VERSION = 1.00;
  @ISA         = qw(Exporter);
  @EXPORT      = qw();
  @EXPORT_OK   = qw(&cmd_install);
  %EXPORT_TAGS = ( );   # eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

our %commands =
  ( 'rescan' => [\&cmd_rescan, 1],
    'configure' => [\&cmd_configure, 1],
    'bootstrap' => [\&cmd_bootstrap, 1],
    'fetch' => [\&cmd_fetch, 1],
    'fetch-all' => [\&cmd_fetch_all, 1],
    'fetch-missing' => [\&cmd_fetch_all_missing, 1],
    'build' => [\&cmd_build, 1],
    'rebuild' => [\&cmd_rebuild, 1],
    'install' => [\&cmd_install, 1],
    'reinstall' => [\&cmd_reinstall, 1],
    'update' => [\&cmd_install, 1],
    'update-all' => [\&cmd_update_all, 1],
    'enable' => [\&cmd_install, 1],
    'activate' => [\&cmd_install, 1],
    'use' => [\&cmd_install, 1],
    'disable' => [\&cmd_remove, 1],
    'deactivate' => [\&cmd_remove, 1],
    'unuse' => [\&cmd_remove, 1],
    'remove' => [\&cmd_remove, 1],
    'delete' => [\&cmd_remove, 1],
    'purge' => [\&cmd_remove, 1],
    'describe' => [\&cmd_description, 1],
    'description' => [\&cmd_description, 1],
    'desc' => [\&cmd_description, 1],
    'info' => [\&cmd_description, 1],
    'scanpackages' => [\&cmd_scanpackages, 1],
    'list' => [\&cmd_list, 1],
    'listpackages' => [\&cmd_listpackages, 1],
    'selfupdate' => [\&cmd_selfupdate, 1],
    'selfupdate-finish' => [\&cmd_selfupdate_finish, 1],
    'validate' => [\&cmd_validate, 0],
    'check' => [\&cmd_validate, 0],
  );

END { }       # module clean-up code here (global destructor)

### constructor using configuration

sub new_with_config {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $config_object = shift;

  my $self = {};
  bless($self, $class);

  $self->{config} = $config_object;

  $self->initialize();

  return $self;
}

### self-initialization

sub initialize {
  my $self = shift;
  my $config = $self->{config};
  my ($basepath);

  $self->{basepath} = $basepath = $config->param("basepath");
  if (!$basepath) {
    die "Basepath not set in config file!\n";
  }

#  print "Reading package info...\n";
#  Fink::Package->scan_all();
}

### process command

sub process {
  my $self = shift;
  my $cmd = shift;
  my ($cmdname, $flag, $proc, $arr);

  unless (defined $cmd) {
    print "NOP\n";
    return;
  }

  while (($cmdname, $arr) = each %commands) {
    if ($cmd eq $cmdname) {
      ($proc, $flag) = @$arr;
      if ($flag) {
        print "Reading package info...\n";
        Fink::Package->scan_all();
      }
      eval { &$proc(@_); };
      if ($@) {
	print "Failed: $@";
      } else {
	print "Done.\n";
      }
      return;
    }
  }

  die "unknown command: $cmd\n";
}

### simple commands

sub cmd_rescan {
  print "Re-reading package info...\n";
  Fink::Package->forget_packages();
  Fink::Package->scan_all();
}

sub cmd_configure {
  Fink::Configure::configure();
}

sub cmd_bootstrap {
  Fink::Bootstrap::bootstrap();
}

sub cmd_selfupdate {
  Fink::SelfUpdate::check();
}

sub cmd_selfupdate_finish {
  Fink::SelfUpdate::finish();
}

sub cmd_list {
  my ($pattern, @allnames, @selected);
  my ($pname, $package, $lversion, $vo, $iflag, $description);

  @allnames = Fink::Package->list_packages();
  if ($#_ < 0) {
    @selected = @allnames;
  } else {
    @selected = ();
    while (defined($pattern = shift)) {
      $pattern =~ s/\*/.*/g;
      $pattern =~ s/\?/./g;
      push @selected, grep(/$pattern/, @allnames);
    }
  }

  foreach $pname (sort @selected) {
    $package = Fink::Package->package_by_name($pname);
    if ($package->is_virtual()) {
      $lversion = "";
      $iflag = "   ";
      $description = "[virtual package]";
    } else {
      $lversion = &latest_version($package->list_versions());
      $vo = $package->get_version($lversion);
      if ($vo->is_installed()) {
	$iflag = " i ";
      } elsif ($package->is_any_installed()) {
	$iflag = "(i)";
      } else {
	$iflag = "   ";
      }
      $description = $vo->get_shortdescription(46);
    }

    printf "%s %-15.15s %-11.11s %s\n",
      $iflag, $pname, $lversion, $description;
  }
}

sub cmd_listpackages {
  my ($pname, $package);

  foreach $pname (Fink::Package->list_packages()) {
    print "$pname\n";
    $package = Fink::Package->package_by_name($pname);
    if ($package->is_any_installed()) {
      print "YES\n";
    } else {
      print "NO\n";
    }
  }
}

sub cmd_scanpackages {
  my @treelist = @_;
  my ($tree, $treedir, $cmd, $archive, $component);

  # do all trees by default
  if ($#treelist < 0) {
    @treelist = $config->get_treelist();
  }

  # create a global override file

  my ($pkgname, $package, $pkgversion, $prio);
  open(OVERRIDE,">$basepath/fink/override") or die "can't write override file: $!\n";
  foreach $pkgname (Fink::Package->list_packages()) {
    $package = Fink::Package->package_by_name($pkgname);
    next unless defined $package;
    $pkgversion = $package->get_version(&latest_version($package->list_versions()));
    next unless defined $pkgversion;

    $prio = "optional";
    if ($pkgversion->param_boolean("Essential")) {
      $prio = "required";
    }
    print OVERRIDE "$pkgname $prio ".$pkgversion->get_section()."\n";
  }
  close(OVERRIDE) or die "can't write override file: $!\n";

  # create the Packages.gz and Release files for each tree

  chdir "$basepath/fink";
  foreach $tree (@treelist) {
    $treedir = "dists/$tree/binary-darwin-powerpc";
    if ($tree =~ /^([^\/]+)\/(.+)$/) {
      $archive = $1;
      $component = $2;
    } else {
      $archive = $tree;
      $component = "main";
    }

    $cmd = "dpkg-scanpackages $treedir override | gzip >$treedir/Packages.gz";
    if (&execute($cmd)) {
      unlink("$treedir/Packages.gz");
      die "package scan failed\n";
    }

    open(RELEASE,">$treedir/Release") or die "can't write Release file: $!\n";
    print RELEASE <<EOF;
Archive: $archive
Component: $component
Origin: Fink
Label: Fink
Architecture: darwin-powerpc
EOF
    close(RELEASE) or die "can't write Release file: $!\n";
  }
}

### package-related commands

sub cmd_fetch {
  my ($package, @plist);

  @plist = &expand_packages(@_);
  if ($#plist < 0) {
    die "no package specified for command 'fetch'!\n";
  }

  foreach $package (@plist) {
    $package->phase_fetch();
  }
}

sub cmd_description {
  my ($package, @plist);

  @plist = &expand_packages(@_);
  if ($#plist < 0) {
    die "no package specified for command 'description'!\n";
  }

  print "\n";
  foreach $package (@plist) {
    print $package->get_fullname().": ";
    print $package->get_description();
    print "\n";
  }
}

sub cmd_fetch_missing {
  my ($package, @plist);

  @plist = &expand_packages(@_);
  if ($#plist < 0) {
    die "no package specified for command 'fetch'!\n";
  }

  foreach $package (@plist) {
    $package->phase_fetch(1);
  }
}

sub cmd_fetch_all {
  my ($pname, $package, $version, $vo);

  foreach $pname (Fink::Package->list_packages()) {
    $package = Fink::Package->package_by_name($pname);
    $version = &latest_version($package->list_versions());
    $vo = $package->get_version($version);
    if (defined $vo) {
      $vo->phase_fetch();
    }
  }
}

sub cmd_fetch_all_missing {
  my ($pname, $package, $version, $vo);

  foreach $pname (Fink::Package->list_packages()) {
    $package = Fink::Package->package_by_name($pname);
    $version = &latest_version($package->list_versions());
    $vo = $package->get_version($version);
    if (defined $vo) {
      $vo->phase_fetch(1);
    }
  }
}

sub cmd_remove {
  my ($package, @plist);

  @plist = &expand_packages(@_);
  if ($#plist < 0) {
    die "no package specified for command 'remove'!\n";
  }

  foreach $package (@plist) {
    $package->phase_deactivate();
  }
}

sub cmd_validate {
  my ($filename, @flist);
  
  @flist = @_;
  if ($#flist < 0) {
    die "no input file specified for command 'validate'!\n";
  }
  
  print "\n";
  foreach $filename (@flist) {
    die "File \"$filename\" does not exist!\n" unless (-f $filename);
    if ($filename =~/\.info$/) {
      &validate_info_file($filename);
      print "\n";
    } elsif ($filename =~/\.deb$/) {
      &validate_dpkg_file($filename);
      print "\n";
    } else {
      print "Don't know how to handle $filename, skipping\n";
    }
  }
}


### building and installing

my ($OP_BUILD, $OP_INSTALL, $OP_REBUILD, $OP_REINSTALL) =
  (0, 1, 2, 3);

sub cmd_build {
  &real_install($OP_BUILD, 0, @_);
}

sub cmd_rebuild {
  &real_install($OP_REBUILD, 0, @_);
}

sub cmd_install {
  &real_install($OP_INSTALL, 0, @_);
}

sub cmd_reinstall {
  &real_install($OP_REINSTALL, 0, @_);
}

sub cmd_update_all {
  my (@plist, $pname, $package);

  foreach $pname (Fink::Package->list_packages()) {
    $package = Fink::Package->package_by_name($pname);
    if ($package->is_any_installed()) {
      push @plist, $pname;
    }
  }

  &real_install($OP_INSTALL, 1, @plist);
}

sub real_install {
  my $op = shift;
  my $showlist = shift;
  my ($pkgspec, $package, $pkgname, $pkgobj, $item, $dep);
  my ($all_installed, $any_installed);
  my (%deps, @queue, @deplist, @vlist, @requested, @additionals, @elist);
  my ($oversion, $opackage, $v, $ep, $dp, $dname);
  my ($answer, $s);

  if ($config->param_boolean("Verbose")) {
    $showlist = 1;
  }

  %deps = ();   # hash by package name

  # add requested packages
  foreach $pkgspec (@_) {
    # resolve package name
    #  (automatically gets the newest version)
    $package = Fink::PkgVersion->match_package($pkgspec);
    unless (defined $package) {
      die "no package found for specification '$pkgspec'!\n";
    }
    # no duplicates here
    #  (dependencies is different, but those are checked later)
    $pkgname = $package->get_name();
    if (exists $deps{$pkgname}) {
      print "Duplicate request for package '$pkgname' ignored.\n";
      next;
    }
    $pkgobj = Fink::Package->package_by_name($pkgname);
    # skip if this version/revision is installed
    #  (also applies to update)
    if ($op != $OP_REBUILD and $op != $OP_REINSTALL
	and $package->is_installed()) {
      next;
    }
    # for build, also skip if present, but not installed
    if ($op == $OP_BUILD
	and $package->is_present()) {
      next;
    }
    # add to table
    $deps{$pkgname} = [ $pkgname, $pkgobj, $package, $op, 1 ];
  }

  @queue = keys %deps;
  if ($#queue < 0) {
    print "No packages to install.\n";
    return;
  }

  # resolve dependencies for essential packages
  @elist = Fink::Package->list_essential_packages();
  foreach $ep (@elist) {
    # no virtual packages here
    $ep = [ Fink::Package->package_by_name($ep)->get_all_versions() ];
  }

  # recursively expand dependencies
  while ($#queue >= 0) {
    $pkgname = shift @queue;
    $item = $deps{$pkgname};

    # check installation state
    if ($item->[2]->is_installed()) {
      if ($item->[4] == 0) {
	$item->[4] = 2;
      }
      # already installed, don't think about it any more
      next;
    }

    # get list of dependencies
    @deplist = $item->[2]->resolve_depends();
    if (not $item->[2]->param_boolean("Essential")) {
      push @deplist, @elist;
    }
  DEPLOOP: foreach $dep (@deplist) {
      next if $#$dep < 0;   # skip empty lists

      # check the graph
      foreach $dp (@$dep) {
	$dname = $dp->get_name();
	if (exists $deps{$dname} and $deps{$dname}->[2] == $dp) {
	  push @$item, $deps{$dname};
	  next DEPLOOP;
	}
      }

      # check for installed pkgs
      foreach $dp (@$dep) {
	if ($dp->is_installed()) {
	  $dname = $dp->get_name();
	  if (exists $deps{$dname}) {
	    die "Internal error: node for $dname already exists\n";
	  }
	  # add node to graph
	  $deps{$dname} = [ $dname, Fink::Package->package_by_name($dname),
			    $dp, $OP_INSTALL, 2 ];
	  # add a link
	  push @$item, $deps{$dname};
	  # add to investigation queue
	  push @queue, $dname;
	  next DEPLOOP;
	}
      }

      # else choose one arbitrarily
      $dname = $dep->[0]->get_name();
      if (exists $deps{$dname}) {
	die "Internal error: node for $dname already exists\n";
      }

      my (@vlist, $pnode);
      $pnode = Fink::Package->package_by_name($dname);
      @vlist = ();
      foreach $dp (@$dep) {
	if ($dp->get_name() eq $dname) {
	  push @vlist, $dp->get_fullversion();
	}
      }
      
      # add node to graph
      $deps{$dname} = [ $dname, $pnode,
			$pnode->get_version(&latest_version(@vlist)),
			$OP_INSTALL, 0 ];
      # add a link
      push @$item, $deps{$dname};
      # add to investigation queue
      push @queue, $dname;
    }
  }

  # generate summary
  @requested = ();
  @additionals = ();
  foreach $pkgname (sort keys %deps) {
    $item = $deps{$pkgname};
    if ($item->[4] == 0) {
      push @additionals, $pkgname;
    } elsif ($item->[4] == 1) {
      push @requested, $pkgname;
    }
  }

  # display list of requested packages
  if ($showlist) {
    $s = "The following ";
    if ($#requested > 0) {
      $s .= scalar(@requested)." packages";
    } else {
      $s .= "package";
    }
    $s .= " will be ";
    if ($op == $OP_INSTALL) {
      $s .= "installed or updated";
    } elsif ($op == $OP_BUILD) {
      $s .= "built";
    } elsif ($op == $OP_REBUILD) {
      $s .= "rebuilt";
    } elsif ($op == $OP_REINSTALL) {
      $s .= "reinstalled";
    }
    $s .= ":";
    &print_breaking($s);
    &print_breaking_prefix(join(" ",@requested), 1, " ");
  }
  # ask user when additional packages are to be installed
  if ($#additionals >= 0) {
    if ($#additionals > 0) {
      &print_breaking("The following ".scalar(@additionals).
		      " additional packages will be installed:");
    } else {
      &print_breaking("The following additional package ".
		      "will be installed:");
    }
    &print_breaking_prefix(join(" ",@additionals), 1, " ");
    $answer = &prompt_boolean("Do you want to continue?", 1);
    if (! $answer) {
      die "Dependencies not satisfied\n";
    }
  }

  # fetch all packages that need fetching
  foreach $pkgname (sort keys %deps) {
    $item = $deps{$pkgname};
    next if $item->[3] == $OP_INSTALL and $item->[2]->is_installed();
    if ($item->[3] == $OP_REBUILD or not $item->[2]->is_present()) {
      $item->[2]->phase_fetch(1);
    }
  }

  # install in correct order...
  while (1) {
    $all_installed = 1;
    $any_installed = 0;
  PACKAGELOOP: foreach $pkgname (sort keys %deps) {
      $item = $deps{$pkgname};
      next if (($item->[4] & 2) == 2);   # already installed
      $all_installed = 0;

      # check dependencies
      foreach $dep (@$item[5..$#$item]) {
	next PACKAGELOOP if (($dep->[4] & 2) == 0);
      }

      # build it
      $any_installed = 1;
      $package = $item->[2];

      if ($item->[3] == $OP_REBUILD or not $package->is_present()) {
	$package->phase_unpack();
	$package->phase_patch();
	$package->phase_compile();
	$package->phase_install();
	$package->phase_build();
      }
      if ($item->[3] != $OP_BUILD
	  and ($item->[3] != $OP_REBUILD or $package->is_installed())) {
	$package->phase_activate();
      }

      # mark it as installed
      $item->[4] |= 2;
    }
    last if $all_installed;

    if (!$any_installed) {
      die "Problem resolving dependencies. Check for circular dependencies.\n";
    }
  }
}

### helper routines

sub expand_packages {
  my ($pkgspec, $package, @package_list);

  @package_list = ();
  foreach $pkgspec (@_) {
    $package = Fink::PkgVersion->match_package($pkgspec);
    unless (defined $package) {
      die "no package found for specification '$pkgspec'!\n";
    }
    push @package_list, $package;
  }
  return @package_list;
}


### EOF
1;
