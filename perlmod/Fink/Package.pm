#
# Fink::Package class
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2003 The Fink Package Manager Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA	 02111-1307, USA.
#

package Fink::Package;
use Fink::Base;
use Fink::Services qw(&read_properties &latest_version &version_cmp 
                      &parse_fullversion &print_breaking);
use Fink::Config qw($config $basepath $debarch);
use Fink::PkgVersion;
use File::Find;

use strict;
use warnings;

our $VERSION = 1.00;
our @ISA = qw(Fink::Base);

our $have_packages = 0;
our $packages = {};
our @essential_packages = ();
our $essential_valid = 0;
our $db_outdated = 1;
our $db_mtime = 0;

END { }				# module clean-up code here (global destructor)


### constructor taking a name

sub new_with_name {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $pkgname = shift;

	my $self = {};
	bless($self, $class);

	$self->{package} = lc $pkgname;

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

	$packages->{$self->{package}} = $self;
}

### get package name

sub get_name {
	my $self = shift;

	return $self->{_name};
}

### get pure virtual package flag

sub is_virtual {
	use Fink::VirtPackage;
	my $self = shift;

	if (Fink::VirtPackage->query_package($self->{_name})) {
		# Fix to set VirtPackage.pm pkgs as virtuals level 2
		$self->{_virtual} = 2;
	}
	return $self->{_virtual};
}

### add a version object

