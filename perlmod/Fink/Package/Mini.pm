# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Package::Mini class
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2004 The Fink Package Manager Team
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

package Fink::Package::Mini;
use Fink::Base;
use Fink::Config qw($basepath $config $debarch);
use Fink::CLI qw(&get_term_width);
use Fink::Package;
use Fink::Services qw(&latest_version);

use strict;
use warnings;

our $VERSION = 1.00;
our @ISA = qw(Fink::Base Fink::Package);

our $have_packages = 0;
our $packages_mini = {};
our $db_outdated   = 1;

END { }				# module clean-up code here (global destructor)


### constructor taking a name

### self-initialization

sub initialize {
	my $self = shift;

	$self->SUPER::initialize();

	$self->{_name} = $self->param_default("Package", "");
	$self->{_versions} = {};
	$self->{_virtual} = 1;
	$self->{_providers} = [];

	$packages_mini->{$self->{package}} = $self;
}

### get package name

sub get_name {
	my $self = shift;

	return $self->{_name};
}

### get pure virtual package flag

sub package_by_name {
	shift;
	my $pkgname = shift;
	$packages_mini->{$pkgname};
}
sub list_packages {
	shift;   # class method - ignore first parameter

	return keys %$packages_mini;
}
sub is_installed {
	my $package = shift;
	return $package->{is_installed};
}
sub is_any_installed {
	my $package = shift;
	return $package->{is_any_installed};
}
sub is_virtual {
	my $package = shift;
	return $package->{is_virtual};
}
sub get_builddependsonly {
	my $package = shift;
	return $package->{buildonly};
}
sub get_description {
	my $package = shift;
	return $package->{description};
}
sub get_maintainer {
	my $package = shift;
	return $package->{maintainer};
}
sub get_section {
	my $package = shift;
	return $package->{section};
}
sub get_tree {
	my $package = shift;
	return $package->{tree};
}
sub get_version {
	my $package = shift;
	return $package->{version};
}

sub require_packages {
	shift;	# class method - ignore first parameter

	if (!$have_packages) {
		Fink::Package::Mini->scan_all();
	}
}

sub forget_packages {
	shift;	# class method - ignore first parameter

	$have_packages = 0;
	%$packages_mini = ();
	$db_outdated = 1;
}


### read list of packages, either from cache or files

sub scan_all {
	shift;	# class method - ignore first parameter
	my ($time) = time;
	my ($db_mtime, $dbmini_mtime, $dlist, $pkgname, $po, $hash, $fullversion, @versions);

	Fink::Package::Mini->forget_packages();
	
	# If we have the Storable perl module, try to use the package index
	if (-e "$basepath/var/db/fink-list.db") {
		eval {
			require Storable; 

			# We assume the DB is up-to-date unless proven otherwise
			$db_outdated = 0;
		
			# Unless the NoAutoIndex option is set, check whether we should regenerate
			# the index based on its modification date and that of the package descs.
			if (not $config->param_boolean("NoAutoIndex")) {
				$db_mtime = (stat("$basepath/var/db/fink.db"))[9];
				$dbmini_mtime = (stat("$basepath/var/db/fink-list.db"))[9];
				if (((lstat("$basepath/etc/fink.conf"))[9] > $dbmini_mtime)
					or ((stat("$basepath/etc/fink.conf"))[9] > $dbmini_mtime)) {
					$db_outdated = 1;
				} elsif ($dbmini_mtime < $db_mtime) {
					$db_outdated = 1;
				} else {
					$db_outdated = &search_comparedb( "$basepath/fink/dists" );
				}
			}
			
			# If the index is not outdated, we can use it, and thus safe a lot of time
			 if (not $db_outdated) {
				$packages_mini = Storable::retrieve("$basepath/var/db/fink-list.db") if (-f "$basepath/var/db/fink-list.db");
			 }
		}
	}

	# Regenerate the DB if it is outdated
	if ($db_outdated) {
		Fink::Package::Mini->update_db();
	}

	$have_packages = 1;
}

### scan for info files and compare to $dbmini_mtime

sub search_comparedb {
	my $path = shift;
	$path .= "/";  # forces find to follow the symlink

	# Using find is much faster than doing it in Perl
	return
	  (grep !m{/(CVS|binary-$debarch)/},
	   `/usr/bin/find $path \\( -type f -or -type l \\) -and -name '*.info' -newer $basepath/var/db/fink-list.db`)
		 ? 1 : 0;
}


### read the packages and update the database, if needed and we are root

sub update_db {
	shift;	# class method - ignore first parameter
	my ($tree, $dir);

	my ($packagename, $package, $vo);
	foreach $packagename (Fink::Package->list_packages()) {
		$packages_mini->{$packagename} = {
			buildonly        => 0,
			description      => '',
			is_any_installed => 0,
			is_installed     => 0,
			is_virtual       => 0,
			maintainer       => '',
			section          => '',
			tree             => 'stable',
			version          => '',
		};
		bless($packages_mini->{$packagename}, 'Fink::Package::Mini');
		$package = Fink::Package->package_by_name($packagename);
		if ($package->is_virtual() == 1) {
			$packages_mini->{$packagename}->{description} = "[virtual package]";
			$packages_mini->{$packagename}->{is_virtual}  = 1;
		} else {
			$packages_mini->{$packagename}->{version} = &latest_version($package->list_versions());
			$vo = $package->get_version($packages_mini->{$packagename}->{version});
			if ($vo->is_installed()) {
				$packages_mini->{$packagename}->{is_installed} = 1;
			} elsif ($package->is_any_installed()) {
				$packages_mini->{$packagename}->{is_any_installed} = 1;
			}
			$packages_mini->{$packagename}->{description} = $vo->get_shortdescription();
			$packages_mini->{$packagename}->{buildonly}   = $vo->param_boolean("builddependsonly");
			$packages_mini->{$packagename}->{section}     = $vo->get_section($vo);
			$packages_mini->{$packagename}->{maintainer}  = $vo->param("maintainer");
			$packages_mini->{$packagename}->{tree}        = $vo->get_tree($vo);
		}
	}

	eval {
		require Storable; 
		if ($> == 0) {
			if (&get_term_width) {
				print STDERR "Updating 'fink list' index... "
			}
			unless (-d "$basepath/var/db") {
				mkdir("$basepath/var/db", 0755) || die "Error: Could not create directory $basepath/var/db";
			}
			Storable::lock_store ($packages_mini, "$basepath/var/db/fink-list.db.tmp") or die "couldn't store: $!\n";
			rename "$basepath/var/db/fink-list.db.tmp", "$basepath/var/db/fink-list.db";
			if (&get_term_width) {
				print STDERR "done.\n";
			}
		}
	};

	$db_outdated = 0;
}

1;
