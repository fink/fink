#
# Fink::Engine class
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

package Fink::Engine;

use Fink::Services qw(&print_breaking &print_breaking_prefix
                      &prompt_boolean &prompt_selection
                      &latest_version &execute &get_term_width
                      &file_MD5_checksum);
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

# The list of commands. Maps command names to a list containing
# a function reference, and two flags. The first flag indicates
# whether this command requires the package descriptions to be
# read, the second flag whether root permissions are needed.
our %commands =
  ( 'index' => [\&cmd_index, 0, 1],
    'rescan' => [\&cmd_rescan, 0, 0],
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
    'apropos' => [\&cmd_apropos, 0, 0],
    'describe' => [\&cmd_description, 1, 0],
    'description' => [\&cmd_description, 1, 0],
    'desc' => [\&cmd_description, 1, 0],
    'info' => [\&cmd_description, 1, 0],
    'scanpackages' => [\&cmd_scanpackages, 1, 1],
    'list' => [\&cmd_list, 0, 0],
    'listpackages' => [\&cmd_listpackages, 1, 0],
    'selfupdate' => [\&cmd_selfupdate, 0, 1],
    'selfupdate-cvs' => [\&cmd_selfupdate_cvs, 0, 1],
    'selfupdate-finish' => [\&cmd_selfupdate_finish, 1, 1],
    'validate' => [\&cmd_validate, 0, 0],
    'check' => [\&cmd_validate, 0, 0],
    'checksums' => [\&cmd_checksums, 1, 0],
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

sub cmd_index {
  Fink::Package->force_update_db();
}

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
  do_real_list("list",@_);
}