sub add_version {
	my $self = shift;
	my $version_object = shift;

	my $version = $version_object->get_fullversion();
	if (exists $self->{_versions}->{ $version} 
		&& $self->{_versions}->{ $version}->{_type} eq 'dummy' ) {
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
	my $spec = shift;
	my @include_list = @_;
	my (@list, $version, $vo, $relation, $reqversion);

	if ($spec =~ /^\s*(<<|<=|=|>=|>>)\s*([0-9a-zA-Z.\+-:]+)\s*$/) {
		$relation = $1;
		$reqversion = $2;
	} else {
		die "Illegal version specification '".$spec."' for package ".$self->get_name()."\n";
	}

	@list = ();
	
	while (($version, $vo) = each %{$self->{_versions}}) {
		push @list, $vo if &version_cmp($version, $relation, $reqversion);
	}

	if (@include_list > 0) {
		my @match_list;
		# if we've been given a list to choose from, return the
		# intersection of the two
		for my $vo (@list) {
			my $version = $vo->get_version();
			if (grep(/^${version}$/, @include_list)) {
				push(@match_list, $vo);
			}
		}
		return @match_list;
	} else {
	return @list;
	}
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

sub is_any_present{
	my $self = shift;
	my ($version);

	foreach $version (keys %{$self->{_versions}}) {
		return 1
			if $self->{_versions}->{$version}->is_present();
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
	shift;	# class method - ignore first parameter
	my $pkgname = shift;
	my $package;

	return $packages->{lc $pkgname};
}

### get package by exact name, create when not found

sub package_by_name_create {
	shift;	# class method - ignore first parameter
	my $pkgname = shift;
	my $package;

	return $packages->{lc $pkgname} || Fink::Package->new_with_name($pkgname);
}

### list all packages

sub list_packages {
	shift;	# class method - ignore first parameter

	return keys %$packages;
}

### list essential packages

sub list_essential_packages {
	shift;	# class method - ignore first parameter
	my ($package, $version, $vnode);

	if (not $essential_valid) {
		@essential_packages = ();
		foreach $package (values %$packages) {
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
	shift;	# class method - ignore first parameter

	if (!$have_packages) {
		Fink::Package->scan_all();
	}
}

### forget about all packages

sub forget_packages {
	shift;	# class method - ignore first parameter

	$have_packages = 0;
	%$packages = ();
	@essential_packages = ();
	$essential_valid = 0;
	$db_outdated = 1;
}

### read list of packages, either from cache or files

sub scan_all {
	shift;	# class method - ignore first parameter
	my ($time) = time;
	my ($dlist, $pkgname, $po, $hash, $fullversion, @versions);

	Fink::Package->forget_packages();
	
	# If we have the Storable perl module, try to use the package index
	if (-e "$basepath/var/db/fink.db") {
		eval {
			require Storable; 

			# We assume the DB is up-to-date unless proven otherwise
			$db_outdated = 0;
		
			# Unless the NoAutoIndex option is set, check whether we should regenerate
			# the index based on its modification date and that of the package descs.
			if (not $config->param_boolean("NoAutoIndex")) {
				$db_mtime = (stat("$basepath/var/db/fink.db"))[9];			 
				if (((lstat("$basepath/etc/fink.conf"))[9] > $db_mtime)
					or ((stat("$basepath/etc/fink.conf"))[9] > $db_mtime)) {
					$db_outdated = 1;
				} else {
					$db_outdated = &search_comparedb( "$basepath/fink/dists" );
				}
			}
			
			# If the index is not outdated, we can use it, and thus safe a lot of time
			 if (not $db_outdated) {
				$packages = Storable::retrieve("$basepath/var/db/fink.db");
			 }
		}
	}
	
	# Regenerate the DB if it is outdated
	if ($db_outdated) {
		Fink::Package->update_db();
	}

	# Get data from dpkg's status file. Note that we do *not* store this 
	# information into the package database.
	$dlist = Fink::Status->list();
	foreach $pkgname (keys %$dlist) {
		$po = Fink::Package->package_by_name_create($pkgname);
		next if exists $po->{_versions}->{$dlist->{$pkgname}->{version}};
		$hash = $dlist->{$pkgname};

		# create dummy object
		if (@versions = parse_fullversion($hash->{version})) {
			$hash->{epoch} = $versions[0] if defined($versions[0]);
			$hash->{version} = $versions[1] if defined($versions[1]);
			$hash->{revision} = $versions[2] if defined($versions[2]);
			$hash->{type} = "dummy";
			$hash->{filename} = "";

			Fink::Package->inject_description($po, $hash);
		}
	}
	# Get data from VirtPackage.pm. Note that we do *not* store this 
	# information into the package database.
	$dlist = Fink::VirtPackage->list();
	foreach $pkgname (keys %$dlist) {
		$po = Fink::Package->package_by_name_create($pkgname);
		next if exists $po->{_versions}->{$dlist->{$pkgname}->{version}};
		$hash = $dlist->{$pkgname};

		# create dummy object
		if (@versions = parse_fullversion($hash->{version})) {
			$hash->{epoch} = $versions[0] if defined($versions[0]);
			$hash->{version} = $versions[1] if defined($versions[1]);
			$hash->{revision} = $versions[2] if defined($versions[2]);
			$hash->{type} = "dummy";
			$hash->{filename} = "";

			Fink::Package->inject_description($po, $hash);
		}
	}
	$have_packages = 1;

	printf "Information about %d packages read in %d seconds.\n", 
               scalar(values %$packages), (time - $time);
}

### scan for info files and compare to $db_mtime

sub search_comparedb {
	my $path = shift;
	$path .= "/";  # forces find to follow the symlink

	# Using find is much faster than doing it in Perl
	return
	  (grep !m{/(CVS|binary-$debarch)/},
	   `/usr/bin/find $path \\( -type f -or -type l \\) -and -name '*.info' -newer $basepath/var/db/fink.db`)
		 ? 1 : 0;
}

### read the packages and update the database, if needed and we are root

sub update_db {
	shift;	# class method - ignore first parameter
	my ($tree, $dir);

	# read data from descriptions
	print "Reading package info...\n";
	foreach $tree ($config->get_treelist()) {
		$dir = "$basepath/fink/dists/$tree/finkinfo";
		Fink::Package->scan($dir);
	}
	eval {
		require Storable; 
		if ($> == 0) {
			print "Updating package index... ";
			unless (-d "$basepath/var/db") {
				mkdir("$basepath/var/db", 0755) || die "Error: Could not create directory $basepath/var/db";
			}
			Storable::store ($packages, "$basepath/var/db/fink.db.tmp");
			rename "$basepath/var/db/fink.db.tmp", "$basepath/var/db/fink.db";
			print "done.\n";
		} else {
			&print_breaking( "\nFink has detected that your package cache is out of date and needs" .
				" an update, but does not have privileges to modify it. Please re-run fink as root," .
				" for example with a \"fink index\" command.\n" );
		}
	};
	$db_outdated = 0;
}

### scan one tree for package desccriptions

sub scan {
	shift;	# class method - ignore first parameter
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
		# fields that should be converted from multiline to
		# single-line
		for my $field ('builddepends', 'depends', 'files') {
			if (exists $properties->{$field}) {
				$properties->{$field} =~ s/[\r\n]+/ /gs;
				$properties->{$field} =~ s/\s+/ /gs;
			}
		}

		# If we want to allow the main package to see lang
		# vers, we need to replicate the parsing for
		# _langversion_pkg from PkgVersion::initialize here.

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
	shift;	# class method - ignore first parameter
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
	
	return $version;
}


1;
