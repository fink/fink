# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Package class
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2005 The Fink Package Manager Team
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
use Fink::Services qw(&read_properties &read_properties_var
		      &latest_version &version_cmp &parse_fullversion
		      &expand_percent);
use Fink::CLI qw(&get_term_width &print_breaking &print_breaking_stderr);
use Fink::Config qw($config $basepath $dbpath $debarch binary_requested);
use Fink::PkgVersion;
use Fink::FinkVersion;
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

=head1 NAME

Fink::Package - manipulate Fink package objects

=head1 DESCRIPTION

Fink::Package contains a variety of tools for querying, manipulating, and
navigating the Fink package database.

=head2 Functions

No functions are exported by default.  You should generally be getting
a package object by interacting with this module in an object-oriented
fashion:

  my $package = Fink::Package->package_by_name('PackageName');

=over 4

=cut

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

### Do not change API! This is used by FinkCommander (fpkg_list.pl)

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
	if (exists $self->{_versions}->{$version} 
		&& $self->{_versions}->{$version}->is_type('dummy') ) {
		$self->{_versions}->{$version}->merge($version_object);
	} else {
		# $pv->fullname is currently treated as unique, even though it won't be
		# if the version is the same but epoch isn't. So let's make sure.
		delete $self->{_versions}->{$version};
		my $fullname = $version_object->get_fullname();
		if (grep { $_->get_fullname() eq $fullname } $self->get_all_versions()) {
			die "The package full name '$fullname' is not allowed to be used"
			 ." more than once.";
		}
		
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

### Do not change API! This is used by FinkCommander (fpkg_list.pl)

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
	my @versions;

	@versions = values %{$self->{_versions}};
	push @versions, @{$self->{_providers}};
	return @versions;
}

# Are any of the package's providers installed?
sub is_provided {
	my $self = shift;
	my $pvo;

	foreach $pvo (@{$self->{_providers}}) {
		return 1 if $pvo->is_installed();
	}
	return 0;
}

### Do not change API! This is used by FinkCommander (fpkg_list.pl)

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

### Do not change API! This is used by FinkCommander (fpkg_list.pl)

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

### Do not change API! This is used by FinkCommander (fpkg_list.pl)

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

### Do not change API! This is used by FinkCommander (fpkg_list.pl)

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

### Do not change API! This is used by FinkCommander (fpkg_list.pl)

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

### Do not change API! This is used by FinkCommander (fpkg_list.pl)

sub require_packages {
	shift;	# class method - ignore first parameter

	if (!$have_packages) {
		Fink::Package->scan_all(@_);
	}
}

# set the aptgetable status of packages

