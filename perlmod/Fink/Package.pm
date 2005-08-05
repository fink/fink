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
		      &expand_percent &lock_wait &store_rename);
use Fink::CLI qw(&get_term_width &print_breaking &print_breaking_stderr
				 &rejoin_text);
use Fink::Config qw($config $basepath $dbpath $debarch);
use Fink::Command qw(&touch &mkdir_p &rm_rf &rm_f);
use Fink::PkgVersion;
use Fink::FinkVersion;
use Fink::Shlibs;
use File::Find;
use File::Basename;
use Symbol qw();
use Fcntl qw(:mode);

use strict;
use warnings;

our $VERSION = 1.00;
our @ISA = qw(Fink::Base);

our $have_shlibs; # Have we loaded the shlibs?

our $packages = undef;		# The loaded packages (undef if unloaded)
our $valid_since = undef;	# The earliest time with the same DB as now

# Cache of essential packages
our @essential_packages = ();
our $essential_valid = 0;

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
		
		# noload
		if (grep { $_->get_fullname() eq $fullname } $self->get_all_versions(1)) {
			# avoid overhead of allocating for and storing the grep
			# results in if() since it's rare we'll need it
			my $msg = "A package name is not allowed to have the same ".
				"version-revision but different epochs: $fullname\n";
			foreach (
				grep { $_->get_fullname() eq $fullname } $self->get_all_versions(),
				$version_object
			) {
				my $infofile = $_->get_info_filename();
				$msg .= sprintf "  epoch %d\t%s\n", 
					$_->get_epoch(),
					length $infofile ? "fink virtual or dpkg status" : $infofile;
			};
			die $msg;
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
	my $noload = shift || 0;
	
	my @vers = values %{$self->{_versions}};
	map { $_->load_fields } @vers unless $noload;
	return @vers;
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
		return map { $_->load_fields } @match_list;
	} else {
		return map { $_->load_fields } @list;
	}
}

