#
# Fink::Package class
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

package Fink::Package;
use Fink::Base;
use Fink::Services qw(&read_properties &latest_version);
use Fink::Config qw($config $basepath);
use Fink::PkgVersion;
use File::Find;

use strict;
use warnings;

BEGIN {
  use Exporter ();
  our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
  $VERSION = 1.00;
  @ISA         = qw(Exporter Fink::Base);
  @EXPORT      = qw();
  @EXPORT_OK   = qw();  # eg: qw($Var1 %Hashit &func3);
  %EXPORT_TAGS = ( );   # eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

our ($have_packages, @package_list, @essential_packages, $essential_valid);
$have_packages = 0;
@package_list = ();
@essential_packages = ();
$essential_valid = 0;

END { }       # module clean-up code here (global destructor)


### constructor taking a name

sub new_with_name {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $pkgname = shift;

  my $self = {};
  bless($self, $class);

  $self->{package} = $pkgname;

  $self->initialize();

  return $self;
}

### self-initialization

sub initialize {
  my $self = shift;

  $self->SUPER::initialize();

  $self->{_name} = $self->param_default("Package", "");
  $self->{_versions} = {};
  $self->{_virtual} = 1;
  $self->{_providers} = [];

  push @package_list, $self;
}

### get package name

sub get_name {
  my $self = shift;

  return $self->{_name};
}

### get pure virtual package flag

sub is_virtual {
  my $self = shift;

  return $self->{_virtual};
}

### add a version object

sub add_version {
  my $self = shift;
  my $version_object = shift;

  my $version = $version_object->get_fullversion();
  if (exists $self->{_versions}->{$version}) {
    $self->{_versions}->{$version}->merge($version_object);
  } else {
    $self->{_versions}->{$version} = $version_object;
  }

  $self->{_virtual} = 0;
}

### add a providing version object of another package

sub add_provider {
  my $self = shift;
  my $provider = shift;

  push @{$self->{_providers}}, $provider;
}

### list available versions

sub list_versions {
  my $self = shift;

  return keys %{$self->{_versions}};
}

### other listings

sub get_all_versions {
  my $self = shift;

  return values %{$self->{_versions}};
}

sub get_matching_versions {
  my $self = shift;

  return values %{$self->{_versions}};
}

sub get_all_providers {
  my $self = shift;
  my (@versions);

  @versions = values %{$self->{_versions}};
  push @versions, @{$self->{_providers}};
  return @versions;
}

sub list_installed_versions {
  my $self = shift;
  my (@versions, $version);

  @versions = ();
  foreach $version (keys %{$self->{_versions}}) {
    push @versions, $version
      if $self->{_versions}->{$version}->is_installed();
  }
  return @versions;
}

sub is_any_installed {
  my $self = shift;
  my ($version);

  foreach $version (keys %{$self->{_versions}}) {
    return 1
      if $self->{_versions}->{$version}->is_installed();
  }
  return 0;
}

### get version object by exact name

sub get_version {
  my $self = shift;
  my $version = shift;

  unless (defined($version) && $version) {
    return undef;
  }
  if (exists $self->{_versions}->{$version}) {
    return $self->{_versions}->{$version};
  }
  return undef;
}


### get package by exact name, fail when not found

sub package_by_name {
  shift;  # class method - ignore first parameter
  my $pkgname = shift;
  my $package;

  foreach $package (@package_list) {
    if ($package->get_name() eq $pkgname) {
      return $package;
    }
  }
  return undef;
}

### get package by exact name, create when not found

sub package_by_name_create {
  shift;  # class method - ignore first parameter
  my $pkgname = shift;
  my $package;

  foreach $package (@package_list) {
    if ($package->get_name() eq $pkgname) {
      return $package;
    }
  }
  return Fink::Package->new_with_name($pkgname);
}

### list all packages

sub list_packages {
  shift;  # class method - ignore first parameter
  my ($package, @list);

  @list = ();
  foreach $package (@package_list) {
    push @list, $package->get_name();
  }
  return @list;
}

### list essential packages

sub list_essential_packages {
  shift;  # class method - ignore first parameter
  my ($package, $version, $vnode);

  if (not $essential_valid) {
    @essential_packages = ();
    foreach $package (@package_list) {
      $version = &latest_version($package->list_versions());
      $vnode = $package->get_version($version);
      if (defined($vnode) && $vnode->param_boolean("Essential")) {
	push @essential_packages, $package->get_name();
      }
    }
    $essential_valid = 1;
  }
  return @essential_packages;
}

### make sure package descriptions are available

sub require_packages {
  shift;  # class method - ignore first parameter

  if (!$have_packages) {
    print "Reading package info...\n";
    Fink::Package->scan_all();
  }
}

### forget about all packages

sub forget_packages {
  shift;  # class method - ignore first parameter

  $have_packages = 0;
  @package_list = ();
  @essential_packages = ();
  $essential_valid = 0;
}

### read list of packages from files

sub scan_all {
  shift;  # class method - ignore first parameter
  my ($tree, $dir);
  my ($dlist, $pkgname, $po, $hash, $fullversion);

  $have_packages = 0;
  @package_list = ();
  @essential_packages = ();
  $essential_valid = 0;

  # read data from descriptions
  foreach $tree ($config->get_treelist()) {
    $dir = "$basepath/fink/dists/$tree/finkinfo";
    Fink::Package->scan($dir);
  }

  # get data from dpkg's status file
  $dlist = Fink::Status->list();
  foreach $pkgname (keys %$dlist) {
    $po = Fink::Package->package_by_name_create($pkgname);
    next if exists $po->{_versions}->{$dlist->{$pkgname}->{version}};
    $hash = $dlist->{$pkgname};

    # create dummy object
    $fullversion = $hash->{version};
    if ($fullversion =~ /^(.+)-([^-]+)$/) {
      $hash->{version} = $1;
      $hash->{revision} = $2;
      $hash->{type} = "dummy";
      $hash->{filename} = "";

      Fink::Package->inject_description($po, $hash);
    }
  }

  $have_packages = 1;

  print "Information about ".($#package_list+1)." packages read.\n";
}

### scan one tree for package desccriptions

sub scan {
  shift;  # class method - ignore first parameter
  my $directory = shift;
  my (@filelist, $wanted);
  my ($filename, $properties, $pkgname, $package);

  return if not -d $directory;

  # search for .info files
  @filelist = ();
  $wanted =
    sub {
      if (-f and not /^[\.#]/ and /\.info$/) {
	push @filelist, $File::Find::fullname;
      }
    };
  find({ wanted => $wanted, follow => 1, no_chdir => 1 }, $directory);

  foreach $filename (@filelist) {
    # read the file and get the package name
    $properties = &read_properties($filename);
    $pkgname = $properties->{package};
    unless ($pkgname) {
      print "No package name in $filename\n";
      next;
    }
    unless ($properties->{version}) {
      print "No version number for package $pkgname in $filename\n";
      next;
    }

    # get/create package object
    $package = Fink::Package->package_by_name_create($pkgname);

    # create object for this particular version
    $properties->{thefilename} = $filename;
    Fink::Package->inject_description($package, $properties);
  }
}

### create a version object from a properties hash and link it
# first parameter: existing Package object
# second parameter: ref to hash with fields

sub inject_description {
  shift;  # class method - ignore first parameter
  my $po = shift;
  my $properties = shift;
  my ($version, $vp, $vpo);

  # create version object
  $version = Fink::PkgVersion->new_from_properties($properties);

  # link them together
  $po->add_version($version);

  # track provided packages
  if ($version->has_param("Provides")) {
    foreach $vp (split(/\s*\,\s*/, $version->param("Provides"))) {
      $vpo = Fink::Package->package_by_name_create($vp);
      $vpo->add_provider($version);
    }
  }
}


### EOF
1;
