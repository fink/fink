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

use Fink::Services qw(&print_breaking &print_breaking_prefix
                      &prompt_boolean &prompt_selection
                      &latest_version &execute);
use Fink::Package;
use Fink::PkgVersion;
use Fink::Config qw($config $basepath);

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
  ( 'rescan' => [\&cmd_rescan, 0, 0],
    'configure' => [\&cmd_configure, 0, 1],
    'bootstrap' => [\&cmd_bootstrap, 0, 1],
    'fetch' => [\&cmd_fetch, 1, 1],
    'fetch-all' => [\&cmd_fetch_all, 1, 1],
    'fetch-missing' => [\&cmd_fetch_all_missing, 1, 1],
    'build' => [\&cmd_build, 1, 1],
    'rebuild' => [\&cmd_rebuild, 1, 1],
    'install' => [\&cmd_install, 1, 1],
    'reinstall' => [\&cmd_reinstall, 1, 1],
    'update' => [\&cmd_install, 1, 1],
    'update-all' => [\&cmd_update_all, 1, 1],
    'enable' => [\&cmd_install, 1, 1],
    'activate' => [\&cmd_install, 1, 1],
    'use' => [\&cmd_install, 1, 1],
    'disable' => [\&cmd_remove, 1, 1],
    'deactivate' => [\&cmd_remove, 1, 1],
    'unuse' => [\&cmd_remove, 1, 1],
    'remove' => [\&cmd_remove, 1, 1],
    'delete' => [\&cmd_remove, 1, 1],
    'purge' => [\&cmd_remove, 1, 1],
    'apropos' => [\&cmd_apropos, 1, 0],
    'describe' => [\&cmd_description, 1, 0],
    'description' => [\&cmd_description, 1, 0],
    'desc' => [\&cmd_description, 1, 0],
    'info' => [\&cmd_description, 1, 0],
    'scanpackages' => [\&cmd_scanpackages, 1, 1],
    'list' => [\&cmd_list, 1, 0],
    'listpackages' => [\&cmd_listpackages, 1, 0],
    'selfupdate' => [\&cmd_selfupdate, 0, 1],
    'selfupdate-cvs' => [\&cmd_selfupdate_cvs, 0, 1],
    'selfupdate-finish' => [\&cmd_selfupdate_finish, 1, 1],
    'validate' => [\&cmd_validate, 0, 0],
    'check' => [\&cmd_validate, 0, 0],
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
}

### process command

sub process {
  my $self = shift;
  my $cmd = shift;
  my ($cmdname, $cmdinfo, $info);
  my ($proc, $pkgflag, $rootflag);

  unless (defined $cmd) {
    print "NOP\n";
    return;
  }

  $cmdinfo = undef;
  while (($cmdname, $info) = each %commands) {
    if ($cmd eq $cmdname) {
      $cmdinfo = $info;
      last;
    }
  }
  if (not defined $cmdinfo) {
    die "fink: unknown command \"$cmd\".\nType 'fink --help' for more information.\n";
  }

  ($proc, $pkgflag, $rootflag) = @$cmdinfo;

  # check if we need to be root
  if ($rootflag and $> != 0) {
    &restart_as_root($cmd, @_);
  }

  # read package descriptions if needed
  if ($pkgflag) {
    Fink::Package->require_packages();
  }
  eval { &$proc(@_); };
  if ($@) {
    print "Failed: $@";
  }
}

### restart as root with command