sub get_all_providers {
	my $self = shift;
	my $noload = shift || 0;
	my @versions;

	@versions = values %{$self->{_versions}};
	push @versions, @{$self->{_providers}};
	map { $_->load_fields } @versions unless $noload;
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
	my $noload = shift || 0;

	unless (defined($version) && $version) {
		return undef;
	}
	if (exists $self->{_versions}->{$version}) {
		my $pv = $self->{_versions}->{$version};
		$pv->load_fields unless $noload;
		return $pv;
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
			$vnode = $package->get_version($version, 1); # noload
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

=item require_packages

  Fink::Package->require_packages;

Load the package database into memory

=cut

sub require_packages {
	my $class = shift;
# 0 => both
# 1 => shlibs
# 2 => package
	$class->load_packages unless defined $packages;
#	if (!$have_shlibs && $oper != 2) {
#		Fink::Shlibs->scan_all(@_);
#	}
}

=item check_dbdirs

  my ($path, $fh, $new) = Fink::Package->check_dbdirs $write, $force_create;

Process the DB dirs. Returns the good directory found/created, and the lock
already acquired.

If $write is true, will create a new directory if one does not exist, and will
delete any old dirs.

If $force_create is true, will always create a new directory (invalidating any
previous PDB dirs).

=begin comment

When Fink uses a DB dir, it needs continued access to what's inside (since it
likely is using 'backed' PkgVersions). So when the DB is invalidated, we can't
just delete it.

Instead, we mark it as 'old' by creating a brand new DB dir. These dirs all
look like 'db.#', eg: db.1234, and the one that has the largest # is the
current one.

But how do we ever delete a DB dir? Each Fink gets a shared lock on its DB
dir; then if a DB dir is old and has no shared locks, it's no longer in use
and can be deleted.

=end comment

=cut

sub check_dbdirs {
	my ($class, $write, $force_create) = @_;
	
	# This directory holds multiple 'db.#' dirs
	my $multidir = "$dbpath/finkinfodb";
	
	# Special case: If the file "$multidir/invalidate" exists, it means
	# a shell script wants us to invalidate the DB
	my $inval = "$multidir/invalidate";
	if (-e $inval) {
		$force_create = 1;
		rm_f($inval) if $write;
	}
	
	# Get the db.# numbers in high-to-low order.
	my @nums;
	if (opendir MULTI, $multidir) {
		@nums = sort { $b <=> $a} map { /^db\.(\d+)$/ ? $1 : () } readdir MULTI;
	}
	# Find a number higher than all existing, for new dir
	my $higher = @nums ? $nums[0] + 1 : 1;
	my $newdir = "$multidir/db.$higher";
	
	# Get the current dir
	my @dirs = grep { -d $_ } map { "$multidir/db.$_" } @nums;
	my $use_existing = !$force_create && @dirs;
	my ($current, $fh);
	
	# Try to lock on an existing dir, if applicable
	if ($use_existing) {
		$current = $dirs[0];
		$fh = lock_wait("$current.lock", exclusive => 0, no_block => 1);
		# Failure ok, will try a new dir
	}
	
	# Use and lock a new dir, if needed
	if (!$fh) {
		$current = $newdir;
		if ($write) { # If non-write, it's just a fake new dir
			mkdir_p($multidir) unless -d $multidir;
			$fh = lock_wait("$current.lock", exclusive => 0, no_block => 1)
				or die "Can't make new DB dir $current: $!\n";
			mkdir_p($current);
		}
	}
		
	# Try to delete old dirs
	my @old = grep { $_ ne $current } @dirs;
	if ($write) {
		for my $dir (@old) {
			my $lock = "$dir.lock";
			if (my $fh = lock_wait($lock, exclusive => 1, no_block => 1)) {
				rm_rf($dir);
				rm_f($lock);
				close $fh;
			}
		}
	}
	
	return ($current, $fh);
}		

=item db_dir

  my $path = Fink::Package->db_dir $write;

Get the path to the directory that can store the Fink cached package database.
Creates it if it does not exist and $write is true.

=item forget_db_dir

  Fink::Package->forget_db_dir;

Forget the current DB directory.

=item is_new_db_dir

  my $bool = Fink::Package->is_new_db_dir;

Returns true if the current DB directory is new (as opposed to already used
and containing a DB).

=cut

{
	my $cache_db_dir = undef;
	my $cache_db_dir_fh = undef;

	sub db_dir {
		my $class = shift;
		my $write = shift || 0;
		
		unless (defined $cache_db_dir) {
			($cache_db_dir, $cache_db_dir_fh) =
				$class->check_dbdirs($write, 0);
		}
		return $cache_db_dir;
	}
	
	sub forget_db_dir {
		close $cache_db_dir_fh if $cache_db_dir_fh;
		($cache_db_dir, $cache_db_dir_fh) = (undef) x 2;
	}
	
	sub is_new_db_dir {
		my $class = shift;
		return !-f ($class->db_dir . "/used");
	}
}

=item db_index

  my $path = Fink::Package->db_index;

Get the path to the file that can store the Fink global database index.

=cut

sub db_index {
	my $class = shift;
	return "$dbpath/index.db";
}


=item db_lockfile

  my $path = Fink::Package->db_lockfile;

Get the path to the pdb lock file.

=cut

sub db_lockfile {
	my $class = shift;
	return $class->db_index . ".lock";
}


=item db_proxies

  my $path = Fink::Package->db_proxies;

Get the path to the quick-startup cache of the proxy-db.

=cut

sub db_proxies {
	my $class = shift;
	return "$dbpath/proxies.db";
}


=item search_comparedb

  Fink::Package->search_comparedb;

Checks if any .info files are newer than the on-disk package database cache.
Returns true if the cache is out of date.

Note that in several cases, this can miss changes. For example, a .info file
older than the PDB cache that is moved into the dists will not be found.

=cut

sub search_comparedb {
	my $class = shift;
	my $path = "$basepath/fink/dists/";  # extra '/' forces find to follow the symlink
	
	my $dbfile = $class->db_proxies;
	return 1 if -M $dbfile > -M "$basepath/etc/fink.conf";

	# Using find is much faster than doing it in Perl
	my $prune_bin = "\\( -name 'binary-$debarch' -prune \\)";
	my $file_test = "\\( \\( -type f -o -type l \\) -name '*.info' \\)";
	my $cmd = "/usr/bin/find $path \\! $prune_bin \\( $file_test -o -type d \\) "
		. " -newer $dbfile";
	open NEWER_FILES, "$cmd |" or die "/usr/bin/find failed: $!\n";

	# If there is anything on find's STDOUT, we know at least one
	# .info is out-of-date. No reason to check them all.
	my $file = <NEWER_FILES>;
	my $file_found = defined $file;

	close NEWER_FILES;

	return $file_found;
}


=item forget_packages

  Fink::Package->forget_packages;
  Fink::Package->forget_packages $options;

Removes the package database from memory. The hash-ref $options can contain the
following keys:

=over 4

=item disk

If B<disk> is present and true, in addition to removing the package database
from memory, any on-disk cache is removed as well. This option defaults to
false and should be used sparingly.

=back

=cut

sub forget_packages {
	my $class = shift;
	my $optarg = shift || {};
	if (ref($optarg) ne 'HASH') {
		die "There's a new API for forget_packages, please use it, I won't "
			. "change it again.\n";
	}
	my %opts = (disk => 0, %$optarg);
	
	$packages = undef;
	@essential_packages = ();
	$essential_valid = 0;
	%Fink::PkgVersion::shared_loads = ();
	$valid_since = undef;
	
	if ($opts{disk} && $> == 0) {	# Only if we're root
		my $lock = lock_wait($class->db_lockfile, exclusive => 1,
			desc => "another Fink's indexing");
		
		# Create a new DB dir (possibly deleting the old one)
		$class->forget_db_dir();
		$class->check_dbdirs(1, 1);
		
		rm_f($class->db_index);
		rm_f($class->db_proxies);
		close $lock if $lock;
	}
}

=item load_packages

  Fink::Package->load_packages;

Load the package database, updating any on-disk cache if necessary and 
possible.

=cut

sub load_packages {
	my $class = shift;
	my ($time) = time;

	$class->update_db();
	$class->insert_runtime_packages;

	if (&get_term_width) {
		printf STDERR "Information about %d packages read in %d seconds.\n", 
			scalar(values %$packages), (time - $time);
	}
}


=item can_read_write_db

  my ($read, $write) = Fink::Package->can_read_write_db;

Determines whether Fink can read or write the package database cache.

=cut

sub can_read_write_db {
	my $class = shift;
	
	my ($read, $write) = (1, 0);
	
	eval "require Storable";
	if ($@) {
		my $perlver = sprintf '%*vd', '', $^V;
		&print_breaking_stderr( "Fink could not load the perl Storable module, which is required in order to keep a cache of the package index. You should install the fink \"storable-pm$perlver\" package to enable this functionality.\n" );
		$read = 0;
	} elsif ($> != 0) {
	} else {
		$write = 1;
	}
	
	return ($read, $write);
}

=item update_index

  my $fidx = Fink::Package->update_index $fidx, $info, @pvs;

Update the package index $idx with the results of loading PkgVersions @pvs from
.info file $info.

Returns the new index item for the .info file.

=cut

sub update_index {
	my ($class, $idx, $info, @pvs) = @_;
	
	# Always use a new file, so an old fink doesn't accidentally read a newer
	# file in the same place.
	
	# TODO: This leaves old cache files sitting around, perhaps if the atime
	# gets old enough we should delete them?
	my $cidx = $idx->{next_idx}++;

	# Split things into dirs
	my $dir = sprintf "%03d00", $cidx / 100;		
	my $cache = $class->db_dir . "/$dir/$cidx";

	my %new_idx = (
		inits => { map { $_->get_fullname => $_->get_init_fields } @pvs },
		cache => $cache,
		info_mtime => (stat($info))[9] || 0,
	);
	
	return ($idx->{infos}{$info} = \%new_idx);
}	

=item pass1_update

  Fink::Package->pass1_update $ops, $idx, $infos;

Load any .info files whose cache isn't up to date and available for reading.
If $ops{write} is true, update the cache as well.

=cut

sub pass1_update {
	my ($class, $ops, $idx, @infos) = @_;
		
	my $uncached = 0;
	my $noauto = $config->param_boolean("NoAutoIndex");
	
	for my $info (@infos) {
		my $load = 0;
		my $fidx = $idx->{infos}{$info};
		
		# Do we need to load?
		$load = 1 if $ops->{load} && !$ops->{read}; # Can't read it, must load
		
		# Check if it's cached
		if (!$load) {
			unless (defined $fidx) {
				$load = 1;
			} elsif (!$noauto) {
				$load = 1 if !-f $fidx->{cache}
					|| $fidx->{info_mtime} < (stat($info))[9];
			}
		}
		
		unless ($load) {
#			print "Not reading: $info\n";
			next;
		}
#		print "Reading: $info\n";
		
		# Print a nice message
		if ($uncached == 0 && &get_term_width) {
			if ($> != 0) {
				print_breaking_stderr rejoin_text <<END;
Fink has detected that your package index cache is missing or out of date, but
does not have privileges to modify it. Re-run fink as root, for example with a
\"fink index\" command, to update the cache.\n
END
			}				
			print STDERR "Reading package info...";
			$uncached = 1;
		}
		
		# Load the file
		my @pvs = $class->packages_from_info_file($info);
		map { $_->_disconnect } @pvs;	# Don't keep obj references
		
		# Update the index
		$fidx = $class->update_index($idx, $info, @pvs);
		
		# Turn it into a storable format, and cache it
		my %store = map { $_->get_fullname => $_ } @pvs;
		$Fink::PkgVersion::shared_loads{$fidx->{cache}} = \%store;
		
		# Update the cache
		if ($ops->{write}) {
			my $dir = dirname $fidx->{cache};
			mkdir_p($dir) unless -d $dir;
			
			touch($class->db_dir . "/used"); # No longer clean
			unless (store_rename(\%store, $fidx->{cache})) {
				delete $idx->{infos}{$info};
			}
		}
	}
	
	# Finish up;
	if ($uncached) {		
		if ($ops->{write}) {
			store_rename($idx, $class->db_index);
		}
		print_breaking_stderr("done.") if &get_term_width;
	}
}

=item pass3_insert

  my $success = Fink::Package->pass3_insert $idx, @infos;

Ensure that the .info files @infos are loaded and inserted into the PDB.
Information about the .info files is to be found in the index $idx..

=cut

sub pass3_insert {
	my ($class, $idx, @infos) = @_;
		
	for my $info (@infos) {
		my @pvs;
					
		my $fidx = $idx->{infos}{$info};
		my $cache = $fidx->{cache};
			
		@pvs = map { Fink::PkgVersion->new_backed($cache, $_) }
			values %{ $fidx->{inits} };
		
		$class->insert_pkgversions(@pvs);
	}
	
	return 1;
}

=item get_all_infos

  my @infos = Fink::Package->get_all_infos;

Get a list of all the .info files. Returns an array of paths to the .info
files.

=cut

sub get_all_infos {
	my $class = shift;
	
	return map { $class->tree_infos($_) } $config->get_treelist();
}

=item update_db

  Fink::Package->update_db %options;

Updates the on-disk package database cache if possible. Options is a hash, where
the following elements are valid:

=over 4

=item no_load

If B<no_load> is present and true, the current package database will not be read
in to memory, but will only be updated.

=item no_fastload

If B<no_fastload> is present and true, the fast-load cache will not be used,
instead all the .info files will be scanned (but not necessarily read). The
main cache will still be used.

=back

=cut

sub update_db {
	my $class = shift;
	my %options = @_;
	my $load = !$options{no_load};
	my $try_cache = !$options{no_fastload};
	
	my %ops = ( load => $load );
	@ops{'read', 'write'} = $class->can_read_write_db;
	# If we can't write and don't want to load, what's the point?
	return if !$ops{load} && !$ops{write}; 
	
	# Get the lock
	my $lock = 0;
	if ($ops{write} || $ops{read}) {
		$lock = lock_wait($class->db_lockfile, exclusive => $ops{write},
			desc => "another Fink's indexing");
		unless ($lock) {
			if ($! !~ /no such file/i && $> == 0) { # Don't warn if just no perms
				&print_breaking_stderr("Warning: Package index cache disabled because cannot access indexer lockfile: $!");
			}
			@ops{'read', 'write'} = (0, 0);
			return unless $ops{load};
		}
	}
	if (!$ops{write}) {	# If reading, we just wanted to wait, we don't really
		close $lock if $lock;	# need to keep the lock.
		$lock = 0;
	}
	
	# Get the cache dir; also notifies fink that the PDB is in use
	my $dbdir = $class->db_dir($ops{write});
	
	# Can we use the index? Definitely not if we have a whole new db_dir.
	my $idx_ok = ($ops{read} || $ops{write}) && !$class->is_new_db_dir();
	
	# Can we use the proxy DB?
	my $proxy_ok = $idx_ok && $try_cache && -r $class->db_proxies;
	# Proxy must be newer, otherwise it could be out of date from a load-only
	$proxy_ok &&= (-M $class->db_proxies < (-M $class->db_index || 0));
	$proxy_ok &&= !$class->search_comparedb
		unless $config->param_boolean("NoAutoIndex");
	
	if ($proxy_ok) {
		# Just use the proxies
		$valid_since = (stat($class->db_proxies))[9];
		eval { $packages = Storable::lock_retrieve($class->db_proxies); };
		if ($@ || !defined $packages) {
			die "It appears that part of Fink's package database is corrupted. "
				. "Please run 'fink index' to correct the problem.\n";
		}
		close $lock if $lock;
	} else {
		rm_f($class->db_proxies); # Probably not valid anymore
		
		# Load the index
		$valid_since = time;
		my $idx;
		if ($idx_ok) {
			eval { $idx = Storable::lock_retrieve($class->db_index); };
			if ($@ || !defined $idx) {
				close $lock if $lock;
				# Try to force a re-gen next time
				$class->forget_packages({ disk => 1 });
				die "It appears that Fink's package database is corrupted. "
					. "Please run 'fink index -f' to recreate it.\n";
			}
		} else {
			$idx = { infos => { }, 'next' => 1, };
		}
		
		# Get the .info files
		my @infos = $class->get_all_infos;
		
		# Pass 1: Load outdated infos
		$class->pass1_update(\%ops, $idx, @infos);
		close $lock if $lock;
		return unless $ops{load};
		
		# Pass 2: Scan for files to load: Last one reached for each fullname
		my %name2latest;
		for my $info (@infos) {
			my @fullnames = keys %{ $idx->{infos}{$info}{inits} };
			@name2latest{@fullnames} = ($info) x scalar(@fullnames);
		}
		my %loadinfos = map { $_ => 1} values %name2latest;	# uniqify
		my @loadinfos = keys %loadinfos;
		
		# Pass 3: Load and insert the .info files
		$class->pass3_insert($idx, @loadinfos);
		
		# Store the proxy db
		if ($ops{write}) {
			store_rename($packages, $class->db_proxies);
		}
	}		
} 

=item db_valid_since

  my $time = Fink::Package->db_valid_since;

Get earliest time (in seconds since the epoch) at which the DB is known to be
exactly the same as now. This allows clients to cache the contents of the DB,
only reloading if $cache_time < Fink::Package->db_valid_since;

=cut

sub db_valid_since {
	my $class = shift;
	return $valid_since;
}

=item tree_infos

  my @files = tree_infos $treename;

Get the full pathnames to all the .info files in a Fink tree.

=cut

sub tree_infos {
	my $class = shift;
	my $treename = shift;
	
	my $treedir = "$basepath/fink/dists/$treename/finkinfo";
	return () unless -d $treedir;

	my @filelist = ();
	my $wanted = sub {
		if (-f _ and not /^[\.\#]/ and /\.info$/) {
			push @filelist, $File::Find::fullname;
		}
	};
	find({ wanted => $wanted, follow => 1, no_chdir => 1 }, $treedir);
	
	return @filelist;
}		


=item packages_from_info_file

  my @packages = Fink::Package->packages_from_info_file $filename;

Create Fink::PkgVersion objects based on a .info file. Do not
yet add these packages to the current package database.

Returns all packages created, including split-offs.

=cut

sub packages_from_info_file {
	my $class = shift;
	my $filename = shift;
	
	# read the file and get the package name
	my $properties = &read_properties($filename);
	$properties = $class->handle_infon_block($properties, $filename);
	return () unless keys %$properties;
	
	my $pkgname = $properties->{package};
	unless ($pkgname) {
		print_breaking_stderr "No package name in $filename";
		next;
	}
	unless ($properties->{version}) {
		print_breaking_stderr "No version number for package $pkgname in $filename";
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

	return $class->packages_from_properties($properties, $filename);
}


=item insert_runtime_packages

  Fink::Package->insert_runtime_packages;

Add all packages to the database which are dynamically generated, rather than
created from .info files.

=cut

sub insert_runtime_packages {
	my $class = shift;
	
	# Get data from dpkg's status file. Note that we do *not* store this 
	# information into the package database.
	$class->insert_runtime_packages_hash(Fink::Status->list());

	# Get data from VirtPackage.pm. Note that we do *not* store this 
	# information into the package database.
	$class->insert_runtime_packages_hash(Fink::VirtPackage->list());
}

=item insert_runtime_package_hash

  Fink::Package->insert_runtime_package_hash $hashref;

Given a hash of package-name => property-list, insert the packages into the
in-memory database.

=cut

sub insert_runtime_packages_hash {
	my $class = shift;
	
	my $dlist = shift;
	foreach my $pkgname (keys %$dlist) {
		my $po = $class->package_by_name_create($pkgname);
		next if exists $po->{_versions}->{$dlist->{$pkgname}->{version}};
		my $hash = $dlist->{$pkgname};

		# create dummy object
		if (my @versions = parse_fullversion($hash->{version})) {
			$hash->{epoch} = $versions[0] if defined($versions[0]);
			$hash->{version} = $versions[1] if defined($versions[1]);
			$hash->{revision} = $versions[2] if defined($versions[2]);
			$hash->{type} = "dummy";
			$hash->{filename} = "";

			$class->insert_pkgversions($class->packages_from_properties($hash));
		}
	}
}

=item packages_from_properties

  my $properties = { field => $val, ... };
  my @packages = Fink::Package->packages_from_properties $properties, $filename;

Create Fink::PkgVersion objects based on a hash-ref of properties. Do not
yet add these packages to the current package database.

Returns all packages created, including split-offs if this is a parent package.

=cut

sub packages_from_properties {
	my $class = shift;
	my $properties = shift;
	my $filename = shift || "";

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
				push @pkgversions,
					$class->packages_from_properties($this_properties, $filename);
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
	if (exists $properties->{parent_obj}) {
		# get parent's Package for percent expansion
		# (only splitoffs can use %N in Package)
		$pkg_expand{'N'}  = $properties->{parent_obj}->{package};
		$pkg_expand{'n'}  = $pkg_expand{'N'};  # allow for a typo
	}
	# must always call expand_percent even if no Type or parent in
	# order to make sure Maintainer doesn't have bad % constructs
	$properties->{package_invariant} = &expand_percent($properties->{package_invariant},\%pkg_expand, "$filename \"package\"");

	# must always call expand_percent even if no Type in order to make
	# sure Maintainer doesn't have %type_*[] or other bad % constructs
	$properties->{package} = &expand_percent($properties->{package},\%pkg_expand, "$filename \"package\"");

	# create object for this particular version
	$properties->{thefilename} = $filename if $filename;
	
	my $pkgversion = Fink::PkgVersion->new_from_properties($properties);
	
	# Only return splitoffs for the parent. Otherwise, PkgVersion::add_splitoff
	# goes crazy.
	if ($pkgversion->has_parent) { # It's a splitoff
		return ($pkgversion);
	} else {								# It's a parent
		return $pkgversion->get_splitoffs(1, 1);
	}
}

=item insert_pkgversions

  Fink::Package->insert_pkgversions @pkgversions;

Insert a list of Fink::PkgVersion into the current in-memory package database.

=cut

sub insert_pkgversions {
	my $class = shift;
	my @pvs = @_;
	
	for my $pv (@pvs) {
		# get/create package object
		my $po = $class->package_by_name_create($pv->get_name);
	
		# link them together
		$po->add_version($pv);

		# track provided packages
		if ($pv->has_pkglist("Provides")) {
			foreach my $vp (split(/\s*\,\s*/, $pv->pkglist("Provides"))) {
				my $vpo = $class->package_by_name_create($vp);
				$vpo->add_provider($pv);
			}
		}
	}
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
		print_breaking_stderr "Multiple InfoN blocks in $filename; skipping";
		return {};
	}
	unless (keys %$properties == 1) {
		# if InfoN, entire file must be within block (avoids
		# having to merge InfoN block with top-level fields)
		print_breaking_stderr "Field(s) outside $infon block! Skipping $filename";
		return {};
	}
	my ($info_level) = ($infon =~ /(\d+)/);
	my $max_info_level = &Fink::FinkVersion::max_info_level;
	if ($info_level > $max_info_level) {
		# make sure we can handle this InfoN
		print_breaking_stderr "Package description too new to be handled by this fink ($info_level>$max_info_level)! Skipping $filename";
		return {};
	}
	
	# okay, parse InfoN and promote it to the top level
	my $new_properties = &read_properties_var("$infon of \"$filename\"",
		$properties->{$infon}, { remove_space => ($info_level >= 3) });
	$new_properties->{infon} = $info_level;
	return $new_properties;
}

=back

=cut

1;
