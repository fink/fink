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
use Fink::Services qw(read_properties);

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

our (@package_list);
@package_list = ();

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

  push @package_list, $self;
}

### get package name

sub get_name {
  my $self = shift;

  return $self->{_name};
}

### add a version object

sub add_version {
  my $self = shift;
  my $version_object = shift;

  my $version = $version_object->get_fullversion();
  $self->{_versions}->{$version} = $version_object;
}

### list available versions

sub list_versions {
  my $self = shift;

  return keys %{$self->{_versions}};
}

### other listings

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

### forget about all packages

sub forget_packages {
  shift;  # class method - ignore first parameter

  @package_list = ();
}

### read list of packages from files

sub scan {
  shift;  # class method - ignore first parameter
  my $directory = shift;
  my ($filename, $properties);
  my ($pkgname, $package, $version);

  foreach $filename (glob $directory."/*") {
    # skip backup files etc.
    next if $filename =~ /^[\.\#]/ or $filename =~ /[\~\#]$/;
    next unless -f $filename;

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
    $version = Fink::PkgVersion->new_from_properties($properties);

    # link them together
    $package->add_version($version);

##    print " ".$package->get_name()." ".$version->get_version()."\n";
  }

  print "Information about ".($#package_list+1)." packages read.\n";
}


### EOF
1;