sub restart_as_root {
  my ($method, $cmd, $arg);

  $method = $config->param_default("RootMethod", "sudo");

  $cmd = "$basepath/bin/fink";

  # Pass on options
  if (Fink::Config::get_option("dontask")) {
    $cmd .= " --yes";
  }
  if (Fink::Config::get_option("verbosity")>0) {
    $cmd .= " --verbose";
  }
  elsif (Fink::Config::get_option("verbosity")<0) {
    $cmd .= " --quiet";
  }
  if (Fink::Config::get_option("interactive")) {
    $cmd .= " --interactive";
  }
  # TODO: add code that automates passing on the options!

  foreach $arg (@_) {
    if ($arg =~ /^[A-Za-z0-9_.+-]+$/) {
      $cmd .= " $arg";
    } else {
      # safety first
      $arg =~ s/[\$\`\'\"|;]/_/g;
      $cmd .= " \"$arg\"";
    }
  }

  if ($method eq "sudo") {
    $cmd = "sudo $cmd";
  } elsif ($method eq "su") {
    $cmd = "su root -c '$cmd'";
  } else {
    die "Fink is not configured to become root automatically.\n";
  }

  exit &execute($cmd, 1);
}

### simple commands

sub cmd_rescan {
  Fink::Package->forget_packages();
  Fink::Package->require_packages();
}

sub cmd_configure {
  require Fink::Configure;
  Fink::Configure::configure();
}

sub cmd_bootstrap {
  require Fink::Bootstrap;
  Fink::Bootstrap::bootstrap();
}

sub cmd_selfupdate {
  require Fink::SelfUpdate;
  Fink::SelfUpdate::check();
}

sub cmd_selfupdate_cvs {
  require Fink::SelfUpdate;
  Fink::SelfUpdate::check(1);
}

sub cmd_selfupdate_finish {
  require Fink::SelfUpdate;
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

  my ($pkgname, $package, $pkgversion, $prio, $section);
  open(OVERRIDE,">$basepath/fink/override") or die "can't write override file: $!\n";
  foreach $pkgname (Fink::Package->list_packages()) {
    $package = Fink::Package->package_by_name($pkgname);
    next unless defined $package;
    $pkgversion = $package->get_version(&latest_version($package->list_versions()));
    next unless defined $pkgversion;

    $section = $pkgversion->get_section();
    if ($section eq "bootstrap") {
      $section = "base";
    }

    $prio = "optional";
    if ($pkgname eq "apt") {
      $prio = "important";
    }
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

    if (! -d $treedir) {
      if (&execute("mkdir -p $treedir")) {
	die "can't create directory $treedir\n";
      }
    }

    $cmd = "dpkg-scanpackages $treedir override | gzip >$treedir/Packages.gz";
    if (&execute($cmd)) {
      unlink("$treedir/Packages.gz");
      die "package scan failed in $treedir\n";
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

sub cmd_apropos {
  my ($pattern, @allnames);
  my ($pname, $package, $lversion, $vo, $iflag, $description);

  $pattern = shift;
  unless ($pattern) {
    die "no keyword specified for command 'apropos'!\n";
  }

  @allnames = Fink::Package->list_packages();
  
  print "\n";
  foreach $pname (sort @allnames) {
    $package = Fink::Package->package_by_name($pname);
    next unless defined $package;
    next if $package->is_virtual();

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

	next unless $vo->get_shortdescription(150) =~ /$pattern/i;

    printf "%s %-15.15s %-11.11s %s\n",
      $iflag, $pname, $lversion, $description;
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
  my ($package, @plist, $pnames);

  @plist = &expand_packages(@_);
  if ($#plist < 0) {
    die "no package specified for command 'remove'!\n";
  }

  $pnames = "";
  foreach $package (@plist) {
    $pnames = $pnames." ".$package->get_name();
  }
  if (&execute("dpkg --remove ".$pnames)) {
    die "can't remove package(s)\n";
  }
  Fink::Status->invalidate();
}

sub cmd_validate {
  my ($filename, @flist);

  require Fink::Validation;

  @flist = @_;
  if ($#flist < 0) {
    die "no input file specified for command 'validate'!\n";
  }
  
  foreach $filename (@flist) {
    die "File \"$filename\" does not exist!\n" unless (-f $filename);
    if ($filename =~/\.info$/) {
      Fink::Validation::validate_info_file($filename);
    } elsif ($filename =~/\.deb$/) {
      Fink::Validation::validate_dpkg_file($filename);
    } else {
      die "Don't know how to validate $filename!\n";
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
  my (%candidates, @candidates, $pnode);
  my ($oversion, $opackage, $v, $ep, $dp, $dname);
  my ($answer, $s);

  if (Fink::Config::is_verbose()) {
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
    if ($item->[3] == $OP_REBUILD or not $item->[2]->is_present()) {
      # include build-time dependencies
      @deplist = $item->[2]->resolve_depends(1);
    } else {
      @deplist = $item->[2]->resolve_depends(0);
    }
    # add essential packages
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

      # check for installed pkgs (exact revision)
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

      # make list of package names (preserve order)
      %candidates = ();
      @candidates = ();
      foreach $dp (@$dep) {
	next if exists $candidates{$dp->get_name()};
	$candidates{$dp->get_name()} = 1;
	push @candidates, $dp->get_name();
      }
      my $found = 0;

      if ($#candidates == 0) {  # only one candidate
	$dname = $candidates[0];
	$found = 1;
      }

      if (not $found) {
	# check for installed pkgs (by name)
	my $cand;
	foreach $cand (@candidates) {
	  $pnode = Fink::Package->package_by_name($cand);
	  if ($pnode->is_any_installed()) {
	    $dname = $cand;
	    $found = 1;
	    last;
	  }
	}
      }

      if (not $found) {
	# let the user pick one

	my $labels = {};
	foreach $dname (@candidates) {
	  $labels->{$dname} = $dname;
	}

	print "\n";
	&print_breaking("fink needs help picking an alternative to satisfy ".
			"a virtual dependency. The candidates:");
	$dname =
	  &prompt_selection("Pick one:", 1, $labels, @candidates);
      }

      # the dice are rolled...

      if (exists $deps{$dname}) {
	die "Internal error: node for $dname already exists\n";
      }

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