sub do_real_list {
  my ($pattern, @allnames, @selected);
  my ($pname, $package, $lversion, $vo, $iflag, $description);
  my ($formatstr, $desclen, $name, @temp_ARGV, $section);
  my %options =
  (
   "installedstate" => 0
  );
  my ($width, $namelen, $verlen, $dotab, $wanthelp);
  my $cmd = shift;
  use Getopt::Long;
  $formatstr = "%s %-15.15s %-11.11s %s\n";
  $desclen = 46;
  @temp_ARGV = @ARGV;
  @ARGV=@_;
  Getopt::Long::Configure(qw(bundling ignore_case require_order no_getopt_compat prefix_pattern=(--|-)));
  if ($cmd eq "list") {
    GetOptions(
	    'width|w=s' 	=> \$width,
	    'tab|t'		=> \$dotab,
	    'installed|i'	=> sub {$options{installedstate} |=3;},
	    'uptodate|u'	=> sub {$options{installedstate} |=2;},
	    'outdated|o'	=> sub {$options{installedstate} |=1;},
	    'notinstalled|n'	=> sub {$options{installedstate} |=4;},
	    'section|s=s'	=> \$section,
	    'help|h'		=> \$wanthelp
    ) or die "fink list: unknown option\nType 'fink list --help' for more information.\n";
  }  else { # apropos
    GetOptions(
	    'width|w=s' 	=> \$width,
	    'tab|t'		=> \$dotab,
	    'help|h'		=> \$wanthelp
    ) or die "fink list: unknown option\nType 'fink apropos --help' for more information.\n";  
  }
  if ($wanthelp) {
    require Fink::FinkVersion;
    my $version = Fink::FinkVersion::fink_version();

    print <<"EOF";
Fink $version, Copyright (c) 2001,2002 Christoph Pfisterer and others.
This is free software, distributed under the GNU General Public License.

Usage: fink [options] list [listoptions] [string]
       fink [options] apropos [listoptions] [string]
       
Where listoptions are:
  -w=xyz, --width=xyz	Sets the width of the display you would like the output
			formatted for. xyz is either a numeric value or auto.
			auto will set the width based on the terminal width.
                      
  -t, --tab		Outputs the list with the tab char as a delimiter 
			between fields. Useful for GUI implementations.

  -i, --installed	list only, lists only installed packages.
  
  -u, --uptodate	list only, lists only packages which are up to date.
  
  -o, --outdated	list only, lists packages for which a newer version 
			is available.
  
  -n, --notinstalled	list only, lists packages which are not installed.
  
  -s=expr, 		list only, lists packages in the sections matching
    --section=expr 	the expr. eg fink list --section=x11
 
  -h, --help		This text.

EOF
  exit 0;
  }
  if ($options{installedstate} == 0) {$options{installedstate} = 7;}

  if (defined $width) {
    if (($width eq "") || ($width eq "auto") || ($width eq "=auto") || ($width eq "=")) {
      $width = &get_term_width;
      if ($width == 0) {
        $desclen=0;
        $formatstr = "%s\t%s\t%s\t%s\n";
        undef $width;
      }
      else {
        if ($width < 40) { $width = 40; }
      }
    }  
    $width =~ s/[\=]?([0-9]+)/$1/;
    if ($width < 40) { $width = 40; }
    if (defined $width) {  
      $width = $width -5;
      $namelen = int($width * 0.2);
      $verlen = int($width * 0.15);
      if ($desclen != 0) {
        $desclen = $width - $namelen -$verlen -2;
      }
      $formatstr = "%s %-" . $namelen . "." . $namelen . "s %-" . $verlen . "." . $verlen . "s %s\n";
    }
  } else {
    if ($dotab) {
      $formatstr = "%s\t%s\t%s\t%s\n";
      $desclen = 0;
    }
  }
  Fink::Package->require_packages();
  @_=@ARGV;
  @ARGV=@temp_ARGV;
  @allnames = Fink::Package->list_packages();
  if ($cmd eq "list") {
    if ($#_ < 0) {
      @selected = @allnames;
    } else {
      @selected = ();
      while (defined($pattern = shift)) {
        $pattern = quotemeta $pattern; # fixes bug about ++ etc in search string.
	if ((grep /\\\*/, $pattern) or (grep /\\\?/, $pattern)) {
	   $pattern =~ s/\\\*/.*/g;
	   $pattern =~ s/\\\?/./g;
           push @selected, grep(/^$pattern$/, @allnames);
	} else {
	   push @selected, grep(/$pattern/, @allnames);
	}
      }
    }
  } else {
    $pattern = shift;
    @selected = @allnames;
    unless ($pattern) {
      die "no keyword specified for command 'apropos'!\n";
    }
  }

  foreach $pname (sort @selected) {
    $package = Fink::Package->package_by_name($pname);
    if ($package->is_virtual()) {
      $lversion = "";
      $iflag = "   ";
      $description = "[virtual package]";
      next if ($cmd eq "apropos"); 
      if (not ($options{installedstate} & 4)) {next; };
    } else {
      $lversion = &latest_version($package->list_versions());
      $vo = $package->get_version($lversion);
      if ($vo->is_installed()) {
        if (not ($options{installedstate} &2)) {next;};
        $iflag = " i ";
      } elsif ($package->is_any_installed()) {
        $iflag = "(i)";
        if (not ($options{installedstate} &1)) {next;};
      } else {
        $iflag = "   ";
        if (not ($options{installedstate} & 4)) {next; };
      }

      $description = $vo->get_shortdescription($desclen);
    }
    if (defined $section) {
      $section =~ s/[\=]?(.*)/$1/;
      next unless $vo->get_section($vo) =~ /\Q$section\E/i;
    }  
    if ($cmd eq "apropos") {
      next unless $vo->get_shortdescription(150) =~ /\Q$pattern\E/i;
    }
    printf $formatstr,
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
    if ($pkgname eq "apt" or $pkgname eq "storable-pm") {
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
  do_real_list("apropos", @_);  
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
      eval {
        $vo->phase_fetch();
      };
      warn "$@" if $@;         # turn fatal exceptions into warnings
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
      eval {
        $vo->phase_fetch(1);
      };
      warn "$@" if $@;         # turn fatal exceptions into warnings
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

# HACK HACK HACK
# This is to be removed soon again, only a temporary tool to allow
# checking of all available MD5 values in all packages.
sub cmd_checksums {
  my ($pname, $package, $vo, $i, $file, $chk);

  # Iterate over all packages
  foreach $pname (Fink::Package->list_packages()) {
    $package = Fink::Package->package_by_name($pname);
    foreach $vo ($package->get_all_versions()) {
      # Skip packages that do not have source files
      next if not defined $vo->{_sourcecount};
    
      # For each tar ball, if a checksum was specified, locate it and
      # verify the checksum.
      for ($i = 1; $i <= $vo->{_sourcecount}; $i++) {
	$chk = $vo->get_checksum($i);
	if ($chk ne "-") {
	  $file = $vo->find_tarball($i);
	  if (defined($file) and $chk ne &file_MD5_checksum($file)) {
	    print "Checksum of tarball $file of package ".$vo->get_fullname()." is incorrect.\n";
	  }
	}
      }
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
  my (%already_rebuilt, %already_activated);

  if (Fink::Config::is_verbose()) {
    $showlist = 1;
  }

  %deps = ();   # hash by package name

  %already_rebuilt = ();
  %already_activated = ();

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
    if ($item->[2]->is_installed() and $item->[3] != $OP_REBUILD) {
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
	  if ($deps{$dname}->[3] < $OP_INSTALL) {
	    $deps{$dname}->[3] = $OP_INSTALL;
	  }
	  # add a link
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
          my $package = Fink::Package->package_by_name($dname);
          my $lversion = &latest_version($package->list_versions());
          my $vo = $package->get_version($lversion);
          my $description = $vo->get_shortdescription(60);
	  $labels->{$dname} = "$dname: $description";
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


      if (($item->[3] == $OP_REBUILD and not $already_rebuilt{$pkgname})
	  or not $package->is_present()) {
	$package->phase_unpack();
	$package->phase_patch();
	$package->phase_compile();
	$package->phase_install();
	$package->phase_build();

	$already_rebuilt{$pkgname} = 1;

	my $parent;
	if (@{$package->{_splitoffs}} > 0) {
	  $parent = $package;
	} elsif (exists $package->{parent}) {
	  $parent = $package->{parent};
	}
	if (defined $parent) {
	  my $splitoff;
	  $already_rebuilt{$parent->get_name()} = 1;
	  foreach $splitoff (@{$package->{_splitoffs}}) {
	    $already_rebuilt{$splitoff->get_name()} = 1;
	    if ($splitoff->is_installed()) {
	      $already_activated{$splitoff->get_name()} = 1;
	      $splitoff->phase_activate();
	    }
	  }
	}
      }
      # Install the package if necessary and if it wasn't already installed 
      # previously. "Necessary" means that the command issued by the user
      # was an "install", a "reinstall" or a "rebuild" of an installed pkg.
      if (not $already_activated{$pkgname} and
	  ($item->[3] == $OP_INSTALL or $item->[3] == $OP_REINSTALL
	   or ($item->[3] == $OP_REBUILD and $package->is_installed()))) {
	$already_activated{$pkgname} = 1;
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