sub update_aptgetable {
	my $class = shift; # class method
	my $statusfile = "$basepath/var/lib/dpkg/status";
	
	open APTDUMP, "$basepath/bin/apt-cache dump |"
		or die "Can't run apt-cache dump: $!";
		
	# Note: We assume here that the package DB exists already
	my ($po, $pv);
	while(<APTDUMP>) {
		if (/^\s*Package:\s*(\S+)/) {
			($po, $pv) = (Fink::Package->package_by_name($1), undef);
		} elsif (/^\s*Version:\s*(\S+)/) {
			$pv = $po->get_version($1) if defined $po;
		} elsif (/^\s+File:\s*(\S+)/) { # Need \s+ so we don't get crap at end
										# of apt-cache dump
			# Avoid using debs that aren't really apt-getable
			next if $1 eq $statusfile;
			
			$pv->set_aptgetable() if defined $pv;
		}
	}
	close APTDUMP;
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

	my $dbfile = "$dbpath/fink.db";
	my $conffile = "$basepath/etc/fink.conf";

	Fink::Package->forget_packages();
	
	# If we have the Storable perl module, try to use the package index
	if (-e $dbfile) {
		eval {
			require Storable; 

			# We assume the DB is up-to-date unless proven otherwise
			$db_outdated = 0;
		
			# Unless the NoAutoIndex option is set, check whether we should regenerate
			# the index based on its modification date and that of the package descs.
			if (not $config->param_boolean("NoAutoIndex")) {
				$db_mtime = (stat($dbfile))[9];			 
				if (((lstat($conffile))[9] > $db_mtime)
					or ((stat($conffile))[9] > $db_mtime)) {
					$db_outdated = 1;
				} else {
					$db_outdated = &search_comparedb( "$basepath/fink/dists" );
				}
			}
			
			# If the index is not outdated, we can use it, and thus save a lot of time
			if (not $db_outdated) {
				$packages = Storable::lock_retrieve($dbfile);
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

	if (&get_term_width) {
		printf STDERR "Information about %d packages read in %d seconds.\n", 
			scalar(values %$packages), (time - $time);
	}
}

### scan for info files and compare to $db_mtime

# returns true if any are newer than $db_mtime, false if not
sub search_comparedb {
	my $path = shift;
	$path .= "/";  # forces find to follow the symlink

	# Using find is much faster than doing it in Perl
	open NEWER_FILES, "/usr/bin/find $path \\( -type f -or -type l \\) -and -name '*.info' -newer $dbpath/fink.db |"
		or die "/usr/bin/find failed: $!\n";

	# If there is anything on find's STDOUT, we know at least one
	# .info is out-of-date. No reason to check them all.
	my $file_found = defined <NEWER_FILES>;

	close NEWER_FILES;

	return $file_found;
}

### read the packages and update the database, if needed and we are root

sub update_db {
	shift;	# class method - ignore first parameter
	my ($tree, $dir);

	my $dbfile = "$dbpath/fink.db";
	my $lockfile = "$dbpath/fink.db.lock";

	my $oldsig = $SIG{'INT'};
	$SIG{'INT'} = sub { unlink($lockfile); die "User interrupt.\n"  };

	# check if we should update index cache
	my $writable_cache = 0;
	eval "require Storable";
	if ($@) {
		my $perlver = sprintf '%*vd', '', $^V;
		&print_breaking_stderr( "Fink could not load the perl Storable module, which is required in order to keep a cache of the package index. You should install the fink \"storable-pm$perlver\" package to enable this functionality.\n" );
	} elsif ($> != 0) {
		&print_breaking_stderr( "Fink has detected that your package index cache is missing or out of date, but does not have privileges to modify it. Re-run fink as root, for example with a \"fink index\" command, to update the cache.\n" );
	} else {
		# we have Storable.pm and are root
		$writable_cache = 1;
	}

	# minutes to wait
	my $wait = 5;
	if (-f $lockfile) {
		# Check if we're already indexing.  If the index is less than 5 minutes old,
		# assume that there's another fink running and try to wait for it to finish indexing
		my $db_mtime = (stat($lockfile))[9];
		if ($db_mtime > (time - 60 * $wait)) {
			print STDERR "\nWaiting for another reindex to finish...";
			for (0 .. 60) {
				sleep $wait;
				if (! -f $lockfile) {
					print STDERR " done.\n";
					$packages = Storable::lock_retrieve($dbfile);
					$db_outdated = 0;
					return;
				}
			}
		}
	} else {
		open (FILEOUT, '>' . $lockfile);
		close (FILEOUT);
	}

	# read data from descriptions
	if (&get_term_width) {
		print STDERR "Reading package info...\n";
	}
	foreach $tree ($config->get_treelist()) {
		$dir = "$basepath/fink/dists/$tree/finkinfo";
		Fink::Package->scan($dir);
	}
	if (Fink::Config::binary_requested()) {
		Fink::Package->update_aptgetable();
	}
	
	if ($writable_cache) {
		if (&get_term_width) {
			print STDERR "Updating package index... ";
		}
		unless (-d $dbpath) {
			mkdir($dbpath, 0755) || die "Error: Could not create directory $dbpath: $!\n";
		}

		Storable::lock_store ($packages, "$dbfile.tmp");
		rename "$dbfile.tmp", $dbfile or die "Error: could not activate temporary file $dbfile.tmp: $!\n";
		print STDERR "done.\n";
	};

	$SIG{'INT'} = $oldsig if (defined $oldsig);
	unlink($lockfile);

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
			if (-f and not /^[\.\#]/ and /\.info$/) {
				push @filelist, $File::Find::fullname;
			}
		};
	find({ wanted => $wanted, follow => 1, no_chdir => 1 }, $directory);

	foreach $filename (@filelist) {
		# read the file and get the package name
		$properties = &read_properties($filename);
		$properties = Fink::Package->handle_infon_block($properties, $filename);
		next unless keys %$properties;
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

		Fink::Package->setup_package_object($properties, $filename);
	}
}

# Given $properties as a ref to a hash of .info lines in $filename,
# instantiate the package(s) and return an array of Fink::PkgVersion
# object(s) (i.e., the results of Fink::Package::inject_description().
sub setup_package_object {
	shift;	# class method - ignore first parameter
	my $properties = shift;
	my $filename = shift;

	my %pkg_expand;

	if (exists $properties->{type}) {
		if ($properties->{type} =~ /([a-z0-9+.\-]*)\s*\((.*?)\)/) {
			# if we were fed a list of subtypes, remove the list and
			# refeed ourselves with each one in turn
			my $type = $1;
			my @subtypes = split ' ', $2;
			if ($subtypes[0] =~ /^boolean$/i) {
				# a list of (boolean) has special meaning
				@subtypes = ('','.');
			}
			my @pkgversions;
			foreach (@subtypes) {
				# need new copy, not copy of ref to original
				my $this_properties = {%{$properties}};
				$this_properties->{type} =~ s/($type\s*)\(.*?\)/$type $_/;
				push @pkgversions, Fink::Package->setup_package_object($this_properties, $filename);
			};
			return @pkgversions;
		}
		# we have only single-value subtypes
#		print "Type: ",$properties->{type},"\n";
		my $type_hash = Fink::PkgVersion->type_hash_from_string($properties->{type},$filename);
		foreach (keys %$type_hash) {
			( $pkg_expand{"type_pkg[$_]"} = $pkg_expand{"type_raw[$_]"} = $type_hash->{$_} ) =~ s/\.//g;
		}
	}
#	print map "\t$_=>$pkg_expand{$_}\n", sort keys %pkg_expand;


	# store invariant portion of Package
	( $properties->{package_invariant} = $properties->{package} ) =~ s/\%type_(raw|pkg)\[.*?\]//g;
	if (exists $properties->{parent}) {
		# get parent's Package for percent expansion
		# (only splitoffs can use %N in Package)
		$pkg_expand{'N'}  = $properties->{parent}->{package};
		$pkg_expand{'n'}  = $pkg_expand{'N'};  # allow for a typo
	}
	# must always call expand_percent even if no Type or parent in
	# order to make sure Maintainer doesn't have bad % constructs
	$properties->{package_invariant} = &expand_percent($properties->{package_invariant},\%pkg_expand, "$filename \"package\"");

	# must always call expand_percent even if no Type in order to make
	# sure Maintainer doesn't have %type_*[] or other bad % constructs
	$properties->{package} = &expand_percent($properties->{package},\%pkg_expand, "$filename \"package\"");

	# get/create package object
	my $package = Fink::Package->package_by_name_create($properties->{package});

	# create object for this particular version
	$properties->{thefilename} = $filename;
	my $pkgversion = Fink::Package->inject_description($package, $properties);
	return ($pkgversion);
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
	if ($version->has_pkglist("Provides")) {
		foreach $vp (split(/\s*\,\s*/, $version->pkglist("Provides"))) {
			$vpo = Fink::Package->package_by_name_create($vp);
			$vpo->add_provider($version);
		}
	}
	
	return $version;
}

=item handle_infon_block

    my $properties = &read_properties($filename);
    $properties = &handle_infon_block($properties, $filename);

For the .info file lines processed into the hash ref $properties from
file $filename, deal with the possibility that the whole thing is in a
InfoN: block.

If so, make sure this fink is new enough to understand this .info
format (i.e., NE<lt>=max_info_level). If so, promote the fields of the
block up to the top level of %$properties and return a ref to this new
hash. Also set a _info_level key to N.

If an error with InfoN occurs (N>max_info_level, more than one InfoN
block, or part of $properties existing outside the InfoN block) print
a warning message and return a ref to an empty hash (i.e., ignore the
.info file).

=cut

sub handle_infon_block {
	shift;	# class method - ignore first parameter
	my $properties = shift;
	my $filename = shift;

	my($infon,@junk) = grep {/^info\d+$/i} keys %$properties;
	if (not defined $infon) {
		return $properties;
	}
	# file contains an InfoN block
	if (@junk) {
		print "Multiple InfoN blocks in $filename; skipping\n";
		return {};
	}
	unless (keys %$properties == 1) {
		# if InfoN, entire file must be within block (avoids
		# having to merge InfoN block with top-level fields)
		print "Field(s) outside $infon block! Skipping $filename\n";
		return {};
	}
	my ($info_level) = ($infon =~ /(\d+)/);
	my $max_info_level = &Fink::FinkVersion::max_info_level;
	if ($info_level > $max_info_level) {
		# make sure we can handle this InfoN
		print "Package description too new to be handled by this fink ($info_level>$max_info_level)! Skipping $filename\n";
		return {};
	}
	# okay, parse InfoN and promote it to the top level
	my $new_properties = &read_properties_var("$infon of \"$filename\"", $properties->{$infon});
	$new_properties->{infon} = $info_level;
	return $new_properties;
}


=back

=cut

1;
