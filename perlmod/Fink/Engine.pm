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
                      &latest_version &execute &read_properties &expand_percent);
use Fink::Package;
use Fink::PkgVersion;
use Fink::Config qw($config $basepath);
use Fink::Configure;
use Fink::Bootstrap;
use Fink::SelfUpdate;

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

our @boolean_fields = qw(Essential NoSourceDirectory UpdateConfigGuess UpdateLibtool); # add NoSet* !
our @obsolete_fields = qw(Comment CommentPort CommenStow UseGettext);
our @name_version_fields = qw(Source SourceDirectory SourceN SourceNExtractDir Patch);
our @recommended_field_order =
  qw(
    Package
    Version
    Revision
    Type
    Maintainer
    Depends
    Provides
    Conflicts
    Replaces
    Essential
    Source
    SourceDirectory
    NoSourceDirectory
    SourceN
    SourceNExtractDir
    UpdateConfigGuess
    UpdateLibtool
    Patch
    PatchScript
    ConfigureParams
    CompileScript
    InstallScript
    Set*
    NoSet*
    PreInstScript
    PostInstScript
    PreRmScript
    PostRmScript
    ConfFiles
    InfoDocs
    DaemonicFile
    DaemonicName
    Description
    DescDetail
    DescUsage
    DescPackaging
    DescPort
    Homepage
    License
  );	# The order for "License" is not yet officiall specified


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

### .info/.deb file validation

# Should check/verifies the following in .info files:
#   + the filename matches %f.info
#   + patch file is present
#   + all required fields are present
#   + warn if obsolete fields are encountered
#   + warn about missing Description/Maintainer fields
#   + warn about overlong Description fields
#   + warn if boolean fields contain bogus values
#   + warn if fields seem to contain the package name/version, and suggest %n/%v should be used
#     (excluded from this are fields like Description, Homepage etc.)
#
# TODO: Optionally, should sort the fields to the recommended field order
#   - warn if unknown fields are encountered
#   - error if format is violated (e.g. bad here-doc)
#   - warn if /sw is hardcoded somewhere
#   - if type is bundle/nosource - warn about usage of "Source" etc.
# ... other things, make suggestions ;)
#
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

sub validate_info_file {
	my $filename = shift;
	my ($properties, @parts);
	my ($pkgname, $pkgversion, $pkgrevision, $pkgfullname, $pkgdestdir, $pkgpatchpath);
	my ($field, $value);
	my ($expand);
	my $looks_good = 1;

	print "Validating package file $filename...\n";
	
	# read the file properties
	$properties = &read_properties($filename);
	
	$pkgname = $properties->{package};
	$pkgversion = $properties->{version};
	$pkgrevision = $properties->{revision};
	$pkgfullname = "$pkgname-$pkgversion-$pkgrevision";
	$pkgdestdir = "$basepath/src/root-".$pkgfullname;
	
	@parts = split(/\//, $filename);
	pop @parts;   # remove filename
	$pkgpatchpath = join("/", @parts);
	
	unless ($pkgname) {
		print "Error: No package name in $filename\n";
		return;
	}
	unless ($pkgversion) {
		print "Error: No version number in $filename\n";
		return;
	}
	unless ($pkgrevision) {
		print "Error: No revision number or revision number is 0 in $filename\n";
		return;
	}
	if ($pkgname =~ /[^-.a-z0-9]/) {
		print "Error: Package name may only contain lowercase letters, numbers, '.' and '-'\n";
		return;
	}
	unless ($properties->{maintainer}) {
		print "Error: No maintainer specified in $filename\n";
		$looks_good = 0;
	}

	unless ("$pkgfullname.info" eq $filename) {
		print "Warning: File name should be $pkgfullname.info but is $filename\n";
		$looks_good = 0;
	}
	
	# Check whether any of the following fields contains the package name or version,
	# and suggest that %f/%n/%v be used instead
	foreach $field (@name_version_fields) {
		$value = $properties->{lc $field};
		if ($value) {
			if ($value =~ /$pkgfullname/) {
				print "Warning: Field \"$field\" contains full package name. Use %f instead.\n";
				$looks_good = 0;
			} else {
#				if ($value =~ /$pkgname/) {
#					print "Warning: Field \"$field\" contains package name. Use %n instead.\n";
#					$looks_good = 0;
#				}
				if ($value =~ /$pkgversion/) {
					print "Warning: Field \"$field\" contains package version. Use %v instead.\n";
					$looks_good = 0;
				}
			}
		}
	}
	
	# Check if any obsolete fields are used
	foreach $field (@obsolete_fields) {
		if ($properties->{lc $field}) {
			print "Warning: Field \"$field\" is obsolete.\n";
			$looks_good = 0;
		}
	}

	# Boolean fields
	foreach $field (@boolean_fields) {
		$value = $properties->{lc $field};
		if ($value) {
			unless ($value =~ /^\s*(true|yes|on|1|false|no|off|0)\s*$/) {
				print "Warning: Boolean field \"$field\" contains suspicious value \"$value\".\n";
				$looks_good = 0;
			}
		}
	}
	
	# Warn for missing / overlong package descriptions
	$value = $properties->{description};
	unless ($value) {
		print "Warning: No package description supplied.\n";
		$looks_good = 0;
	}
	elsif (length($value) > 40) {
		print "Warning: Length of package description exceeds 40 characters.\n";
		$looks_good = 0;
	}
			
	$expand = { 'n' => $pkgname,
				'v' => $pkgversion,
				'r' => $pkgrevision,
				'f' => $pkgfullname,
				'p' => $basepath, 'P' => $basepath,
				'd' => $pkgdestdir,
				'i' => $pkgdestdir.$basepath,
				'a' => $pkgpatchpath,
				'b' => '.'
	};
	
	# Verify the patch file exists, if specified
	$value = $properties->{patchfile};
	if ($value) {
		$value = &expand_percent($value, $expand);
		unless (-f $value) {
			print "Error: can't find patchfile \"$value\"\n";
			$looks_good = 0;
		}
	}
	
	if ($looks_good) {
		print "Package looks good!\n";
	}
}

#
# Check a given .deb file for standard compliance
#
#	- usage of non-recommended directories (/sw/src, /sw/man, /sw/info, /sw/doc, /sw/libexec)
#	- usage of other non-standard subdirs 
#	- ideas?
#
sub validate_dpkg_file {
	my $filename = shift;
	my @bad_dirs = ("$basepath/src/", "$basepath/man/", "$basepath/info/", "$basepath/doc/", "$basepath/libexec/");
	my ($pid, $bad_dir);
	
	print "Validating .deb file $filename...\n";
	
	# Quick & Dirty solution!!!
	$pid = open(README, "dpkg --contents $filename |") or die "Couldn't run dpkg: $!\n";
	while (<README>) {
		# process
		if (/([^\s]*)\s*([^\s]*)\s*([^\s]*)\s*([^\s]*)\s*([^\s]*)\s*\.([^\s]*)/) {
			$filename = $6;
			#print "$6\n";
			foreach $bad_dir (@bad_dirs) {
				if ($6 =~ /^$bad_dir/) {
					print "Warning: File installed into depracted directory $bad_dir\n";
					print "         Offender is $filename\n";
					last;
				}
			}
		}
	}
	close(README) or die "Error on close: $!\n";
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
