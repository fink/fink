# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::PkgVersion class
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2016 The Fink Package Manager Team
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
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110, USA.
#

package Fink::PkgVersion;
use Fink::Base;
use Fink::Services qw(&filename &execute
					  &expand_percent &expand_percent2 &latest_version
					  &collapse_space &read_properties &read_properties_var
					  &pkglist2lol &lol2pkglist &cleanup_lol
					  &version_cmp
					  &get_system_perl_version
					  &get_path &eval_conditional &enforce_gcc
					  &dpkg_lockwait &aptget_lockwait &lock_wait
					  &store_rename &apt_available
					  &is_accessible);
use Fink::CLI qw(&print_breaking &print_breaking_stderr &rejoin_text
				 &prompt_boolean &prompt_selection
				 &should_skip_prompt &die_breaking);
use Fink::Config qw($config $basepath $libpath $buildpath
					$dbpath $ignore_errors);
use Fink::FinkVersion qw(&get_arch);
use Fink::NetAccess qw(&fetch_url_to_file);
use Fink::Mirror;
use Fink::Package;
use Fink::Status;
use Fink::VirtPackage;
use Fink::Bootstrap qw(&get_bsbase);
use Fink::Command qw(cp mkdir_p rm_f rm_rf symlink_f du_sk chowname chowname_hr touch);
use Fink::Notify;
use Fink::Validation qw(validate_dpkg_unpacked);
use Fink::Text::DelimMatch;
use Fink::Text::ParseWords qw(&parse_line);
use Fink::Checksum;

use POSIX qw(uname strftime);
use Hash::Util;
use File::Basename qw(&dirname &basename);
use Carp qw(confess);
use File::Temp qw(tempdir);
use Fcntl;
use Storable;
use IO::Handle;
use version 0.77;	

use strict;
use warnings;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
	$VERSION	 = 1.00;
	@ISA		 = qw(Exporter Fink::Base);
	@EXPORT		 = qw();
	@EXPORT_OK	 = qw();	# eg: qw($Var1 %Hashit &func3);
	%EXPORT_TAGS = ( );		# eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

our %perl_archname_cache;

# Hold the trees of packages that we've built, so we can scan them
our %built_trees;

END {
	scanpackages();
}

=head1 NAME

Fink::PkgVersion - a single version of a package

=head1 DESCRIPTION

=head2 Methods

=over 4

=item new_backed

  my $pv = Fink::PkgVersion->new_backed $file, $hashref;

Create a disk-backed PkgVersion, with initial properties from $hashref.
Other properties will be loaded as needed from $file.

Note that this constructor does B<not> initialize the PkgVersion, since it
already has an initialized object on-disk.


B<WARNING:>

When a PkgVersion object is created with new_backed, the first access to the
object MUST be with one of these methods:

  Package: get_version, get_all_versions, get_matching_versions, get_all_providers
  PkgVersion: get_parent, get_splitoffs, parent_splitoffs

Many of these methods take a $noload flag to allow callers to disable loading.
This should only be done rarely, when the caller is CERTAIN that no unloaded
fields will be used and when it results in many fewer loads. There should be
always be a comment nearby with the text 'noload'.

In addition, the following fields should be accessed exclusively through
accessors:

  Package: _providers, _versions
  PkgVersion: _splitoffs_obj, parent_obj

=cut

sub new_backed {
	my ($proto, $file, $init) = @_;
	my $class = ref($proto) || $proto;

	$init->{_backed_file} = $file;
	$init->{_backed_loaded} = 0;
	return bless $init, $class;
}

# Are we loaded?
sub _is_loaded {
	my $self = shift;
	return !$self->has_param('_backed_file') || $self->param('_backed_loaded');
}

=item load_fields

  my $same_pv = $pv->load_fields;

Load any unloaded fields into this PkgVersion object. Loads are shared among
different PkgVersion objects. Returns this object.

=for private

load_fields must always be called, even for newly-created objects. We
set some fields here that are runtime-dependent, which needs to happen
even for packages that aren't cached.

=cut

our %shared_loads;

{
	# Some things we don't want to load, if we'd rather keep what's already in
	# the database.
	my %dont_load = map { $_ => 1 } qw(_full_trees);

	sub load_fields {
		my $self = shift;
		return $self if $self->_is_loaded;

		$self->set_param('_backed_loaded', 1);
		my $file = $self->param('_backed_file');
		my $loaded;
		if (exists $shared_loads{$file}) {
#			print "Sharing PkgVersion " . $self->get_fullname . " from $file\n";
			$loaded = $shared_loads{$file};
		} else {
#			print "Loading PkgVersion " . $self->get_fullname . " from: $file\n";
			eval {
				local $SIG{INT} = 'IGNORE'; # No user interrupts
				$loaded = Storable::retrieve($file);
			};
			if ($@ || !defined $loaded) {
				die "It appears that part of Fink's package database is corrupted "
					. "or missing. Please run 'fink index' to correct the "
					. "problem.\n";
			}
			$shared_loads{$file} = $loaded;
		}

		return $self unless exists $loaded->{$self->get_fullname};

		# Insert the loaded fields
		my $href = $loaded->{$self->get_fullname};
		my @load_keys = grep { !exists $dont_load{$_} } keys %$href;
		@$self{@load_keys} = @$href{@load_keys};

		# We need to update %d, %D, %i and %I to adapt to changes in buildpath
		$self->_set_destdirs;

		if (Fink::Config::get_option("tests")) {
			$self->activate_infotest;
		}

		return $self;
	}
}

# PRIVATE: $pv->_set_destdirs
# (Re)set the destination (install) directories for this package.
# This is necessary for loading old finkinfodb caches, and for recovering
# from bootstrap mode.
sub _set_destdirs {
	my $self = shift;

	my $destdir = $self->get_install_directory();
	my $pdestdir = $self->has_parent()
		? $self->get_parent()->get_install_directory()
		: $destdir;
	my %entries = (
		'd' => $destdir,			'D' => $pdestdir,
		'i' => $destdir.$basepath,	'I' => $pdestdir.$basepath,
	);
	@{$self->{_expand}}{keys %entries} = values %entries;
	$self->prepare_percent_c;
}

=item get_init_fields

  my $hashref = $pv->get_init_fields;

Get the minimum fields necessary for inserting a PkgVersion.

=cut

{
	# Fields required to add a package to $packages
	my @keepfields = qw(_name _epoch _version _revision _filename
		_pkglist_provides essential _full_trees);

	sub get_init_fields {
		my $self = shift;

		return {
			map { exists $self->{$_} ? ( $_ => $self->{$_} ) : () }
				@keepfields
		};
	}
}

=item handle_infon_block

    my $properties = &read_properties($filename);
    ($properties, $info_level) =
    	Fink::PkgVersion->handle_infon_block($properties, $filename);

For the .info file lines processed into the hash ref $properties from
file $filename, deal with the possibility that the whole thing is in a
InfoN: block.

If so, make sure this fink is new enough to understand this .info
format (i.e., NE<lt>=max_info_level). If so, promote the fields of the
block up to the top level of %$properties and return a ref to this new
hash. If called in a scalar context, the InfoN level is returned in
the "infon" field of the $properties hash. If called in an array
context, the InfoN level (or 1 if not an InfoN construct) is returned
as the second element.

If an error with InfoN occurs (N>max_info_level, more than one InfoN
block, or part of $properties existing outside the InfoN block) print
a warning message and return a ref to an empty hash (i.e., ignore the
.info file).

=cut

# must be class method because it controls if/how to parse a .info
# file, so not enough data would be known yet to create a PV object
sub handle_infon_block {
	shift;	# class method - ignore first parameter
	my $properties = shift;
	my $filename = shift;

	my($infon,@junk) = grep {/^info\d+$/i} keys %$properties;
	if (not defined $infon) {
		wantarray ? return $properties, 1 : return $properties;
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
	return ($new_properties, $info_level);
}

=item pkgversions_from_properties

  my $properties = { field => $val, ... };
  my @packages = Fink::Package->pkgversions_from_properties
   					$properties, %options;

Create Fink::PkgVersion objects based on a hash-ref of properties. Do not
yet add these packages to the current package database.

Returns all packages created, including split-offs if this is a parent package.

Options are info_level and filename, and optionally parent.

The option "no_exclusions", if true, will cause the packages to be
created even if an Architcture field setting would normally disable
them.

=cut

sub pkgversions_from_properties {
	my $class = shift;
	my $properties = shift;
	my %options = @_;
	my $filename = $options{filename} || "";

	# Handle variant types
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
					$class->pkgversions_from_properties($this_properties, %options);
			};
			return @pkgversions;
		}

		# we have only single-value subtypes
#		print "Type: ",$properties->{type},"\n";
	}

	# create object for this particular version
	my $pkgversion = $class->new_from_properties($properties, %options);
	return () unless exists $pkgversion->{package};  # trap instantiation failures

	# Handle Architecture and Distribution fields. We should do this before
	# instantiating the PV objects, but that would mean having to
	# parse the Type field another time in order to get %-exp map.
	if ($pkgversion->has_param('architecture')) {
		# Syntax is like a package-list, so piggy-back on those fields' parser
		my $pkg_arch = $pkgversion->pkglist('architecture');

		# always call pkglist(architecture) even if no_exclusions so
		# that we get error-checking on the field
		if (not $options{no_exclusions}) {
			my $sys_arch = $config->param('Architecture');
			if (defined $pkg_arch and $pkg_arch !~ /(\A|,)\s*$sys_arch\s*(,|\Z)/) {
				# Discard the whole thing if local arch not listed
				return ();
			}
		}
	}

	if ($pkgversion->has_param('distribution')) {
		# Syntax is like a package-list, so piggy-back on those fields' parser
		my $pkg_dist = $pkgversion->pkglist('distribution');

		# always call pkglist(distribution) even if no_exclusions so
		# that we get error-checking on the field
		if (not $options{no_exclusions}) {
			my $sys_dist = $config->param('Distribution');
			if (defined $pkg_dist and $pkg_dist !~ /(\A|,)\s*$sys_dist\s*(,|\Z)/) {
				# Discard the whole thing if local dist not listed
				return ();
			}
		}
	}

	# Only return splitoffs for the parent. Otherwise, PkgVersion::add_splitoff
	# goes crazy.
	if ($pkgversion->has_parent) { # It's a splitoff
		return ($pkgversion);
	} else {								# It's a parent
		return $pkgversion->get_splitoffs(1, 1);
	}
}

=item pkgversions_from_info_file

  my @packages = Fink::Package->pkgversions_from_info_file $filename;
  my @packages = Fink::Package->pkgversions_from_info_file $filename, %options;

Create Fink::PkgVersion objects based on a .info file. Do not
yet add these packages to the current package database.

Returns all packages created, including split-offs.

Any given %options are passed to pkgversions_from_properties, except
for "filename" and "info_level", which are over-written.

=cut

sub pkgversions_from_info_file {
	my $class = shift;
	my $filename = shift;
	my %options = @_;

	# read the file and get the package name
	my $properties = &read_properties($filename);
	my $info_level;
	($properties, $info_level) = $class->handle_infon_block($properties, $filename);
	return () unless keys %$properties;

	my $pkgname = $properties->{package};
	unless ($pkgname) {
		print_breaking_stderr "\nNo package name in $filename";
		return ();
	}
	unless ($properties->{version}) {
		print_breaking_stderr "\nNo version number for package $pkgname in $filename";
		return ();
	}

	%options = (%options,
				filename => $filename,
				info_level => $info_level
			   );

	return $class->pkgversions_from_properties($properties, %options);
}

=item one_pkgversion_from_info_file

  my $pv = Fink::Package->one_pkgversion_from_info_file $filename;
  my @pvs = Fink::Package->one_pkgversion_from_info_file $filename;

Convenience method to get a single Fink::PkgVersion object from a .info
file. Does B<not> return splitoffs, only parents.

If the .info file uses variants, multiple objects will be returned. By
capturing just one, information may be lost, but at least the caller will
have a useful parent object.

=cut

sub one_pkgversion_from_info_file {
	my $class = shift;
	my $filename = shift;
	my @pvs = $class->pkgversions_from_info_file($filename);
	@pvs = grep { ! $_->has_parent() } @pvs;
	return wantarray ? @pvs : $pvs[-1];
}


=item initialize

  $pv->initialize(%options);

I<Protected method, do not call directly>.

Object initializer as specified in Fink:::Base.

The following elements may be in the options-hash for the
new_from_properties constructor.

=over 4

=item filename

The name of the file from which this PkgVersion's properties were read.
Omission of this option is strongly discouraged.

=item info_level

The level of the package description syntax used to describe this PkgVersion,
ie: the InfoN field. Omission of this option is strongly discouraged.

=item parent_obj

The parent PkgVersion of this package, if it has one.

=back

=cut

sub initialize {
	my $self = shift;
	my %options = (info_level => 1, filename => "", @_);

	my ($pkgname, $epoch, $version, $revision, $fullname);
	my ($source, $type_hash);
	my ($depspec, $deplist, $dep, $expand, $destdir);
	my ($parentpkgname, $parentdestdir, $parentinvname);
	my ($i, $path, @parts, $finkinfo_index, $section, @splitofffields);

	$self->SUPER::initialize();

	# handle options
	for my $opt (qw(info_level filename)) {
		### Do not change meaning of _filename! This is used by FinkCommander (fpkg_list.pl)
		$self->{"_$opt"} = $options{$opt};
	}
	my $filename = $options{filename};

	# set parent
	$self->{parent_obj} = $options{parent_obj} if exists $options{parent_obj};


	### Handle types

	# Setup restricted expansion hash. NOTE: multivalue lists were already cleared
	$expand = { };
	$self->{_type_hash} = $type_hash = $self->type_hash_from_string($self->param_default("Type", ""), $self->{_filename});
	foreach (keys %$type_hash) {
		( $expand->{"type_pkg[$_]"} = $expand->{"type_raw[$_]"} = $type_hash->{$_} ) =~ s/\.//g;
		( $expand->{"type_num[$_]"} = $type_hash->{$_} ) =~ s/[^\d]//g;
	}
	$expand->{"lib"} = "lib";
	if (exists $type_hash->{"-64bit"}) {
		if ($type_hash->{"-64bit"} eq "-64bit") {
			if ($config->param('Architecture') eq "powerpc" ) {
				$expand->{"lib"} = "lib/ppc64";
			} elsif ($config->param('Architecture') eq "i386" ) {
				$expand->{"lib"} = "lib/x86_64";
			} elsif ($config->param('Architecture') eq "x86_64" ) {
				# paradoxically, no special library location is required for
				# -64bit variants under x86_64 architecture
			} else {
				print_breaking_stderr "Skipping $self->{_filename}\n";
				delete $self->{package};
				return;
			}
		}
	}
	if ($self->has_parent()) {
		# get parent's Package for percent expansion
		# (only splitoffs can use %N in Package)
		$expand->{'N'}  = $self->get_parent()->get_name();
		$expand->{'n'}  = $expand->{'N'};  # allow for a typo
	}

	$self->{_package_invariant} = $self->{package};

	# Setup basic package name
	# must always call expand_percent even if no Type in order to make
	# sure we don't have bogus %type_*[] or other bad % constructs
	# (do %-exp on complete Package first in order to catch any %-exp problems)
	unless (defined($self->{package} = &expand_percent2(
						$self->{package}, $expand,
						'err_action' => 'undef',
						'err_info'   => "$self->{_filename} \"package\""
					))) {
		print_breaking_stderr "Skipping $self->{_filename}\n";
		delete $self->{package};
		return;
	};

	# Setup invariant name
	$self->{_package_invariant} =~ s/\%type_(raw|pkg)\[.*?\]//g;
	# %-exp of Package already caught any %-exp problems
	$self->{_package_invariant} = &expand_percent($self->{_package_invariant},
		$expand, "$self->{_filename} \"package\"");

	### END handle types


	# setup basic fields
	$self->{_name} = $pkgname = $self->param_default("Package", "");
	$self->{_version} = $version = $self->param_default("Version", "0");
	$self->{_revision} = $revision = $self->param_default("Revision", "0");
	$self->{_epoch} = $epoch = $self->param_default("Epoch", "0");

	# path handling
	if ($filename) {
		@parts = split(/\//, $filename);
		pop @parts;		# remove filename
		$self->{_patchpath} = join("/", @parts);
		for ($finkinfo_index = $#parts;
				 $finkinfo_index > 0 and $parts[$finkinfo_index] ne "finkinfo";
				 $finkinfo_index--) {
			# this loop intentionally left blank
		}
		if ($finkinfo_index <= 0) {
			# put some dummy info in for scripts that want
			# to parse info files outside of Fink
			$self->{_section}  = 'unknown';
			$self->{_debpath}  = '/tmp';
			$self->{_debpaths} = ['/tmp'];
			$self->{_full_trees}    = [ [ 'unknown' ] ];
		} else {
			# compute the "section" of this package, e.g. "net", "devel", "crypto"...
			$section = $parts[$finkinfo_index-1]."/";
			if ($finkinfo_index < $#parts) {
				$section = "" if $section eq "main/";
				$section .= join("/", @parts[$finkinfo_index+1..$#parts])."/";
			}
			$self->{_section} = substr($section,0,-1);	 # cut last /
			$parts[$finkinfo_index] = 'binary-' . $config->param('Debarch');
			$self->{_debpath} = join("/", @parts);
			$self->{_debpaths} = [];
			for ($i = $#parts; $i >= $finkinfo_index; $i--) {
				push @{$self->{_debpaths}}, join("/", @parts[0..$i]);
			}

			# determine the full package tree, eg: [ qw(stable main) ]
			# front (removed): '', %p, 'fink', 'dists'
			my $skip = () = ($basepath =~ m,[^/]+,g); # count components of prefix
			$self->{_full_trees} = [ [ @parts[(3+$skip)..$finkinfo_index-1] ] ];
		}
	} else {
		# for dummy descriptions generated from dpkg status data alone
		$self->{_patchpath} = "";
		$self->{_section}   = "unknown";
		$self->{_debpath}   = "";
		$self->{_debpaths}  = [];

		# assume "binary" tree
		$self->{_full_trees} = [ [ "binary" ] ];
	}

	# some commonly used stuff
	$fullname = $pkgname."-".$version."-".$revision;
	# prepare percent-expansion map
	if ($self->has_parent) {
		my $parent = $self->get_parent;
		$parentpkgname = $parent->get_name();
		$parentinvname = $parent->param_default("_package_invariant", $parentpkgname);
	} else {
		$parentpkgname = $pkgname;
		$parentinvname = $self->param_default("_package_invariant", $pkgname);
		$self->{_splitoffs} = [];
	}

	# Add remaining values to expansion-hash
	$expand = { %$expand,
				'n' => $pkgname,
				'ni'=> $self->param_default("_package_invariant", $pkgname),
				'e' => $epoch,
				'v' => $version,
				'V' => $self->get_fullversion,
				'r' => $revision,
				'f' => $fullname,
				'p' => $basepath,
				'm' => $config->param('Architecture'),

				'N' => $parentpkgname,
				'Ni'=> $parentinvname,
				'P' => $basepath,

#				'a' => $self->{_patchpath},
				'b' => '.'
			};

	# Percent-expansion fields that depend on a fink's runtime configs
	# aren't assigned here. We push that into load_fields, which is
	# always called before any fields are used.
	$self->{_expand} = $expand;

	$self->{_bootstrap} = 0;

	# Description is used by 'fink list' so better to get it expanded now
	# also keeps %type_[] out of all list and search fields of pdb
	$self->expand_percent_if_available("Description");

	# from here on we have to distinguish between "real" packages and splitoffs
	if ($self->has_parent) {
		# so it's a splitoff
		my ($parent, $field);

		$parent = $self->get_parent;

		if ($parent->has_param('maintainer')) {
			$self->{'maintainer'} = $parent->{'maintainer'};
		}

		# handle inherited fields
		our @inherited_pkglists =
		 qw(Description DescDetail Homepage License);

		foreach $field (@inherited_pkglists) {
			$field = lc $field;
			if (not $self->has_param($field) and $parent->has_param($field)) {
				$self->{$field} = $parent->{$field};
			}
		}
	} else {
		# implicit "Source" must die
		if (!$self->has_param('Source') and !$self->is_type('dummy') and !$self->is_type('nosource') and !$self->is_type('bundle')) {
			print "\nWarning: file ", $self->get_info_filename, "\nThe implicit \"Source\" feature is deprecated and will be removed soon.\nAdd \"Source: %n-%v.tar.gz\" to assure future compatibility.\n\n";
		}

		# handle splitoff(s)
		@splitofffields = $self->params_matching('SplitOff(?:[2-9]|[1-9]\d+)?');
		if (@splitofffields) {
			# need to keep SplitOff(N) in order
			foreach (map  { $_->[0] }
					 sort { $a->[1] <=> $b->[1] }
					 map  { [ $_, ( (/(\d+)/)[0] || 0 ) ] } @splitofffields
					 ) {
				# form splitoff pkg as its own PkgVersion object
				$self->add_splitoff($self->param($_),$_);
				delete $self->{$_};  # no need to keep the raw fields in the parent
			}
		}
	}

	# Cache Provides pkglist, so we don't need percent-expansion to insert a
	# PkgVersion
	$self->set_param('_provides_no_cache', 1);
	if ($self->has_pkglist('Provides')) {
		$self->set_param('_pkglist_provides', $self->pkglist('Provides'));
	};
	delete $self->{_provides_no_cache};
}

### fields that are package lists need special treatment
### use these accessors instead of param(), has_param(), param_default()
# FIXME-dmacks: need a syntax like foo(-ssl?) that expands to foo|foo-ssl

# fields from which one's own package should be removed
our %pkglist_no_self = ( 'conflicts' => 1,
						 'replaces'  => 1
					   );

sub pkglist_common {
	my ($self, $method, $param, @etc) = @_;
	$method = $self->can($method);
	$param = lc $param || "";

	# This is cached, to make loading faster
	return $self->$method('_pkglist_provides', @etc)
		if $param eq 'provides' && !$self->has_param('_provides_no_cache');

	$self->_remove_extraneous_chars($param);
	$self->expand_percent_if_available($param);
	$self->conditional_pkg_list($param);
	if (exists $pkglist_no_self{$param}) {
		$self->clear_self_from_list($param);
	}
	return $self->$method($param, @etc);
}

sub pkglist {
	my ($self, @etc) = @_;
	$self->pkglist_common('param', @etc);
}

sub pkglist_default {
	my ($self, @etc) = @_;
	$self->pkglist_common('param_default', @etc);
}

sub has_pkglist {
	my ($self, @etc) = @_;
	$self->pkglist_common('has_param', @etc);
}

## remove excess chars:
##  - comments, from # to end of line
##  - normalize whitespace
##  - remove trailing comma

sub _remove_extraneous_chars {
	my $self = shift;
	my $field = lc shift;
	if ($self->has_param($field)) {
		my $val = $self->param($field);
		if ($self->info_level() >= 3) {
			$val =~ s/#.*$//mg;	# comments are from # to end of line
			$val =~ s/,\s*$//;
		}
		$val =~ s/\s+/ /g;
		$val =~ s/^\s*(.*?)\s*$/$1/sg;
		$self->set_param($field => $val);
	}
}

### expand percent chars in the given field, if that field exists
### return the expanded form and store it back into the field data

sub expand_percent_if_available {
	my $self = shift;
	my $field = lc shift;

	if ($self->has_param($field)) {
		$self->{$field} = &expand_percent($self->{$field}, $self->{_expand}, $self->get_info_filename." \"$field\"");
	}
}

### expand percent chars in the given field, if that field exists
### return the expanded form but do not store it back into the field data

sub param_expanded {
	my $self = shift;
	my $field = shift;
	my $err_action = shift;
	return &expand_percent($self->param($field), $self->{_expand},
		$self->get_info_filename." \"$field\"", $err_action);
}

=item param_default_expanded

	my $value = $pv->param_default_expanded $field, $default;
	my $value = $pv->param_default_expanded $field, $default, %options;

Expand percent chars in the given $field, if that field exists.
Return the expanded form but do not store it back into the field data.
If the field doesn't exist, return the $default. The following
%options may be used:

=over 4

=item expand_override (optional)

A hashref containing a percent-expansion map to be used in addition to
(and overriding) that in the _expand pv package data.

=item err_action (optional)

Specify the behavior when an unknown percent-expansion token is
encountered. See Fink::Services::expand_percent2 for details.

=back

=cut

### Do not change API! param_default_expanded is used by the pdb scripts (dump)

sub param_default_expanded {
	my $self = shift;
	my $field = shift;
	my $default = shift;
	my %options = (@_);

	my $expand = $self->{_expand};
	if ($options{expand_override}) {
		$expand = { %{$self->{_expand}}, %{$options{expand_override}} };
	}

	return &expand_percent2(
		$self->param_default($field, $default), $expand,
		err_info => $self->get_info_filename." \"$field\"",
		err_action => $options{err_action}
	);
}

### Process a Depends (or other field that is a list of packages,
### indicated by $field) to handle conditionals. The field is re-set
### to be conditional-free (remove conditional expressions, remove
### packages for which expression was false). No percent expansion is
### performed (i.e., do it yourself before calling this method).
### Whitespace cleanup is performed.

sub conditional_pkg_list {
	my $self = shift;
	my $field = lc shift;

	my $value = $self->param($field);
	return unless defined $value;

	# short-cut if no conditionals...
	if (not $value =~ /(?-:\A|,|\|)\s*\(/) {
		# just remove leading and trailing whitespace (slinging $value
		# through pkglist2lol + lol2pkglist has same effect so only
		# need to do it manually if short-cut inhibits those calls)
		$value = &collapse_space($value);
		$self->set_param($field, $value);
		return;
	}

#	print "conditional_pkg_list for ",$self->get_name,": $field\n";
#	print "\toriginal: '$value'\n";
	my $struct = &pkglist2lol($value);
	foreach (@$struct) {
		foreach (@$_) {
			if (s/^\s*\((.*?)\)\s*(.*)/$2/) {
				# we have a conditional; remove the cond expression
				my $cond = $1;
#				print "\tfound conditional '$cond'\n";
				# if cond is false, clear entire atom
				undef $_ unless &eval_conditional($cond, "$field of ".$self->get_info_filename);
			}
		}
	}
	$value = &lol2pkglist($struct);
#	print "\tnow have: '$value'\n";
	$self->set_param($field, $value);
	return;
}

### Remove our own package name from a given package-list field
### (Conflicts or Replaces, indicated by $field; these fields are
### always AND of single pkgs, no OR clustering). This must be called
### after conditional dependencies are cleared. The field is re-set.

sub clear_self_from_list {
	my $self = shift;
	my $field = lc shift;

	my $value = $self->param($field);
	return unless defined $value and length $value;
	my $pkgname = $self->get_name;
	return unless $value =~ /\Q$pkgname\E/;  # short-cut if we're not listed

	# Approach: break apart comma-delimited list, reassemble only
	# those atoms that don't match.

	$value = join ", ", ( grep { /([a-z0-9.+\-]+)/ ; $1 ne $pkgname } split /,\s*/, $value);
	$self->set_param($field, $value);
}

# Process ConfigureParams (including Type-specific defaults) and
# conditionals, set {_expand}->{c}, and return result.
# Does not change {configureparams}.
#
# NOTE:
#   You must set _expand before calling!
#   You must make sure this method has been called before ever calling
#     expand_percent if it could involve %c!

sub prepare_percent_c {
	my $self = shift;

	$self->get_build_directory;  # make sure we have %b

	my $pct_c;

	my $type = $self->get_defaultscript_type();
	if ($type eq 'makemaker') {
		# grab perl version, if present
		my ($perldirectory, $perlarchdir, $perlcmd) = $self->get_perl_dir_arch();

		$pct_c =
			"PERL=\"$perlcmd\" " .
			"PREFIX=\%p " .
			"INSTALLPRIVLIB=\%p/lib/perl5$perldirectory " .
			"INSTALLARCHLIB=\%p/lib/perl5$perldirectory/$perlarchdir " .
			"INSTALLSITELIB=\%p/lib/perl5$perldirectory " .
			"INSTALLSITEARCH=\%p/lib/perl5$perldirectory/$perlarchdir " .
			"INSTALLMAN1DIR=\%p/share/man/man1 " .
			"INSTALLMAN3DIR=\%p/share/man/man3 " .
			"INSTALLSITEMAN1DIR=\%p/share/man/man1 " .
			"INSTALLSITEMAN3DIR=\%p/share/man/man3 " .
			"INSTALLBIN=\%p/bin " .
			"INSTALLSITEBIN=\%p/bin " .
			"INSTALLSCRIPT=\%p/bin ";

	} elsif ($type eq 'modulebuild') {
		# grab perl version, if present
		my ($perldirectory, $perlarchdir, $perlcmd) = $self->get_perl_dir_arch();

		$pct_c =
			"--install_base \%p " .
			"--install_path bin=\%p/bin " .
			"--install_path lib=\%p/lib/perl5$perldirectory " .
			"--install_path arch=\%p/lib/perl5$perldirectory/$perlarchdir " .
			"--install_path bindoc=\%p/share/man/man1 " .
			"--install_path libdoc=\%p/share/man/man3 " .
			"--install_path script=\%p/bin " .
			"--destdir \%d ";

	} else {
		$pct_c =
			"--prefix=\%p ";
	}
	$pct_c .= $self->param_default("ConfigureParams", "");

	# need to expand here so can use %-keys in conditionals
	$pct_c = &expand_percent(
		$pct_c,
		$self->{_expand},
		"ConfigureParams of ".$self->get_info_filename
	);

	$pct_c = $self->conditional_space_list(
		$pct_c,
		"ConfigureParams of ".$self->get_info_filename
	);

	# reprotect "%" b/c %c used in *Script and get_*script() does %-exp
	$pct_c =~ s/\%/\%\%/g;
	$self->{_expand}->{c} = $pct_c;
}

# handle conditionals processing in a list of space-separated atoms
#
# NOTE:
#   Percent-expansion is *not* performed here; you must do it yourself
#     if necessary before calling this method!

sub conditional_space_list {
	my $self = shift;    # unused
	my $string = shift;  # the string to parse
	my $where = shift;   # used in warning messages

	$string =~ s/^\s*//;
	$string =~ s/\s*$//;

	return $string unless defined $string and $string =~ /\(/; # short-circuit

	# prepare the paren-balancing parser
	my $mc = Fink::Text::DelimMatch->new( '\s*\(\s*', '\s*\)\s*' );
	$mc->quote("'");
	$mc->escape("\\");
	$mc->returndelim(0);
	$mc->keep(0);

	my($stash, $prefix, $cond, $chunk, @save_delim);  # scratches used in loop
	my $result;

	while (defined $string) {
		$stash = $string;  # save in case no parens (parsing clobbers string)

		($prefix, $cond, $string) = $mc->match($string);  # pluck off first paren set
		$result .= $prefix if defined $prefix;  # leading non-paren things
		if (defined $cond) {
			# found a conditional (string in balanced parens)
			if (defined $string) {
				if ($string =~ /^\s*\{/) {
					# grab whole braces-delimited chunk
					@save_delim = $mc->delim( '\s*\{\s*', '\s*\}\s*' );
					($prefix, $chunk, $string) = $mc->match($string);
					$mc->delim(@save_delim);
				} else {
					# grab first word
					# should canibalize parse_line, optimize this specific use
					# BUG: trailing backslash (last line of a
					# multiline field being fed to a shell command,
					# e.g., ConfigureParams) breaks parse_line. See:
					# https://rt.cpan.org/Ticket/Display.html?id=61103
					$chunk = (&parse_line('\s+', 1, $string))[0];
					$string =~ s/^\Q$chunk//;  # already dealt with this now
				}
				if (defined $chunk and $chunk =~ /\S/) {
					# only keep it if conditional is true
					$result .= " $chunk" if &eval_conditional($cond, $where);
				} else {
					print "Conditional \"$cond\" controls nothing in $where!\n";
				}
			} else {
				print "Conditional \"$cond\" controls nothing in $where!\n";
			}
		} else {
			$result .= $stash;
		}
	}

	$result =~ s/^\s*//;
	$result =~ s/\s*$//;
	$result;
}

=item get_defaultscript_type

	my $defaultscript_type = $pv->get_defaultscript_type;

Returns a string indicating the type of build system to assume for
%{default_script} and related processing. The value is an enum of:

=over 4

=item autotools

=item makemaker

=item ruby

=item modulebuild

=back

The value is controlled explicitly by the DefaultScript: field, or
else implicitly by certain Type: field tokens.

=cut

sub get_defaultscript_type {
	my $self = shift;

	if (!exists $self->{_defaultscript_type}) {
		# Cached because if we did it once, we are probably going to
		# do it again for for each phase of the build process.
		my $type;
		if ($self->has_param('DefaultScript')) {
			# first try explicit DefaultScript: control
			$type = $self->param('DefaultScript');

			unless ($type =~ /^(autotools|makemaker|ruby|modulebuild)$/i) {
				# don't fall through to unintended if typo, etc.
				die "this version of fink does not know how to handle DefaultScript:$type to build package ".$self->get_fullname()."\n";
			}
			if ($self->is_type('bundle')) {
				die "Type:bundle cannot be overridden by DefaultScript to build package ".$self->get_fullname()."\n";
			}
			# Overriding Type:dummy isn't a possible state for fink
			# because dummy means there's no .info and DefaultScript
			# is data present only in the .info

			$type = lc $type;	# canonical lowercase
		} else {
			# otherwise fall back to legacy Type: control
			if ($self->is_type('perl')) {
				$type = 'makemaker';
			} elsif ($self->is_type('ruby')) {
				$type = 'ruby';
			} else {
				$type = 'autotools';
			}
		}
		$self->{_defaultscript_type} = $type;
	}

	return $self->{_defaultscript_type};
}

# returns the requested *Script field (or default value, etc.)
# percent expansion is performed
#
# implementation note: Type:bundle takes precedence over other "magic"
# types like Type:perl
sub get_script {
	my $self = shift;
	my $field = shift;
	$field = lc $field;

	my $default_script = ""; # Type-based script (%{default_script})
	my $field_value;         # .info field contents

	$self->prepare_percent_c;  # make sure %c has the most up-to-date data

	if ($field eq 'patchscript') {
		return "" if $self->has_parent;  # shortcut: SplitOffs do not patch
		return "" if $self->is_type('dummy');  # Type:dummy never patch
		return "" if $self->is_type('bundle'); # Type:bundle never patch

		$field_value = $self->param_default($field, '%{default_script}');

		for my $suffix ($self->get_patchfile_suffixes()) {
			$default_script .= "/usr/bin/patch -p1 < \%{PatchFile$suffix}\n";
		}

	} elsif ($field eq 'compilescript') {
		return "" if $self->has_parent;  # shortcut: SplitOffs do not compile
		return "" if $self->is_type('bundle'); # Type:bundle never compile

		$field_value = $self->param_default($field, '%{default_script}');

		my $type = $self->get_defaultscript_type();
		if ($type eq 'makemaker') {
			# We specify explicit CC and CXX values below, because even though
			# path-prefix-*wraps gcc and g++, system-perl configure hardcodes
			# gcc-4.x, which is not wrapped or necessarily even present.
			my ($perldirectory, $perlarchdir, $perlcmd) = $self->get_perl_dir_arch();
			my $archflags = 'ARCHFLAGS=""'; # prevent Apple's perl from building fat
			$default_script =
				"$archflags $perlcmd Makefile.PL \%c\n".
				"/usr/bin/make CC=gcc CXX=g++\n";
		} elsif ($type eq 'modulebuild') {
			my ($perldirectory, $perlarchdir, $perlcmd) = $self->get_perl_dir_arch();
			my $archflags = 'ARCHFLAGS=""'; # prevent Apple's perl from building fat
			$default_script =
				"$archflags $perlcmd Build.PL \%c\n".
				"$archflags ./Build\n";
		} elsif ($type eq 'ruby') {
			my ($rubydirectory, $rubyarchdir, $rubycmd) = $self->get_ruby_dir_arch();
			$default_script =
				"$rubycmd extconf.rb\n".
				"/usr/bin/make\n";
		} elsif ($self->is_type('dummy')) {
			$default_script = "";
		} else {
			$default_script =
				"./configure \%c\n".
				"/usr/bin/make\n";
		}

	} elsif ($field eq 'installscript') {
		return "" if $self->is_type('dummy');  # Type:dummy never install

		if ($self->has_parent) {
			# SplitOffs default to blank script
			$field_value = $self->param_default($field, '');
			if ($self->is_type('bundle')) {
				# Type:bundle always uses predefined script
				$field_value =
					"/bin/mkdir -p \%i/share/doc/\%n\n".
					"echo \"\%n is a bundle package that doesn't install any files of its own.\" >\%i/share/doc/\%n/README\n";
			}
		} elsif ($self->is_type('bundle')) {
			# Type:bundle always uses predefined script
			$field_value =
				"/bin/mkdir -p \%i/share/doc/\%n\n".
				"echo \"\%n is a bundle package that doesn't install any files of its own.\" >\%i/share/doc/\%n/README\n";
		} else {
			$field_value = $self->param_default($field, '%{default_script}');
		}

		my $type = $self->get_defaultscript_type();
		if ($type eq 'makemaker') {
			# grab perl version, if present
			my ($perldirectory, $perlarchdir) = $self->get_perl_dir_arch();
			$default_script =
				"/usr/bin/make -j1 install PREFIX=\%p INSTALLPRIVLIB=\%p/lib/perl5$perldirectory INSTALLARCHLIB=\%p/lib/perl5$perldirectory/$perlarchdir INSTALLSITELIB=\%p/lib/perl5$perldirectory INSTALLSITEARCH=\%p/lib/perl5$perldirectory/$perlarchdir INSTALLMAN1DIR=\%p/share/man/man1 INSTALLMAN3DIR=\%p/share/man/man3 INSTALLSITEMAN1DIR=\%p/share/man/man1 INSTALLSITEMAN3DIR=\%p/share/man/man3 INSTALLBIN=\%p/bin INSTALLSITEBIN=\%p/bin INSTALLSCRIPT=\%p/bin DESTDIR=\%d\n";
		} elsif ($type eq 'modulebuild') {
			$default_script =
				"./Build install\n";
		} elsif ($self->is_type('bundle')) {
			$default_script =
				"/bin/mkdir -p \%i/share/doc/\%n\n".
				"echo \"\%n is a bundle package that doesn't install any files of its own.\" >\%i/share/doc/\%n/README\n";
		} else {
			$default_script = "/usr/bin/make -j1 install prefix=\%i\n";
		}

	} elsif ($field eq 'testscript') {
		return "" unless Fink::Config::get_option("tests");
		return "" if $self->has_parent;  # shortcut: SplitOffs do not test
		return "" if $self->is_type('dummy');  # Type:dummy never test

		$field_value = $self->param_default($field, '%{default_script}');

		my $type = $self->get_defaultscript_type();
		if ($type eq 'makemaker' && !$self->param_boolean('NoPerlTests')) {
			$default_script =
				"/usr/bin/make test || exit 2\n";
		} elsif ($type eq 'modulebuild' && !$self->param_boolean('NoPerlTests')) {
			$default_script =
				"./Build test || exit 2\n";
		}

	} else {
		# should never get here
		die "Invalid script field for get_script: $field\n";
	}

	# need to pre-expand default_script so not have to change
	# expand_percent() to go a third level deep
	$self->{_expand}->{default_script} = &expand_percent(
		$default_script,
		$self->{_expand},
		$self->get_info_filename." ".lc $field
	);
	my $script = &expand_percent($field_value, $self->{_expand},
								 $self->get_info_filename." \"$field\"");
	delete $self->{_expand}->{default_script};  # this key must stay local

	return $script;
}

# Activate InfoTest fields.
# This parses the InfoTest block and promotes the fields defined within.
# So, it makes values defined in InfoTest override or alter the main
# values as necessary.
sub activate_infotest {
	my $self = shift;
	return if $self->{_test_activated};
	$self->{_test_activated} = 1;

	my $infotest = $self->param_default("InfoTest", "");
	my $max_source = ($self->get_source_suffixes)[-1];
	$max_source ||= ($self->param("Source") and
		lc($self->param("Source")) ne "none") ? 1 : 0;
	my $test_properties = &read_properties_var(
		"InfoTest of ".$self->get_fullname,
		$self->param_default('InfoTest', ''), {remove_space => 1});
	while (my($key, $val) = each(%$test_properties)) {
		if ($key =~ /^Test(Depends|Conflicts)$/i) {
			my $orig_field = "Build$1";
			my $orig_val = $self->param_default($orig_field, "");
			$orig_val .= ", " if $orig_val;
			$self->set_param($orig_field, "$orig_val$val");
		} elsif ($key =~ /^TestConfigureParams$/i) {
			my $main_cp = $self->param_default('ConfigureParams', "");
			chomp $main_cp;
			$self->set_param('ConfigureParams', "$main_cp $val");
			$self->prepare_percent_c;
		} elsif ($key =~ /^Test(Source|Tar)(\d*)(ExtractDir|FilesRename|Rename|-MD5|-Checksum)?$/i) {
			my($test_field_type, $test_no, $test_field) = ($1, $2, $3);
			$test_field ||= "";
			my $source_num = $max_source + ($test_no || 1);
			$source_num = "" if $source_num == 1;
			my $src_param = "$test_field_type$source_num$test_field";
			$self->set_param($src_param, $val);
		} else {
			$self->set_param($key, $val);
		}
	}

	delete $self->{_source_suffixes};
}

### add a splitoff package

sub add_splitoff {
	my $self = shift;
	my $splitoff_data = shift;
	my $fieldname = shift;
	my $filename = $self->{_filename};
	my ($properties, $package, $pkgname, @splitoffs);

	# if we're not Info3+, use old-style whitespace removal
	$splitoff_data =~ s/^\s+//gm if $self->info_level < 3;

	# get the splitoff package name
	$properties = &read_properties_var("$fieldname of \"$filename\"",
		$splitoff_data,
		{ remove_space => ($self->info_level >= 3) });
	$pkgname = $properties->{'package'};
	unless ($pkgname) {
		print "No package name for $fieldname in $filename\n";
	}

	# copy version information
	$properties->{'version'}  = $self->{_version};
	$properties->{'revision'} = $self->{_revision};
	$properties->{'epoch'}    = $self->{_epoch};

	# link the splitoff to its "parent" (=us)
	$properties->{parent_obj} = $self;

	# need to inherit (maybe) Type before package gets created
	if (not exists $properties->{'type'}) {
		if (exists $self->{'type'}) {
			$properties->{'type'} = $self->{'type'};
		}
	} elsif ($properties->{'type'} eq "none") {
		delete $properties->{'type'};
	}

	# instantiate the splitoff
	@splitoffs = $self->pkgversions_from_properties($properties,
		filename => $filename, info_level => $self->info_level(),
		parent_obj => $self);

	# return the new object(s). NOTE: This is actually adding objects!
	push @{$self->{_splitoffs_obj}}, @splitoffs;
}

=item merge

  $new_pv->merge($old_pv);

When one PkgVersion supplants another one, some properties of the old one may
still be relevant. This call method gives the new one a chance to examine the
old one and take things from it.

=cut

sub merge {
	my ($self, $old) = @_;
	# Insert new trees
	{
		my %seen = map { $_ => 1 } $self->get_full_trees;
		foreach my $tree (@{$old->{_full_trees}}) {
			my $txt = join('/', @$tree);
			unshift @{$self->{_full_trees}}, $tree unless $seen{$txt}++;
		}
	}

	# FIXME: Should we merge in the debpaths, as we (possibly) once did? It
	# would make sense, since a deb in the wrong tree should still be fine.
	# *BUT*, it would require storing the debpaths in the index.db, that
	# might be overkill. (Will UseBinaryDist find them anyhow?)

### NOTE: This method used to do something different, and it looks
### like that code path is dead. Code is left here until we're sure.
#	my $self = shift;
#	my $dup = shift;
#
#	print "Warning! Not a dummy package\n" if $self->is_type('dummy');
#	push @{$self->{_debpaths}}, @{$dup->{_debpaths}};
}

### bootstrap helpers

sub enable_bootstrap {
	my $self = shift;
	my $bsbase = shift;
	my $splitoff;

	$self->{_expand}->{p} = $bsbase;
	$self->{_expand}->{d} = "";
	$self->{_expand}->{i} = $bsbase;
	$self->{_expand}->{D} = "";
	$self->{_expand}->{I} = $bsbase;
	$self->prepare_percent_c;

	$self->{_bootstrap} = 1;

	foreach	 $splitoff ($self->parent_splitoffs) {
		$splitoff->enable_bootstrap($bsbase);
	}

}

sub disable_bootstrap {
	my $self = shift;
	my ($destdir);
	my $splitoff;

	$self->{_expand}->{p} = $basepath;
	$self->_set_destdirs;
	$self->{_bootstrap} = 0;

	foreach	 $splitoff ($self->parent_splitoffs) {
		$splitoff->disable_bootstrap();
	}
}

=item is_bootstrapping

  my $bool = $pv->is_bootstrapping;

Are we in bootstrap mode?

=cut

sub is_bootstrapping {
	return $_[0]->{_bootstrap};
}

=item get_name

=item get_version

=item get_revision

=item get_epoch

These accessors return strings for the various fundamental package
data. The values are all guaranteed to be defined (they default to "0"
if the field is missing from the package).

=cut

sub get_name {
	my $self = shift;
	return $self->{_name};
}

sub get_version {
	my $self = shift;
	return $self->{_version};
}

sub get_revision {
	my $self = shift;
	return $self->{_revision};
}

sub get_epoch {
	my $self = shift;
	return $self->{_epoch};
}

=item get_fullversion

=item get_fullname

These accessors return strings for the various derived package data.
The fullversion includes the epoch if the epoch is not zero (prefixed
to the version, delimited by a colon). The fullname never includes the
epoch.

=cut

sub get_fullversion {
	my $self = shift;
	my $epoch = $self->get_epoch();
	exists $self->{_fullversion} or $self->{_fullversion} = sprintf '%s%s-%s',
		$epoch ? $epoch.':' : '',
		$self->get_version(),
		$self->get_revision();
	return $self->{_fullversion};
}

sub get_fullname {
	my $self = shift;
	exists $self->{_fullname} or $self->{_fullname} = sprintf '%s-%s-%s',
		$self->get_name(),
		$self->get_version(),
		$self->get_revision();
	return $self->{_fullname};
}

=item get_filename

=item get_info_filename

These accessors return the .info filename from which this package's
database entry was constructed. If the package is generated by
VirtPackage or dpkg status data alone, get_filename() will return a
null string or undef, while get_info_filename() will always return a
null string in these situations.

=cut

### Do not change API! This is used by FinkCommander (fpkg_list.pl)
sub get_filename {
	my $self = shift;
	return $self->{_filename};
}

sub get_info_filename {
	my $self = shift;
	return "" unless exists  $self->{_filename};
	return "" unless defined $self->{_filename};
	return $self->{_filename};
}

=item get_debname

=item get_debpath

=item get_debfile

These accessors return information about the .deb archive file for the
package. The debname is the simple filename. The debpath is the
directory that would contain the debfile if it were locally built
(this is buried in %p/fink/dists, not the symlink dir %p/fink/debs or
a cache of downloaded precompiled (apt-get) binaries). The debfile is
the full path, composed of the debpath and debfile.

=cut

sub get_debname {
	my $self = shift;
	exists $self->{_debname} or $self->{_debname} = sprintf '%s_%s-%s_%s.deb',
		$self->get_name(),
		$self->get_version(),
		$self->get_revision(),
		$config->param('Debarch');
	return $self->{_debname};
}

sub get_debpath {
	my $self = shift;

	my $path = $self->{_debpath};
	my $dist = $config->param("Distribution");
	$path =~ s/\/dists\//\/$dist\//;
	return $path;
}

sub get_debfile {
	my $self = shift;
	return $self->get_debpath() . '/' . $self->get_debname();
}

### Do not change API! This is used by FinkCommander (fpkg_list.pl)

sub get_section {
	my $self = shift;
	return $self->{_section};
}

# get_instsize DIR
#
# Gets the size of a directory in kilobytes (not bytes!)
sub get_instsize {
	my $self = shift;
	my $path = shift;

	my $size = du_sk($path);
	if ( $size =~ /^Error:/ ) {
		die $size;
	}
	return $size;
}

=item get_tree

  my $tree = $pv->get_tree;

Get the last (highest priority) tree in which this package can be found.
This refers to just the "archive" component of the tree, eg: 'main'.

=cut

### Do not change API! This is used by FinkCommander (fpkg_list.pl)

sub get_tree {
	my $self = shift;
	return ( ($self->get_trees)[-1] );
}

=item get_trees

  my @trees = $pv->get_trees;

Get a list of every tree in which this package can be found.

=cut

sub get_trees {
	my $self = shift;
	return map { $_->[0] } @{$self->{_full_trees}};
}

=item in_tree

  my $bool = $pv->in_tree($tree);

Get whether or not this package can be found in the given tree.

=cut

sub in_tree {
	my ($self, $tree) = @_;
	return scalar(grep { $_ eq $tree } $self->get_trees);
}


### other accessors

# get_source_suffices
#
# retained as long-standing public interface, now deprecated
sub get_source_suffices {
	$_[0]->get_source_suffixes();
}

# get_source_suffixes
#
# Returns an ordered list of all "N"s for which there are non-"none" SourceN
# Note that the primary source will always be at the front.
sub get_source_suffixes {
	my $self = shift;

	# Cache it
	if (!exists $self->{_source_suffixes}) {
		if ( $self->is_type('bundle') || $self->is_type('nosource') || $self->is_type('dummy') || $self->has_parent || ( defined $self->param("Source") && lc $self->param("Source") eq 'none' ) ) {
			$self->{_source_suffixes} = [];
		} else {
			my @params = $self->params_matching('source([2-9]|[1-9]\d+)');
			map { s/^source//i } @params;
			@params = sort { $a <=> $b } @params;
			@params = grep { defined $self->param("Source$_") && lc $self->param("Source$_") ne 'none' } @params;
			unshift @params, "";
			$self->{_source_suffixes} = \@params;
		}
	}

	return @{$self->{_source_suffixes}};
}

# get_source [ SUFFIX ]
#
# Returns the source for a given SourceN suffix. If no suffix is given,
# returns the primary source.
# On error (eg: nonexistent suffix) returns "none".
# May contain mirror information, don't expect a normal URL.
sub get_source {
	my $self = shift;
	my $suffix = shift || "";

	# Implicit primary source
	if ( $suffix eq "" and !$self->has_parent ) {
		my $source = $self->param_default("Source", "\%n-\%v.tar.gz");
		if ($source eq "gnu") {
			$source = "mirror:gnu:\%n/\%n-\%v.tar.gz";
		} elsif ($source eq "gnome") {
			$self->get_version =~ /(^[0-9]+\.[0-9]+)\.*/;
			$source = "mirror:gnome:sources/\%n/$1/\%n-\%v.tar.gz";
		}
		$self->set_param("Source", $source);
	}

	return $self->param_default_expanded("Source".$suffix, "none");
}

# get_patchfile_suffixes
#
# Returns an ordered list of all "N"s for PatchFileN
# Note that the primary patch will always be at the front.
sub get_patchfile_suffixes {
	my $self = shift;

	# Cache it
	if (!exists $self->{_patchfile_suffixes}) {
		my @params = $self->params_matching('patchfile([2-9]|[1-9]\d+)');
		map { s/^patchfile//i } @params;
		@params = sort { $a <=> $b } @params;
		@params = grep { defined $self->param("PatchFile$_") } @params;
		unshift @params, "" if ($self->has_param('PatchFile'));
		for my $param (@params) {
			$self->{'_expand'}->{'PatchFile' . $param} = $self->{_patchpath} . '/' . $self->param('PatchFile' . $param);
		}
		$self->{_patchfile_suffixes} = \@params;
	}

	return @{$self->{_patchfile_suffixes}};
}

# get_tarball [ SUFFIX ]
#
# Returns the name of the source tarball for a given SourceN suffix.
# If no suffix is given, returns the primary source tarball's name.
# On error (eg: nonexistent suffix) returns undef.
sub get_tarball {
	my $self = shift;
	my $suffix = shift || "";

	if ($self->has_param("Source".$suffix."Rename")) {
		return $self->param_expanded("Source".$suffix."Rename");
	} else {
		my $tarball = &filename($self->get_source($suffix));
		return undef if $tarball eq 'none';
		return $tarball;
	}
}

# get_checksum [ SUFFIX ]
#
# Returns the checksum of the source tarball for a given SourceN suffix.
# If no suffix is given, returns the primary source tarball's checksum.
# On error (eg: no checksum for the requested suffix) returns undef.
sub get_checksum {
	my $self = shift;
	my $suffix = shift || "";

	my $sourcefield = 'Source' . $suffix;

	if ($self->has_param($sourcefield . '-Checksum')) {
		return $self->param($sourcefield . '-Checksum');
	} elsif ($self->has_param($sourcefield . '-MD5')) {
		return $self->param($sourcefield . '-MD5');
	}

	return undef;
}

# get_checksum_type [ SUFFIX ]
#
# Returns the type of checksum in the given SourceN checksum entry.
sub get_checksum_type {
	my $self = shift;
	my $suffix = shift || "";

	my $checksum = $self->get_checksum($suffix);
	my $algorithm;
	($algorithm,$checksum) = Fink::Checksum->parse_checksum($checksum);
	return $algorithm;
}

sub get_custom_mirror {
	my $self = shift;
	my $suffix = shift || "";

	if (exists $self->{_custom_mirror}) {
		return $self->{_custom_mirror};
	}

	if ($self->has_param("CustomMirror")) {
		$self->{_custom_mirror} =
			Fink::Mirror->new_from_field($self->param_expanded("CustomMirror"));
	} else {
		$self->{_custom_mirror} = 0;
	}
	return $self->{_custom_mirror};
}

sub get_build_directory {
	my $self = shift;

	if (!exists $self->{_builddir}) {
		my $builddir;

		if ($self->has_parent()) {
			# building is a main-package feature, so %b
			# is based on data there
			$builddir = $self->get_parent()->get_build_directory();
		} else {
			$builddir = $self->get_fullname();  # start with %f
			if ($self->is_type('bundle') || $self->is_type('nosource')
					|| lc $self->get_source() eq "none"
					|| $self->param_boolean("NoSourceDirectory")) {
				# just %f
			} elsif ($self->has_param("SourceDirectory")) {
				# subdir is explicit source directory
				$builddir .= "/".$self->param_expanded("SourceDirectory");
			} else {
				# subdir is derived from tarball filename
				my $dir = $self->get_tarball(); # never undef b/c never get here if no source
				if ($dir =~ /^(.*)[\.\-]tar(\.(gz|z|Z|bz2|xz))?$/) {
					$dir = $1;
				}
				if ($dir =~ /^(.*)[\.\-](t[gbx]z|zip|ZIP)$/) {
					$dir = $1;
				}
				$builddir .= "/".$dir;
			}
		}

		$self->{_builddir} = $builddir;
		$self->{_expand}->{b} = "$buildpath/$builddir";
	}

	return $self->{_builddir};
}

# Accessors for parent
sub has_parent {
	my $self = shift;
	return exists $self->{parent} || exists $self->{parent_obj};
}
sub get_parent {
	my $self = shift;
	$self->{parent_obj} = $self->resolve_spec($self->{parent})
		unless exists $self->{parent_obj};
	return $self->{parent_obj};
}

# PRIVATE: Ensure splitoff object list is around
sub _ensure_splitoffs {
	my $self = shift;
	if (!exists $self->{_splitoffs_obj} && exists $self->{_splitoffs}) {
		$self->{_splitoffs_obj} = [
			# Don't load fields yet
			map { $self->resolve_spec($_, 0) } @{$self->{_splitoffs}}
		];
	}
}

=item parent_splitoffs

  my @splitoffs = $pv->parent_splitoffs;

Returns the splitoffs of this package, not including itself, if this is
a parent package. Otherwise, returns false.

=cut

sub parent_splitoffs {
	my $self = shift;
	$self->_ensure_splitoffs;
	return exists $self->{_splitoffs}
		? map { $_->load_fields } @{$self->{_splitoffs_obj}}
		: ();
}

=item get_splitoffs

  my @splitoffs = $pv->get_splitoffs;
  my $splitoffs = $pv->get_splitoffs $with_parent, $with_self;

Get a list of the splitoffs of this package, or of its parent if this package
is a splitoff.

If $with_parent is true, includes the parent package (defaults false).
If $with_self is true, includes this package (defaults false).
If this package is the parent package, both $with_self and $with_parent must
both be true for this package to be included.

=cut

sub get_splitoffs {
	my $self = shift;

	my $include_parent = shift || 0;
	my $include_self = shift || 0;
	my @list = ();
	my ($splitoff, $parent);

	if ($self->has_parent) {
		$parent = $self->get_parent;
	} else {
		$parent = $self;
	}

	$parent->_ensure_splitoffs;
	if ($include_parent) {
		unless ($self eq $parent && not $include_self) {
			push(@list, $parent);
		}
	}

	foreach $splitoff (@{$parent->{_splitoffs_obj}}) {
		unless ($self eq $splitoff && not $include_self) {
			push(@list, $splitoff);
		}
	}

	return map { $_->load_fields } @list;
}

=item get_relatives

  my @relatives = $pv->get_relatives;

Get the other packages that are splitoffs of this one (or of its parent, if
this package is a splitoff). Does not include this package, but does include
the parent (in case this package is a splitoff).

=cut

sub get_relatives {
	my $self = shift;
	return $self->get_splitoffs(1, 0);
}


# returns the parent of the family

sub get_family_parent {
	my $self = shift;
	return $self->has_parent
		? $self->get_parent
		: $self;
}

# Set up the type hash, and deal with consequences if the type hash cannot
# be setup. Returns 0 if type hash cannot be set up.
sub _setup_type_hash {
	my ($self, $type) = @_;
	return 1 if exists $self->{_type_hash};

	unless ($self->_is_loaded()) {
		return 0 if $type eq 'dummy'; # Allow checking dummy for unloaded obj
		die "Can't check non-dummy type of unloaded PkgVersion\n";
	}

	$self->{_type_hash} = $self->type_hash_from_string($self->param_default("Type", ""), $self->{_filename});
	return 1;
}

# returns whether this fink package is of a given Type:

sub is_type {
	my $self = shift;
	my $type = shift;

	return 0 unless defined $type;
	return 0 unless length $type;
	$type = lc $type;

	return 0 if $self->_setup_type_hash($type) == 0;
	if (defined $self->{_type_hash}->{$type} and length $self->{_type_hash}->{$type}) {
		return 1;
	}
	return 0;
}

# returns the subtype for a given type, or undef if the type is not
# known for the package

sub get_subtype {
	my $self = shift;
	my $type = shift;

	return undef if $self->_setup_type_hash($type) == 0;
	return $self->{_type_hash}->{$type};
}

=item type_hash_from_string

  my $type_hash = Fink::PkgVersion->type_hash_from_string($string, $filename);

Given a $string representing the Type: field of a single package
(i.e., specific variant, not multivalue subtype lists), return a ref
to a hash of type=>subtype key/value pairs. The $filename is used in
error-reporting if the $string cannot be parsed.

=cut

# must be class method because it controls if/how to parse a .info
# file and how to construct %n, so not enough data would be known yet
# to create a PV object
sub type_hash_from_string {
	shift;	# class method - ignore first parameter
	my $string = shift;
	my $filename = shift;

	my %hash;
	$string =~ s/\s*$//g;  # detritus from multitype parsing
	foreach (split /\s*,\s*/, $string) {
		if (/^(\S+)$/) {
			# no subtype so use type as subtype
			$hash{lc $1} = lc $1;
		} elsif (/^(\S+)\s+(\S+)$/) {
			# have subtype
			$hash{lc $1} = $2;
		} else {
			warn "Bad Type specifier '$_' in '$string' of $filename\n";
		}
	}
	return \%hash;
}

=item get_license

This accessor returns the License field for the package, or a null
string if no license could be determined (the return is *always*
defined). This field can be given as a comma-delimitted list of
values, and each value may be controlled by a conditional. The first
value for which the conditional is true or that has no conditional is
used. Leading and trailing whitespace is removed. No case-sanitizing
is performed.

=cut

sub get_license {
	my $self = shift;

	$self->expand_percent_if_available('license');
	$self->conditional_pkg_list('license');  # syntax is close to a Depends!

	$self->param_default('License', '') =~ /^\s*([^,]*)/;
	my $license = $1;  # keep first comma-delimited field
	$license =~ s/\s+$//;

	return $license;
}

=item format_description

	my $string_formatted = format_description $string;

Formats the multiline plain-text $string as a dpkg field value. That
means every line indented by 1 space and blank lines in $string get
converted to a line containing period character (" .\n").

=cut

sub format_description {
	my $s = shift;

	# remove last newline (if any)
	chomp $s;
	# replace empty lines with "."
	$s =~ s/^\s*$/\./mg;
	# add leading space
	# (if you change this here, must compensate in Engine::cmd_dumpinfo)
	$s =~ s/^/ /mg;

	return "$s\n";
}

=item format_oneline

	my $trunc_string = format_oneline $string;
	my $trunc_string = format_oneline $string, $maxlen;

Force $string to fit into the given width $maxlen (if defined and
>0). Embedded newlines and leading and trailing whitespace is
removed. If the resulting string is wider than $maxlen, it is
truncated and an elipses ("...") is added to give a string of the
correct size. This function does *not* respect word-breaks when it
truncates the string.

=cut

sub format_oneline {
	my $s = shift;
	my $maxlen = shift || 0;

	chomp $s;
	$s =~ s/\s*\n\s*/ /sg;
	$s =~ s/^\s+//g;
	$s =~ s/\s+$//g;

	if ($maxlen > 0 && length($s) > $maxlen) {
		$s = substr($s, 0, $maxlen-3)."...";
	}

	return $s;
}

=item get_shortdescription

	my $desc = $self->get_shortdescription;
	my $desc = $self->get_shortdescription $limit;

Returns the Description field for the PkgVersion object or a standard
dummy string if that field does not exist. The value is not truncated
if $limit is negative. It is truncated to $limit chars if $limit is
passed, otherwise it it truncated to 75 chars.

=cut

### Do not change API! This is used by FinkCommander (fpkg_list.pl)

sub get_shortdescription {
	my $self = shift;
	my $limit = shift || 75;
	my ($desc);

	if ($self->has_param("Description")) {
		# "Description" was %-expanded when the PkgVersion object was created
		$desc = &format_oneline($self->param("Description"), $limit);
	} else {
		$desc = "[Package ".$self->get_name()." version ".$self->get_fullversion()."]";
	}
	return $desc;
}

=item get_description

	my $desc = $self->get_description;
	my $desc = $self->get_description $style;
	my $desc = $self->get_description $style, $canonical_prefix; # deprecated!
	my $desc = $self->get_description %options;

Returns the description of the package, formatted for dpkg. The exact
fields used depend on the full_desc_only value in %options. The $style
and $canonical_prefix parameters have the same effect as the
full_desc_only and canonical_prefix values in %options, respectively.
The $canonical_prefix parameter is deprecated and will be removed from
the API soon. The following %options may be used:

=over 4

=item full_desc_only (optional)

If the value is true, only return Description (truncated to 75 chars)
and DescDetail. If false, also include DescUsage, Homepage, and
Maintainer.

=item canonical_prefix (optional)

If the value is true, use "/sw" for %p when parsing the DescDetail and
DescUsage fields instead of the local fink's normal installation path.

=back

=cut

### Do not change the meaning of the $style parameter!
### This part of the API is used by FinkCommander (fpkg_list.pl)

sub get_description {
	my $self = shift;

	my %options;
	if (ref $_[0]) {
		%options = @_;
	} else {
		$options{full_desc_only} = 1 if shift;
		$options{canonical_prefix} = 1 if shift;  # <-- kill this one soon
	}

	my $desc = $self->get_shortdescription(75);  # "Description" (already %-exp)
	$desc .= "\n";

	# need local copy of the %-exp map so we can change it
	my %expand = %{$self->{_expand}};
	if ($options{canonical_prefix}) {
		$expand{p} = '/sw';
	}

	if ($self->has_param("DescDetail")) {
		$desc .= &format_description(
			&expand_percent($self->param('DescDetail'), \%expand,
							$self->get_info_filename.' "DescDetail"', 2)
		);
	}

	if (not $options{full_desc_only}) {
		if ($self->has_param("DescUsage")) {
			$desc .= " .\n Usage Notes:\n";
			$desc .= &format_description(
				&expand_percent($self->param('DescUsage'), \%expand,
								$self->get_info_filename.' "DescUsage"', 2)
			);
		}

		if ($self->has_param("Homepage")) {
			$desc .= " .\n Web site: ".&format_oneline($self->param("Homepage"))."\n";
		}

		if ($self->has_param("Maintainer")) {
			$desc .= " .\n Maintainer: ".&format_oneline($self->param("Maintainer"))."\n";
		}
	}

	return $desc;
}

### get installation state

sub is_fetched {
	my $self = shift;
	my ($suffix);

	if ($self->is_type('bundle') || $self->is_type('nosource') ||
			lc $self->get_source() eq "none" ||
			$self->is_type('dummy')) {
		return 1;
	}

	foreach $suffix ($self->get_source_suffixes) {
		if (not defined $self->find_tarball($suffix)) {
			return 0;
		}
	}
	return 1;
}

=item get_aptdb

  my $hashref = get_aptdb();

Get a hashref with the current packages available via apt-get, and the way apt
wants to get those packages: downloading from a remote site, or using a local
.deb.

=cut

our ($APT_REMOTE, $APT_LOCAL) = (1, 2);

sub get_aptdb {
	my %db;

	my $apt_cache = "$basepath/bin/apt-cache";
	if (!-x $apt_cache) {
		warn "No apt-cache present...skipping binary downloading for now\n";
		return \%db;
	}

	my $statusfile = "$basepath/var/lib/dpkg/status";
	open my $aptdump_fh, "$apt_cache dump |"
		or die "Can't run apt-cache dump: $!";
	my ($pkg, $vers);
	while (defined(local $_ = <$aptdump_fh>)) {
		if (/^\s*Package:\s*(\S+)/) {
			($pkg, $vers) = ($1, undef);
		} elsif (/^\s*Version:\s*(\S+)/) {
			$vers = $1;
		} elsif (/^\s+File:\s*(\S+)/) { # Need \s+ so we don't get crap at end
										# of apt-cache dump
			# Avoid using debs that aren't really apt-getable
			next if $1 eq $statusfile or $1 eq "/tmp/finkaptstatus";

			if (defined $pkg && defined $vers) {
				next if $db{"$pkg-$vers"}; # Use the first one
				if ($1 =~ m,/_[^/]*Packages$,) {
					$db{"$pkg-$vers"} = $APT_LOCAL;
				} else {
					$db{"$pkg-$vers"} = $APT_REMOTE;
				}
			}
		}
	}
	close $aptdump_fh;

	return \%db;
}

=item is_aptgetable

  my $aptgetable = $pv->is_aptgetable;
  my $aptgetable = $pv->is_aptgetable $type;

Get whether or not this package is available via apt-get.

If a type is specified, will only return true if apt get will get the .deb
in the desired way. Specify one of $APT_LOCAL or $APT_REMOTE, or zero for any
type. Defaults to $APT_REMOTE.

=cut

{
	my $aptdb = undef;

	sub is_aptgetable {
		my $self = shift;
		my $wanttype = shift;
		$wanttype = $APT_REMOTE unless defined $wanttype;

		if (!defined $aptdb) { # Load it
			if ($config->binary_requested()) {
				$aptdb = get_aptdb();
			} else {
				$aptdb = {};
			}
		}

		# Return cached value
		my $type = $aptdb->{$self->get_name . "-" . $self->get_fullversion};
		return 0 unless $type;
		return 1 if $wanttype == 0;
		return $type == $wanttype;
	}

=item local_apt_location

  my $path = $pv->local_apt_location;

Find the local path where apt says a deb can be found. Returns undef if none
found.

For packages that have a local non-apt deb file available, the local deb
should be preferred, so this method returns undef.

=cut

sub local_apt_location {
	my $self = shift;

	if (!exists $self->{_apt_loc}) {
		# Apt won't tell us the location if it's installed
		return undef if $self->is_installed();

		if ($self->is_locally_present() || !$self->is_aptgetable($APT_LOCAL)) {
			$self->{_apt_loc} = undef;
		} else {
			# Need --force-yes --yes to bypass downgrade warning
			my $aptcmd = aptget_lockwait()	. " --ignore-breakage --force-yes "
				. "--yes --print-uris install "
				. sprintf("\Q%s=%s", $self->get_name(), $self->get_fullversion())
				. " 2>/dev/null";

			my $line;
			open APT, "-|", $aptcmd or return undef; # Fail silently
			$line = $_ while (<APT>);
			close APT;

			if ($line =~ m,^'file:(/\S+\.deb)',) {
				$self->{_apt_loc} = $1;
			} else {
				$self->{_apt_loc} = undef;
			}
		}
	}

	return $self->{_apt_loc};
}

}

=item is_locally_present

  my $bool = $pv->is_locally_present;

Find whether or not there is a .deb built locally which can be used to
install this package.

=cut

sub is_locally_present {
	my $self = shift;

	return defined $self->find_local_debfile();
}


=item is_present

  my $bool = $pv->is_present;

Find whether or not there is an existing .deb that can be used to install
this package.

=cut

### Do not change API! This is used by FinkCommander (fpkg_list.pl)

sub is_present {
	my $self = shift;

	if (defined $self->find_debfile()) {
		return 1;
	}
	return 0;
}

### Do not change API! This is used by FinkCommander (fpkg_list.pl)

sub is_installed {
	my $self = shift;

	if ((&version_cmp(Fink::Status->query_package($self->{_name}), '=', $self->get_fullversion())) or
	   (&version_cmp(Fink::VirtPackage->query_package($self->{_name}), '=', $self->get_fullversion()))) {
		return 1;
	}
	return 0;
}

# find_tarball [ SUFFIX ]
#
# Returns the path of the downloaded tarball for a given SourceN suffix.
# If no suffix is given, returns the primary source tarball's path.
# On error (eg: nonexistent suffix) returns undef.
sub find_tarball {
	my $self = shift;
	my $suffix = shift || "";
	my ($archive, $found_archive);
	my (@search_dirs, $search_dir);

	$archive = $self->get_tarball($suffix);
	return undef if !defined $archive;   # bad suffix

	# compile list of dirs to search
	@search_dirs = ( "$basepath/src" );
	if ($config->has_param("FetchAltDir")) {
		push @search_dirs, $config->param("FetchAltDir");
	}

	# search for archive
	foreach $search_dir (@search_dirs) {
		$found_archive = "$search_dir/$archive";
		if (-f $found_archive) {
			return $found_archive;
		}
	}
	return undef;
}

=item find_local_debfile

  my $path = $pv->find_local_debfile;

Find a path to an existing .deb for this package, which is known to be built
on this system. If no such .deb exists, return undef.

=cut

sub find_local_debfile {
	my $self = shift;
	my ($path, $fn, $debname);

	# first try a local .deb in the dists/ tree
	$debname = $self->get_debname();
	foreach $path (@{$self->{_debpaths}}, "$basepath/fink/debs") {
		$fn = "$path/$debname";
		if (-f $fn) {
			return $fn;
		}
	}
	return undef;
}

=item find_debfile

  my $path = $pv->find_debfile;

Find a path to an existing .deb for this package. If no such .deb exists,
return undef.

=cut

sub find_debfile {
	my $self = shift;

	# first try a local .deb in the dists/ tree
	my $fn = $self->find_local_debfile();
	return $fn if defined $fn;

	# maybe it's available from the bindist?
	if ($config->binary_requested()) {
		my $epoch = $self->get_epoch();
		# Fix for Debarch since Apt converts _ into %5f
		my $debarch = $config->param('Debarch');
		$debarch =~ s/_/%5f/g;
		# the colon (':') for the epoch needs to be url encoded to
		# '%3a' since likes to store the debs in its cache like this
		$fn = sprintf "%s/%s_%s%s-%s_%s.deb",
			"$basepath/var/cache/apt/archives",
			$self->get_name(),
			$epoch ? $epoch.'%3a' : '',
			$self->get_version(),
			$self->get_revision(),
			$debarch;
		if (-f $fn) {
			return $fn;
		}

		# Try the local apt location
		$fn = $self->local_apt_location();
		return $fn if defined $fn;
	}

	# not found
	return undef;
}

### get dependencies

# usage: @deplist = $self->resolve_depends($include_build, $field, $forceoff);
# where:
#   $self is a PkgVersion object
#   $include_build indicates what type of dependencies one wants:
#     0 - return runtime dependencies only (default if undef)
#     1 - return runtime & build dependencies
#     2 - return build dependencies only
#   $field is either "depends" or "conflicts" (case-insensitive)
#   $forceoff is a boolean (default is false) that indicates...something
#
#   @deplist is list of refs to lists of PkgVersion objects
#     @deplist joins the referenced lists as logical AND
#     each referenced list is joined as logical OR
#     In "depends" mode, must have at least one of each sublist installed
#     In "conflicts" mode, must have none of any sublist installed
#     (but makes no sense to have logical OR in a *Conflicts field)

sub resolve_depends {
	my $self = shift;
	my $include_build = shift || 0;	# FIXME: Kind of badly named... maybe also add an $include_runtime var?
	my $include_runtime = ($include_build < 2) ? 1 : 0;
	my $field = shift;
	my $forceoff = shift || 0;

	my @deplist;    # list of lists of PkgVersion objects to be returned

	my $splitoff;   # used for merging in splitoff-pkg data
	my $oper;       # used in error and warning messages

	if (lc($field) eq "conflicts") {
		$oper = "conflict";
	} elsif (lc($field) eq "depends") {
		$oper = "dependency";
	} else {
		die "resolve_depends: invalid param field=$field, must equal 'Depends' or 'Conflicts'!\n";
	}

	# check for BuildDependsOnly and obsolete-dependency violations
	# if we will be building the package from source
	if ($include_build) {
		my $violated = 0;
		foreach my $pkg ($self->get_splitoffs(1,1)) {
			$violated = 1 if $pkg->check_bdo_violations();
			$violated = 1 if $pkg->check_obsolete_violations();
		}
		if ($violated) {
			if (Fink::Config::get_option("validate") eq "on") {
				die "Please correct the above problems and try again!\n";
			}
		}
	}

	my $verbosity = $config->verbosity_level();

	@deplist = ();

	# Inner subroutine; attention, we exploit closure effects heavily!!
	my $resolve_altspec = sub {
		my $pkglist = shift;
		my $filter_splitoffs = shift || 0;

		my @speclist;   # list of logical OR clusters (strings) of pkg specifiers
		my $altspecs;   # iterator for looping through @speclist

		my @altspec;    # list of pkg specifiers (strings) in a logical OR cluster
		my $depspec;    # iterator for looping through @altspec
		my $altlist;    # ref to list of PkgVersion objects meeting an OR cluster
		my $splitoff;

		@speclist = split(/\s*\,\s*/, $pkglist);

		# Loop over all specifiers and try to resolve each.
		SPECLOOP: foreach $altspecs (@speclist) {
			# A package spec(ification) may consist of multiple alternatives, e.g. "foo | quux (>= 1.0.0-1)"
			# So we need to break this down into pieces (this is done by get_altspec),
			# and then try to satisfy at least one of them.
			$altlist = [];
			@altspec = $self->get_altspec($altspecs);
			foreach $depspec (@altspec) {
				my $depname = $depspec->{'depname'};
				my $versionspec = $depspec->{'versionspec'};

				if ($include_build and defined $self->parent_splitoffs and
					 ($filter_splitoffs or not $include_runtime)) {
					# To prevent circular refs in the build dependency graph, we have to
					# remove all our splitoffs from the graph. We do this by pretending
					# that they are always present and thus any dependency involving them
					# is automatically satisfied.
					# Exception: any splitoffs this master depends on directly are not
					# filtered. Exception from the exception: if we were called by a
					# splitoff to determine the "meta dependencies" of it, then we again
					# filter out all splitoffs. If you've read till here without mental
					# injuries, congrats :-)
					next SPECLOOP if ($depname eq $self->{_name});
					foreach $splitoff ($self->parent_splitoffs) {
						next SPECLOOP if ($depname eq $splitoff->get_name());
					}
				}

				my $package = Fink::Package->package_by_name($depname);

				if (defined $package) {
					if ($versionspec =~ /^\s*$/) {
						# versionspec empty / consists of only whitespace
						push @$altlist, $package->get_all_providers( unique_provides => 1 );
					} else {
						push @$altlist, $package->get_matching_versions($versionspec);
					}
				} else {
					if ($verbosity > 2) {
						print "WARNING: While resolving $oper \"$depname" .
							(defined $versionspec && length $versionspec ? " " . $versionspec : '')
							 . "\" for package \"".$self->get_fullname()."\", package \"$depname\" was not found.\n";
					}
				}
			}

			if (scalar(@$altlist) <= 0) {
				if (lc($field) eq "depends") {
					die_breaking "Can't resolve $oper \"$altspecs\" for package \""
						. $self->get_fullname()
						. "\" (no matching packages/versions found)\n";
				} else {
					if ($forceoff) { # FIXME: Why $forceoff ??
						print "WARNING: Can't resolve $oper \"$altspecs\" for package \""
							. $self->get_fullname()
							. "\" (no matching packages/versions found)\n";
					}
				}
			}

			push @deplist, $altlist;
		}
	}; # end of sub resolve_altspec

	# Add build time dependencies / conflicts
	if ($include_build) {
		# If this is a splitoff, and we are asked for build depends, add the build deps
		# of the master package to the list.
		if ($self->has_parent) {
			push @deplist, $self->get_parent->resolve_depends(2, $field, $forceoff);
			if (not $include_runtime) {
				# The pure build deps of a splitoff are equivalent to those of the parent.
				return @deplist;
			}
		}

		# Add build time dependencies to the spec list
		if ($verbosity > 2) {
			print "Reading build $oper for ".$self->get_fullname()."...\n";
		}
		$resolve_altspec->($self->pkglist_default("Build".$field, ""));
	}

	# Add all regular dependencies to the list.
	if (lc($field) eq "depends") {
		# FIXME: Right now we completely ignore 'Conflicts' in the dep engine.
		# We leave handling them to dpkg. That is somewhat ugly, though, because it
		# means that 'Conflicts' are not automatically 'BuildConflicts' (i.e. the
		# behavior differs from 'Depends').
		# But right now, enabling conflicts would cause update problems (e.g.
		# when switching between 'wget' and 'wget-ssl')
		if ($verbosity > 2) {
			print "Reading $oper for ".$self->get_fullname()."...\n";
		}
		$resolve_altspec->($self->pkglist_default("Depends", ""));

		# Add RuntimeDepends if requested
		if ($include_runtime) {
			# Add build time dependencies to the spec list
			if ($verbosity > 2) {
				print "Reading runtime $oper for ".$self->get_fullname()."...\n";
			}
			$resolve_altspec->($self->pkglist_default("RuntimeDepends", ""));
		}

		# Add further build dependencies
		if ($include_build) {
			# dev-tools (a virtual package) is an implicit BuildDepends of all packages
			if ($self->get_name() ne 'dev-tools') {
				$resolve_altspec->('dev-tools');
			}

			# automatic BuildDepends:xz if any of the source fields are a .xz archive
			foreach my $suffix ($self->get_source_suffixes) {
				my $archive = $self->get_tarball($suffix);
				if ($archive =~ /\.xz$/) {
					$resolve_altspec->('xz');
					last;
				}
			}

			# If this is a master package with splitoffs, and build deps are requested,
			# then add to the list the deps of all our splitoffs.
			# We tell resolve_altspec (via its second parameters) to remove any
			# inter-splitoff deps that would otherwise be introduced by this.
			foreach $splitoff ($self->parent_splitoffs) {
				if ($verbosity > 2) {
					print "Reading $oper for ".$splitoff->get_fullname()."...\n";
				}
				$resolve_altspec->($splitoff->pkglist_default($field, ""), 1);
			}
		}
	}

	return @deplist;
}

# Take a dependency specification string from a dependency field like
# "foo | quux (>= 1.0.0-1)", and turn it into a list of pairs of the form
#    { depname => $depname, versionspec => $versionspec }
#
# So if the input string is "foo | quux (>= 1.0.0-1)",
# we output a list with content
#  ( { depname => "foo", versionspec => "" },
#    { depname => "quux", versionspec => ">= 1.0.0-1" } )
sub get_altspec {
	my $self     = shift;
	my $altspecs = shift;

	my ($depspec, $depname, $versionspec);
	my @specs;

	my @altspec = split(/\s*\|\s*/, $altspecs);
	foreach $depspec (@altspec) {
		if ($depspec =~ /^\s*([0-9a-zA-Z.\+-]+)\s*\((.+)\)\s*$/) {
			push(@specs, { depname => $1, versionspec => $2 });
		} elsif ($depspec =~ /^\s*([0-9a-zA-Z.\+-]+)\s*$/) {
			push(@specs, { depname => $1, versionspec => "" });
		}
	}

	return @specs;
}

=item get_depends

	my $lol_struct = $self->get_depends($want_build, $want_conflicts)

Get the dependency (or conflicts) package list. If $want_build is
true, return the compile-time package list; if it is false, return
only the runtime package list. If $want_conflicts is true, return the
antidependencies (conflicts) list; if it is false, return the
dependencies.

Compile-time dependencies (1,0) is the union of the BuildDepends of
the package family's parent package and the Depends of the whole
package family. Compile-time conflicts (1,1) is the BuildConflicts of
the parent of the package family. This method is not recursive in any
other sense.

This method returns pkgnames and other Depends-style string data in a
list-of-lists structure, unlike resolve_depends, which gives a flat
list of PkgVersion objects.

=cut

sub get_depends {
	my $self = shift;
	my $want_build = shift;
	my $want_conflicts = shift;

	# antidependencies require no special processing
	if ($want_conflicts) {
		if ($want_build) {
			# BuildConflicts is attribute of parent pkg only
			return &pkglist2lol($self->get_family_parent->pkglist_default("BuildConflicts",""));
		} else {
			# Conflicts is attribute of our own pkg only
			return &pkglist2lol($self->pkglist_default("Conflicts",""));
		}
	}

	my @lol;

	if ($want_build) {
		# build-time dependencies need to include whole family and
		# to remove whole family from also-runtime deplist

		my @family_pkgs = $self->get_splitoffs(1,1);

		@lol = map @{ &pkglist2lol($_->pkglist_default("Depends","")) }, @family_pkgs;
		&cleanup_lol(\@lol);  # remove duplicates (for efficiency)
		map $_->lol_remove_self(\@lol), @family_pkgs;

		# (not a runtime dependency so it gets added after remove-self games)
		push @lol, @{ &pkglist2lol($self->get_family_parent->pkglist_default("BuildDepends","")) };

		# automatic BuildDepends:xz if any of the source fields are a .xz archive
		foreach my $suffix ($self->get_source_suffixes) {
			my $archive = $self->get_tarball($suffix);
			push @lol, ['xz'] if $archive =~ /\.xz$/;
		}

	} else {
		# run-time dependencies
		@lol = @{ &pkglist2lol($self->pkglist_default("Depends","")) };
		push @lol, @{ &pkglist2lol($self->pkglist_default("RuntimeDepends","")) };
	}

	&cleanup_lol(\@lol);  # remove duplicates
	return \@lol;
}

=item check_bdo_violations

	my $bool = $self->check_bdo_violations;

Check if any packages in the Depends of this package are
BuildDependsOnly:true. If any violations found, warn about each such
case and return true. If not, return false.

All providers of each package name are checked and all alternatives
are tested. Only one warning is issued for each %n:Depends:%n'
combination over the lifetime of the fink process.

=cut

{
	# track which BuildDependsOnly violation warnings we've issued
	my %bdo_warning_cache = ();  # hash of "$pkg\0$dependency"=>1

sub check_bdo_violations {
	my $self = shift;

	# have we been here? (even more efficient than bdo_warning_cache!)
	return $self->{_BDO_violations} if exists $self->{_BDO_violations};

	$self->{_BDO_violations} = 0;

	# upgrade-compatibility packages should allow renaming of BDO packages
	return $self->{_BDO_violations} if $self->is_obsolete();

	# test all alternatives
	my @atoms = split /\s*[\,|]\s*/, $self->pkglist_default('Depends', '');
	push @atoms, split /\s*[\,|]\s*/, $self->pkglist_default('RuntimeDepends', '');

	foreach my $depname (@atoms) {
		$depname =~ s/\s*\(.*\)//;
		my $package = Fink::Package->package_by_name($depname);
		next unless defined $package;  # skip if no satisfiers
		foreach my $dependent ($package->get_all_providers()) {
			if ($dependent->param_boolean("BuildDependsOnly")) {
				$self->{_BDO_violations} = 1;

				if ($config->verbosity_level() > 1) {
					# whine iff this violation hasn't been whined-about before
					my $cache_key = $self->get_name() . "\0" . $depname;
					if (!$bdo_warning_cache{$cache_key}++) {
						my $dep_providername = $dependent->get_name();
						print "\nWARNING: The package " . $self->get_name() . " Depends on $depname";
						if ($dep_providername ne $depname) {
							# virtual pkg
							print "\n\t (which is provided by $dep_providername)";
						}
						print ",\n\t but $depname only allows things to BuildDepend on it.\n\n";
					}
				}
			}
		}
	}

	return $self->{_BDO_violations};
}

# check_bdo_violations has lexical private variables
}

=item check_obsolete_violations

	my $bool = $self->check_obsolete_violations;

Return a boolean indicating if any dependencies are "obsolete".
See the atom_is_obsolete method for details about the checking.

=cut

sub check_obsolete_violations {
	my $self = shift;

	# have we been here? (even more efficient than obs_warning_cache!)
	return $self->{_obsolete_violations} if exists $self->{_obsolete_violations};

	$self->{_obsolete_violations} = 0;

	foreach my $field (qw/ BuildDepends Depends RuntimeDepends Suggests Recommends /) {
		my @alt_sets = split /\s*,\s*/, $self->pkglist_default($field, "");

		# test each set of alternatives
		foreach my $alt_set (@alt_sets) {
			my @atoms = split /\s*\|\s*/, $alt_set;

			# check obsolete status of first satisfiable dependency
			foreach my $atom (@atoms) {
				if (defined (my $atom_obs = $self->atom_is_obsolete($atom, $field))) {
					$self->{_obsolete_violations} = 1 if $atom_obs;
					last;
				}
			}
		}
	}

	return $self->{_obsolete_violations};
}

=item atom_is_obsolete

	my $bool = $self->atom_is_obsolete($atom,$field);

Returns a boolean indicating if the first available provider of the
given dependency $atom in the given $field name is obsolete. All
versions of all providers of the given package name are checked
(versioning is disregarded). An undef is returned if nothing satisfies
the dependency atom.

If any obsolete dependencies are found, issue a warning. Only one
warning is issued for each %n:DEP_FIELDNAME:%n' combination over the
lifetime of the fink process.

=cut

{
	# track which BuildDependsOnly violation warnings we've issued
	my %obs_warning_cache = ();  # hash of "$pkg\0$deptype\0$dependency"=>1

	# used in warning messages
	my %dep_verbs = (qw/ depends on builddepends on suggests of recommends of /);

sub atom_is_obsolete {
	my $self = shift;
	my $atom = shift;
	my $field = shift;

	my $depname = $atom;
	$depname =~ s/\s*\(.*\)//;  # strip off versioning (we check all for now)
	my $package = Fink::Package->package_by_name($depname);
	return undef unless defined $package;  # skip if no satisfiers

	my $have_obsolete_deps = 0;

	foreach my $dependent ($package->get_all_providers()) {
		if ($dependent->is_obsolete()) {
			$have_obsolete_deps = 1;

			if ($config->verbosity_level() > 1) {
				# whine iff this violation hasn't been whined-about before
				my $cache_key = $self->get_name() . "\0" . $field . "\0" . $depname;
				if (!$obs_warning_cache{$cache_key}++) {
					my $dep_providername = $dependent->get_name();
					print "\nWARNING: The package " . $self->get_name() . " has a preferred $field";
					print " $dep_verbs{lc $field}" if exists $dep_verbs{lc $field};
					print " $depname";
					if ($dep_providername ne $depname) {
						# virtual pkg
						print "\n\t (which is provided by $dep_providername)";
					}
					print ",\n\t but $depname is an obsolete package.\n\n";
				}
			}
		}
	}

	return $have_obsolete_deps;
}

# atom_is_obsolete has lexical private variables
}

=item match_package

  my $result = Fink::PkgVersion->match_package($pkgspec, %opts);

Find a PkgVersion by matching a specification. Return undef
on failure.

Valid options are:

=over 4

=item quiet

Don't print messages. Defaults to false.

=item provides

This parameter controls what happens if no PkgVersion matches the
given specification, but a virtual package does.

If this parameter is 'return', then the Fink::Package object for the virtual
package is returned. The caller should test with $result->isa('Fink::Package')
to determine what sort of result it is looking at.

Otherwise, undef will be returned, just as if the specification could not
be resolved. The user will be warned that a virtual package was encountered
if not in quiet mode. This is the default.

=back

=cut

sub match_package {
	shift;	# class method - ignore first parameter
	my $s = shift;
	my %opts = (quiet => 0, provides => 0, @_);

	my ($pkgname, $package, $version, $pkgversion);
	my ($found, @parts, $i, @vlist, $v, @rlist);

	if ($config->verbosity_level() < 3) {
		$opts{quiet} = 1;
	}

	# first, search for package
	$found = 0;
	$package = Fink::Package->package_by_name($s);
	if (defined $package) {
		$found = 1;
		$pkgname = $package->get_name();
		$version = "###";
	} else {
		# try to separate version from name (longest match)
		@parts = split(/-/, $s);
		for ($i = $#parts - 1; $i >= 0; $i--) {
			$pkgname = join("-", @parts[0..$i]);
			$version = join("-", @parts[$i+1..$#parts]);
			$package = Fink::Package->package_by_name($pkgname);
			if (defined $package) {
				$found = 1;
				last;
			}
		}
	}
	if (not $found) {
		print "no package found for \"$s\"\n"
			unless $opts{quiet};
		return undef;
	}

	# we now have the package name in $pkgname, the package
	# object in $package, and the
	# still to be matched version (or "###") in $version.
	if ($version eq "###") {
		# find the newest version

		$version = &latest_version($package->list_versions());
		if (not defined $version) {
			# i guess it's provided then?
			if ($opts{provides} eq 'return') {
				return $package;
			}
			# choose provider for virtual package
			return $package->choose_virtual_pkg_provider;
		}
	} elsif (not defined $package->get_version($version)) {
		# try to match the version

		@vlist = $package->list_versions();
		@rlist = ();
		foreach $v (@vlist)	 {
			if ($package->get_version($v)->get_version() eq $version) {
				push @rlist, $v;
			}
		}
		$version = &latest_version(@rlist);
		if (not defined $version) {
			# there's nothing we can do here...
			print "no matching version found for $pkgname\n"
				unless $opts{quiet};
			return undef;
		}
	}

	return $package->get_version($version);
}

# Given a ref to a lol struct representing a depends line, remove all
# OR clusters satisfied by this PkgVersion (Package and Provides fields)

sub lol_remove_self {
	my $self = shift;
	my $lol = shift;

	my $self_pkg = $self->get_name();
	my $self_ver = $self->get_fullversion();

	# keys are all packages we supply (Package + Provides)
	my %provides = ($self_pkg => 1);   # pkg supplies itself
	map { $provides{$_}++ } split /\s*,\S*/, $self->pkglist_default("Provides", "");

#	print "lol_remove_self was (", &lol2pkglist($lol), ") for $self_pkg-$self_ver\n";

	my ($cluster, $atom);
	foreach $cluster (@$lol) {
		next unless defined $cluster;  # skip deleted clusters
#		print "cluster: ", join(' | ', @$cluster), "\n";
		foreach $atom (@$cluster) {
#			print "\tatom: '$atom'\n";
			if ($atom =~ /^\Q$self_pkg\E\s*\(\s*([<>=]+)\s*(\S*)\s*\)$/) {
				# pkg matches, has version dependency (op=$1, ver=$2)
#				print "\t\tmatched pkg, need ver $1$2\n";
				# check versioning
				if (&version_cmp($self_ver, $1, $2)) {
#					print "\t\tmatch\n";
					undef $cluster;  # atom matches so clear cluster
					last;            # cluster gone, skip to next one
				}
#				print "\t\tno match\n";
			} else {
#				print "\t\tnot self-with-version\n";
				next if $atom =~ /\(/;  # versioned-dep cannot match a Provides
#				print "\t\tno version at all\n";
#				print "\t\tchecking against providers: ", join(",", keys %provides), "\n";
				if (exists $provides{$atom}) {
#					print "\t\t\tmatch\n";
					undef $cluster;  # atom matches so clear cluster
					last;            # cluster gone, skip to next one
				}
#				print "\t\t\tno match\n";
			}
		}
	}

#	print "lol_remove_self now (", &lol2pkglist($lol), ")\n";
}

###
### PHASES
###

=item phase_fetch_deb

  $self->phase_fetch_deb();
  $self->phase_fetch_deb($conditional, $dryrun);
  $self->phase_fetch_deb($conditional, $dryrun, @packages);

Download the .deb files for some packages. If @packages is not specified, will
fetch the .deb for only this packages.

If $conditional is true, .deb files will only be fetched if they're not already
present (defaults to false).

If $dryrun is true, .deb files won't actually be fetched, but the process will
be simulated (defaults to false).

=cut

sub phase_fetch_deb {
	my $self = shift;
	my $conditional = shift || 0;
	my $dryrun = shift || 0;
	my @packages = @_ ? @_ : ($self);

	# check if $basepath is really '/sw' since the debs are built with
	# '/sw' hardcoded
	#
	if (my $err = $config->bindist_check_prefix) {
		print "\n"; print_breaking("ERROR: $err");
		die "Downloading the binary package '" . $self->get_debname() . "' failed.\n";
	}

	for my $pkg (@packages) {
		if (not $conditional) {
			# delete already downloaded deb
			my $found_deb = $pkg->find_debfile();
			if ($found_deb) {
				rm_f $found_deb;
			}
		}
	}
	$self->fetch_deb($dryrun, @packages);
}

=item fetch_deb

  $self->fetch_deb($dryrun, @packages);

Unconditionally download the .deb files for some packages. Die if apt-get
fails.

=cut

sub fetch_deb {
	my $self = shift;
	my $dryrun = shift || 0;
	my @packages = @_;
	next unless @packages;

	my @names = sort map { $_->get_debname() } @packages;
	if ($config->verbosity_level() > 2) {
		print "Downloading " . join(', ', @names) . " from binary dist.\n";
	}
	my $aptcmd = aptget_lockwait() . " ";
	if ($config->verbosity_level() == 0) {
		$aptcmd .= "-qq ";
	} elsif ($config->verbosity_level() < 2) {
		$aptcmd .= "-q ";
	}
	if ($dryrun) {
		$aptcmd .= "--dry-run ";
	}
	# Newer apt does a sign authentication, since we don't have that in
	# place yet, we need to ignore it.  That way it doesn't stop for
	# interaction, not to mention it defaults to 'N'. 0.6.8 is required!
	#$aptcmd .= "--allow-unauthenticated ";
	$aptcmd .= "--ignore-breakage --download-only install " .
		join(' ', map {
			sprintf "%s=%s", $_->get_name(), $_->get_fullversion
		} @packages);
	# set proxy env vars
	my $http_proxy = $config->param_default("ProxyHTTP", "");
	if ($http_proxy) {
		$ENV{http_proxy} = $http_proxy;
		$ENV{HTTP_PROXY} = $http_proxy;
	}
	my $ftp_proxy = $config->param_default("ProxyFTP", "");
	if ($ftp_proxy) {
		$ENV{ftp_proxy} = $ftp_proxy;
		$ENV{FTP_PROXY} = $ftp_proxy;
	}
	if (&execute($aptcmd)) {
#		print "\n";
#		&print_breaking("Downloading '".$self->get_debname()."' failed. ".
#		                "There can be several reasons for this:");
#		&print_breaking("The server is too busy to let you in or ".
#		                "is temporarily down. Try again later.",
#		                1, "- ", "	");
#		&print_breaking("There is a network problem. If you are ".
#		                "behind a firewall you may want to check ".
#		                "the proxy and passive mode FTP ".
#		                "settings. Then try again.",
#		                1, "- ", "	");
#		&print_breaking("The file was removed from the server or ".
#		                "moved to another directory. The package ".
#		                "description must be updated.");
#		print "\n";
		my $msg = "Downloading at least one of the following binary packages "
			. "failed:\n" . join('', map { sprintf "  %s\n", $_ } @names);
		if ($dryrun) {
			print $msg;
		} else {
			die $msg;
		}

		# FIXME: Should we check is_present to make sure the download really
		# succeeded? Or just fail silently and hope things work out in the end?
	}
}

### fetch

sub phase_fetch {
	my $self = shift;
	my $conditional = shift || 0;
	my $dryrun = shift || 0;
	my ($suffix);

	if ($self->has_parent) {
		($self->get_parent)->phase_fetch($conditional, $dryrun);
		return;
	}
	if ($self->is_type('bundle') || $self->is_type('nosource') ||
			lc $self->get_source() eq "none" ||
			$self->is_type('dummy')) {
		return;
	}

	foreach $suffix ($self->get_source_suffixes) {
		if (not $conditional) {
			$self->fetch_source($suffix, 0, 0, 0, $dryrun);
		} elsif (not $dryrun) {
			$self->fetch_source_if_needed($suffix);
			# fetch_source_if_needed doesn't work with dryrun
		} elsif (not defined $self->find_tarball($suffix)) {
			$self->fetch_source($suffix, 0, 0, 0, $dryrun);
		}
	}
}

=item fetch_source_if_needed

	my $archive = $pv->fetch_source_if_needed($suffix);

Makes sure that the sourcefile indicated by $suffix is downloaded and has the
correct checksums. If the file can't be found, it is downloaded. If it exists,
but has the wrong checksums, we ask the user what to do.

=cut

sub fetch_source_if_needed {
	my $self = shift;
	my $suffix = shift;

	my $archive = $self->get_tarball($suffix);

	# search for archive, try fetching if not found
	my $found_archive = $self->find_tarball($suffix);
	if (not defined $found_archive) {
		return $self->fetch_source($suffix);
	}

	# verify the MD5 checksum, if specified
	my $checksum = $self->get_checksum($suffix);

	if (not defined $checksum) {
		# No checksum was specifed in the .info file, die die die
		my %archive_sums = %{Fink::Checksum->get_all_checksums($found_archive)};
		die "No checksum specifed for Source$suffix of ".$self->get_fullname()."\nActual: " .
			join("        ", map "$_($archive_sums{$_})\n", sort keys %archive_sums);
	}

	# compare to the MD5 checksum of the tarball
	if (not Fink::Checksum->validate($found_archive, $self->get_checksum($suffix))) {
		# mismatch, ask user what to do
		my %archive_sums = %{Fink::Checksum->get_all_checksums($found_archive)};
		my $sel_intro = "The checksum of the file $archive of package ".
			$self->get_fullname()." is incorrect. The most likely ".
			"cause for this is a corrupted or incomplete download\n".
			"Expected: $checksum\nActual: " .
							  join("        ", map "$_($archive_sums{$_})\n", sort keys %archive_sums) .
			"It is recommended that you download it ".
			"again. How do you want to proceed?";
		my $answer = &prompt_selection("Make your choice: ",
						intro   => $sel_intro,
						default => [ value => "redownload" ],
						choices => [
						  "Give up" => "error",
						  "Delete it and download again" => "redownload",
						  "Assume it is a partial download and try to continue" => "continuedownload",
						  "Don't download, use existing file" => "continue"
						],
						category => 'fetch',);
		if ($answer eq "redownload") {
			rm_f $found_archive;
			# Axel leaves .st files around for partial files, need to remove
			if($config->param_default("DownloadMethod") =~ /^axel/)
			{
				rm_f "$found_archive.st";
			}
			$found_archive = $self->fetch_source($suffix, 1);
		} elsif($answer eq "error") {
			die "checksum of file $archive of package ".$self->get_fullname()." incorrect\n";
		} elsif($answer eq "continuedownload") {
			$found_archive = $self->fetch_source($suffix, 1, 1);
		}
	}

	return $found_archive;
}

# fetch_source SUFFIX, [ TRIES ], [ CONTINUE ], [ NOMIRROR ], [ DRYRUN ]
#
# Unconditionally download the source for a given SourceN suffix, dying on
# failure. Returns the path to the downloaded source archive if dryrun is not
# specified.
sub fetch_source {
	my $self = shift;
	my $suffix = shift;
	my $tries = shift || 0;
	my $continue = shift || 0;
	my $nomirror = shift || 0;
	my $dryrun = shift || 0;

	chdir "$basepath/src";

	my $url = $self->get_source($suffix);
	my $file = $self->get_tarball($suffix);
	$nomirror = 1 if $self->get_license() =~ /^(Commercial|Restrictive)$/i;

	my($checksum_type, $checksum) = Fink::Checksum->parse_checksum($self->get_checksum($suffix));

	if ($dryrun) {
		return if $url eq $file; # just a simple filename
		print "$file ", (defined $checksum ? lc($self->get_checksum_type($suffix)) . '=' . $checksum : "-");
	} else {
		if (not defined $checksum) {
			print "WARNING: No checksum specified for Source".$suffix.
							" of package ".$self->get_fullname();
			if ($self->has_param("Maintainer")) {
				print ' Maintainer: '.$self->param("Maintainer") . "\n";
			} else {
				print "\n";
			}
		}
	}

	if (&fetch_url_to_file($url, $file, $self->get_custom_mirror($suffix),
						   $tries, $continue, $nomirror, $dryrun, undef, $checksum, $checksum_type)) {

		if (0) {
		print "\n";
		&print_breaking("Downloading '$file' from the URL '$url' failed. ".
						"There can be several reasons for this:");
		&print_breaking("The server is too busy to let you in or ".
						"is temporarily down. Try again later.",
						1, "- ", "	");
		&print_breaking("There is a network problem. If you are ".
						"behind a firewall you may want to check ".
						"the proxy and passive mode FTP ".
						"settings. Then try again.",
						1, "- ", "	");
		&print_breaking("The file was removed from the server or ".
						"moved to another directory. The package ".
						"description must be updated.",
						1, "- ", "	");
		&print_breaking("The package specifies an incorrect checksum ".
						"for the file.",
						1, "- ", "	");
		&print_breaking("In any case, you can download '$file' manually and ".
						"put it in '$basepath/src', then run fink again with ".
						"the same command. If you have checksum problems, ".
						"make sure you have  updated your package ".
						"recently; contact the package maintainer.");
		print "\n";
		}
		if ($dryrun) {
			if ($self->has_param("Maintainer")) {
				print ' "'.$self->param("Maintainer") . "\"\n";
			}
		} else {
			die "file download failed for $file of package ".$self->get_fullname()."\n";
		}
	} else {
		my $found_archive = $self->find_tarball($suffix);
		if (not defined $found_archive) {
			my $archive = $self->get_tarball($suffix);
			die "can't find source file $archive for package ".$self->get_fullname()."\n";
		}
		return $found_archive;
	}
}

### unpack

sub phase_unpack {
	my $self = shift;
	my ($archive, $found_archive, $bdir, $destdir, $unpack_cmd);
	my ($suffix, $verbosity);
	my ($renamefield, @renamefiles, $renamefile, $renamelist, $expand);
	my ($tarcommand, $tarflags, $cat, $gzip, $bzip2, $unzip, $xz);
	my ($tar_is_pax,$alt_bzip2)=(0,0);
	my $build_as_user_group = $self->pkg_build_as_user_group();

	$config->mixed_arch(msg=>'build a package', fatal=>1);

	if ($self->is_type('bundle') || $self->is_type('dummy')) {
		return;
	}
	if ($self->has_parent) {
		($self->get_parent)->phase_unpack();
		return;
	}

	if ($self->has_param("GCC")) {
		my $gcc_abi = $self->param("GCC");
		my $name = $self->get_fullname();
		Fink::Services::enforce_gcc(<<GCC_MSG, $gcc_abi);
The package $name must be compiled with gcc EXPECTED_GCC,
however, you currently have gcc INSTALLED_GCC selected.
This typically is due to alteration of symlinks which were
installed by Xcode. To correct this problem, you will need
to restore the compiler symlinks to the configuration that
Apple provides.
GCC_MSG
	}

	$bdir = $self->get_fullname();

	$verbosity = "";
	if ($config->verbosity_level() > 1) {
		$verbosity = "v";
	}

	# remove dir if it exists
	chdir "$buildpath";
	if (-e $bdir) {
		rm_rf $bdir or
			die "can't remove existing directory $bdir\n";
	}

	if ($self->is_type('nosource') || lc $self->get_source() eq "none") {
		$destdir = "$buildpath/$bdir";
		mkdir_p $destdir or
			die "can't create directory $destdir\n";
		chowname $build_as_user_group->{'user:group'}, $destdir or
			die "can't chown '" . $build_as_user_group->{'user:group'} . "' $destdir\n";
		return;
	}

	foreach $suffix ($self->get_source_suffixes) {
		$archive = $self->get_tarball($suffix);
		# We verified that the tar file exists with the right checksum during
		# the fetch phase. This second check is redundant, but just in case...
		$found_archive = $self->fetch_source_if_needed($suffix);

		# Determine the name of the TarFilesRename in the case of multi tarball packages
		$renamefield = "Tar".$suffix."FilesRename";
		$renamelist = "";

		$tarflags = "-x${verbosity}f";
		my $permissionflags = " --no-same-owner --no-same-permissions";

		# set up "tar"
		# Determine the rename list ; if not present then then move on.
		if ($self->has_param($renamefield)) { # we need pax
			@renamefiles = split(' ', $self->param($renamefield));
			foreach $renamefile (@renamefiles) {
				$renamefile = &expand_percent($renamefile, $expand, $self->get_info_filename." \"$renamefield\"");
				if ($renamefile =~ /^(.+)\:(.+)$/) {
					$renamelist .= " -s ,$1,$2,";
				} else {
					$renamelist .= " -s ,${renamefile},${renamefile}_tmp,";
				}
			}
			$tarcommand = "/bin/pax -r${verbosity}"; # Use pax for extracting with the renaming feature
			$tar_is_pax = 1; # Flag denoting that we're using pax
		} elsif ( -e "$basepath/bin/tar" ) {
			$tarcommand = "env LANG=C LC_ALL=C $basepath/bin/tar $permissionflags $tarflags"; # Use Fink's GNU Tar if available
			$tar_is_pax=0;
		} elsif ( -e "/usr/bin/gnutar" ) {
			$tarcommand = "/usr/bin/gnutar $permissionflags $tarflags"; # Apple's GNU tar
			$tar_is_pax=0;
		} else {
			$tarcommand = "/usr/bin/tar $permissionflags $tarflags"; # probably BSD tar
			$tar_is_pax=0;
		}

		$bzip2 = $config->param_default("Bzip2path", 'bzip2');
		$bzip2 = 'bzip2' unless (-x $bzip2);
		$alt_bzip2=1 if ($bzip2 ne 'bzip2');
		$unzip = "unzip";
		$gzip = "gzip";
		$cat = "/bin/cat";
		$xz= "xz";

		# Determine unpack command
		# print "\n$tar_is_pax\n";
		$unpack_cmd = "/bin/cp $found_archive ."; # non-archive file
		# check for a tarball
		if ($archive =~ /[\.\-]tar(\.(gz|z|Z|bz2|xz))?$/ or $archive =~ /[\.\-]t[gbx]z$/) {
			if (!$tar_is_pax) {  # No TarFilesRename
				# Using "bzip2" for "bzip2" or if we're not on a bzipped tarball
				if (!($alt_bzip2 and $archive =~ /[\.\-]t(ar\.)?bz2?$/)) {
					$unpack_cmd = "$tarcommand $found_archive"; #let tar figure it out
				} else { # we're on a bzipped tar archive with an alternative bzip2
					$unpack_cmd = "$bzip2 -dc $found_archive | $tarcommand -";
				}
			# Otherwise we're using pax and need to iterate through the uncompress options:
			} elsif ($archive =~ /[\.\-]tar\.(gz|z|Z)$/ or $archive =~ /\.tgz$/) {
				$unpack_cmd = "$gzip -dc $found_archive | $tarcommand $renamelist";
			} elsif ($archive =~ /[\.\-]t(ar\.)?bz2?$/) {
				$unpack_cmd = "$bzip2 -dc $found_archive | $tarcommand $renamelist";
			} elsif ($archive =~ /[\.\-]tar\.xz$/) {
				$unpack_cmd = "$xz -dc $found_archive | $tarcommand $renamelist";
			} elsif ($archive =~ /[\.\-]tar$/) {
				$unpack_cmd = "$cat $found_archive | $tarcommand $renamelist";
			}
		# Zip file
		} elsif ($archive =~ /\.(zip|ZIP)$/) {
			$unpack_cmd = "$unzip -o $found_archive";
		}

		# calculate destination directory
		$destdir = "$buildpath/$bdir";
		if ($suffix ne "") {	# Primary sources have no special extract dir
			my $extractparam = "Source".$suffix."ExtractDir";
			if ($self->has_param($extractparam)) {
				$destdir .= "/".$self->param_expanded($extractparam);
			}
		}

		# create directory
		if (! -d $destdir) {
			mkdir_p $destdir or
				die "can't create directory $destdir\n";
			chowname $build_as_user_group->{'user:group'}, $destdir or
				die "can't chown '" . $build_as_user_group->{'user:group'} . "' $destdir\n";
		}

		# unpack it
		chdir $destdir;
		$self->run_script($unpack_cmd, "unpacking '$archive'", 1, 1);
	}
}

### patch

sub phase_patch {
	my $self = shift;
	my ($dir, $patch_script, $cmd, $patch, $subdir);

	$config->mixed_arch(msg=>'build a package', fatal=>1);

	if ($self->is_type('bundle') || $self->is_type('dummy')) {
		return;
	}
	if ($self->has_parent) {
		($self->get_parent)->phase_patch();
		return;
	}

	$dir = $self->get_build_directory();
	if (not -d "$buildpath/$dir") {
		die "directory $buildpath/$dir doesn't exist, check the package description\n";
	}
	chdir "$buildpath/$dir";

	$patch_script = "";

	### copy host type scripts (config.guess and config.sub) if required

	if ($self->param_boolean("UpdateConfigGuess")) {
		$patch_script .=
			"/bin/cp -f $libpath/update/config.guess .\n".
			"/bin/cp -f $libpath/update/config.sub .\n";
	}
	if ($self->has_param("UpdateConfigGuessInDirs")) {
		foreach $subdir (split(/\s+/, $self->param("UpdateConfigGuessInDirs"))) {
			next unless $subdir;
			$patch_script .=
				"/bin/cp -f $libpath/update/config.guess $subdir\n".
				"/bin/cp -f $libpath/update/config.sub $subdir\n";
		}
	}

	### copy libtool scripts (ltconfig and ltmain.sh) if required

	if ($self->param_boolean("UpdateLibtool")) {
		$patch_script .=
			"/bin/cp -f $libpath/update/ltconfig .\n".
			"/bin/cp -f $libpath/update/ltmain.sh .\n";
	}
	if ($self->has_param("UpdateLibtoolInDirs")) {
		foreach $subdir (split(/\s+/, $self->param("UpdateLibtoolInDirs"))) {
			next unless $subdir;
			$patch_script .=
				"/bin/cp -f $libpath/update/ltconfig $subdir\n".
				"/bin/cp -f $libpath/update/ltmain.sh $subdir\n";
		}
	}

	### copy po/Makefile.in.in if required

	if ($self->param_boolean("UpdatePoMakefile")) {
		$patch_script .=
			"/bin/cp -f $libpath/update/Makefile.in.in po/\n";
	}

	### run what we have so far
	$self->run_script($patch_script, "patching (Update* flags)", 0, 1);
	$patch_script = "";

	### new-style checksummed patchfile
	if ($self->get_patchfile_suffixes()) {
		if ($self->has_param('Patch')) {
			die "Cannot specify both Patch and PatchFile!\n";
		}
		my $dir_checked;
		for my $suffix ($self->get_patchfile_suffixes()) {
			# field contains simple filename with %-exp
			# figure out actual absolute filename
			my $file = &expand_percent("\%{PatchFile$suffix}", $self->{_expand}, $self->get_info_filename." \"PatchFile$suffix\"");

			# file exists
			die "Cannot read PatchFile$suffix \"$file\"\n" unless -r $file;

			# verify the checksum matches (at least one of -Checksum or -MD5 must be present)
			if (not $self->has_param("PatchFile$suffix-MD5") and not $self->has_param("PatchFile$suffix-Checksum")) {
				die "No checksum specified for PatchFile$suffix \"$file\"!\n";
			}
			if ($self->has_param("PatchFile$suffix-Checksum")) {
				my $checksum = $self->param("PatchFile$suffix-Checksum");
				if (not Fink::Checksum->validate($file, $checksum)) {
					my %archive_sums = %{Fink::Checksum->get_all_checksums($file)};
					die "PatchFile$suffix \"$file\" checksum does not match!\n".
						"Expected: $checksum\nActual: " .
						join("        ", map "$_($archive_sums{$_})\n", sort keys %archive_sums);
				}
			}
			if ($self->has_param("PatchFile$suffix-MD5")) {
				my $checksum = "MD5(" . $self->param("PatchFile$suffix-MD5") . ")";
				if (not Fink::Checksum->validate($file, $checksum)) {
					my %archive_sums = %{Fink::Checksum->get_all_checksums($file)};
					die "PatchFile$suffix \"$file\" checksum does not match!\n".
						"Expected: $checksum\nActual: " .
						join("        ", map "$_($archive_sums{$_})\n", sort keys %archive_sums);
				}
			}

			# check that we're contained in a world-executable directory
			unless ($dir_checked) {
				my ($status,$dir) = is_accessible(dirname($file),'01');
				die "$dir and its contents need to have at least o+x permissions. Run:\n\n".
					"sudo /bin/chmod -R o+x $dir\n\n" if $dir;
				$dir_checked=1;
			}

			# make sure patchfile exists and can be read by the user (root
			# or nobody) who is doing the build
			$self->run_script("[ -r $file ]", "patching (PatchFile \"$file\" readability)", 1, 1);
		}
	}

	### patches specified by filename
	if ($self->has_param("Patch")) {
		die "\"Patch\" is no longer supported\n";
	}

	### Deal with PatchScript field
	$self->run_script($self->get_script("PatchScript"), "patching", 1, 1);
}

### compile

sub phase_compile {
	my $self = shift;
	my ($dir, $compile_script, $cmd);

	$config->mixed_arch(msg=>'build a package', fatal=>1);

	my $notifier = Fink::Notify->new();

	if ($self->is_type('bundle')) {
		return;
	}
	if ($self->is_type('dummy') and not $self->has_param('CompileScript')) {
		my $error = "can't build ".$self->get_fullname().
				" because no package description is available";
		$notifier->notify(event => 'finkPackageBuildFailed', description => $error);
		die "compile phase: $error\n";
	}
	if ($self->has_parent) {
		($self->get_parent)->phase_compile();
		return;
	}

	if (!$self->is_type('dummy')) {
		# dummy packages do not actually compile (so no build dir),
		# but they can have a CompileScript to run
		$dir = $self->get_build_directory();
		if (not -d "$buildpath/$dir") {
			my $error = "directory $buildpath/$dir doesn't exist, check the package description";
			$notifier->notify(event => 'finkPackageBuildFailed', description => $error);
			die "compile phase: $error\n";
		}
		chdir "$buildpath/$dir";
	}

	### construct CompileScript and execute it
	$self->run_script($self->get_script("CompileScript"), "compiling", 1, 1);

	if (Fink::Config::get_option("tests")) {
		my $result = $self->run_script($self->get_script("TestScript"), "testing", 1, 1, 1);

		if ($result == 1) {
			warn "phase test: warning\n";
		} elsif ($result) {
			$self->package_error( phase => 'testing', nonfatal => (Fink::Config::get_option("tests") ne "on") );
			print "Continuing anyway as requested.\n";
		} else {
			warn "phase test: passed\n";
		}
	}
}

### install

sub phase_install {
	my $self = shift;
	my $do_splitoff = shift || 0;
	my ($dir, $install_script, $cmd, $bdir);

	$config->mixed_arch(msg=>'build a package', fatal=>1);

	my $notifier = Fink::Notify->new();

	if ($self->is_type('dummy')) {
		my $error = "can't build ".$self->get_fullname().
				" because no package description is available";
		$notifier->notify(event => 'finkPackageBuildFailed', description => $error);
		die "install phase: $error\n";
	}
	if ($self->has_parent and not $do_splitoff) {
		($self->get_parent)->phase_install();
		return;
	}
	if (not $self->is_type('bundle')) {
		if ($do_splitoff) {
			$dir = ($self->get_parent)->get_build_directory();
		} else {
			$dir = $self->get_build_directory();
		}
		if (not -d "$buildpath/$dir") {
			my $error = "directory $buildpath/$dir doesn't exist, check the package description";
			$notifier->notify(event => 'finkPackageBuildFailed', description => $error);
			die "install phase: $error\n";
		}
		chdir "$buildpath/$dir";
	}

	# generate installation script

	$install_script = "";
	unless ($self->{_bootstrap}) {
		$install_script .= "/bin/rm -rf \%d\n";
	}
	$install_script .= "/bin/mkdir -p \%i\n";
	unless ($self->{_bootstrap}) {
		my $build_as_user_group = $self->pkg_build_as_user_group();
		$install_script .= "/bin/mkdir -p \%d/DEBIAN\n";
		$install_script .= "/usr/sbin/chown -R " . $build_as_user_group->{'user:group'} . " \%d\n";
	}
	# Run the script part we have so far (NB: parameter-value
	# "installing" is specially recognized by run_script!)
	$self->run_script($install_script, "installing", 0, 0);
	$install_script = ""; # reset it
	# Now run the actual InstallScript (NB: parameter-value
	# "installing" is specially recognized by run_script!)
	$self->run_script($self->get_script("InstallScript"), "installing", 1, 1);
	if (!$self->is_type('bundle')) {
		# Handle remaining fields that affect installation
		if ($self->param_boolean("UpdatePOD")) {
			# grab perl version, if present
			my ($perldirectory, $perlarchdir) = $self->get_perl_dir_arch();

			$install_script .=
				"/bin/mkdir -p \%i/share/podfiles$perldirectory\n".
				"for i in `find \%i -name perllocal.pod`; do /bin/cat \$i | sed -e s,\%i/lib/perl5,\%p/lib/perl5, >> \%i/share/podfiles$perldirectory/perllocal.\%n.pod; /bin/rm -rf \$i; done;\n";
		}
	}

	# splitoff 'Files' field
	if ($do_splitoff and $self->has_param("Files")) {
		my $files = $self->param_expanded("Files");
		$files =~ s/\s+/ /g; # Make it one line
		$files = $self->conditional_space_list($files,
			"Files of ".$self->get_fullname()." in ".$self->get_info_filename
		);

		my %target_dirs = ();  # keys are dirs that have already been created

		foreach my $file (split /\s+/, $files) {
			my ($source, $target);
			$file =~ s/\%/\%\%/g;   # reprotect for later %-expansion
			if ($file =~ /^(.+)\:(.+)$/) {
				$source = $1;
				$target = $2;
			} else {
				$source = $file;
				$target = $file;
			}
			# If the path starts with a slash, assume it is meant to be global
			# and base it upon %D, otherwise treat it as relative to %I
			if ($source =~ /^\//) {
				$source = "%D$source";
			} else {
				$source = "%I/$source";
			}
			# Now the same for the target (but use %d and %i).
			if ($target =~ /^\//) {
				$target = "%d$target";
			} else {
				$target = "%i/$target";
			}

			# FIXME: if Files entry has colon, we throw out the last
			# component of $target. Should we allow the same type of
			# target renaming we do in DocFiles?

			my $source_dir = dirname($source);
			my $target_dir = dirname($target);

			# Skip iff "mv /foo/bar /foo"
			# (should we just skip Files altogether iff %d==%D?
			next if &expand_percent($source_dir,
									$self->{_expand},
									$self->get_info_filename.' "Files"')
				 eq &expand_percent($target_dir,
									$self->{_expand},
									$self->get_info_filename.' "Files"');

			if (!$target_dirs{$target_dir}++) {
				$install_script .= "\n/usr/bin/install -d -m 755 $target_dir";
			}
			$install_script .= "\n/bin/mv $source $target_dir/";
		}
	}

	# generate commands to install documentation files
	if ($self->has_param("DocFiles")) {
		my $files = $self->param_expanded("DocFiles");
		$files =~ s/\s+/ /g; # Make it one line
		$files = $self->conditional_space_list($files,
			"DocFiles of ".$self->get_fullname()." in ".$self->get_info_filename
		);

		my $target_dir = '%i/share/doc/%n';
		$install_script .= "\n/usr/bin/install -d -m 700 $target_dir";

		my ($file, $source, $target);
		foreach $file (split /\s+/, $files) {
			$file =~ s/\%/\%\%/g;   # reprotect for later %-expansion
			if ($file =~ /^(.+)\:(.+)$/) {
				# simple renaming
				# globs in source okay, dirs in target not auto-created
				$source = $1;
				$target = $2;
			} elsif ($file =~ /^(.+):$/) {
				# flatten declared nesting with automatic renaming
				# (dir1/dir2/.../foo => foo.dir1.dir2....)
				$source = $1;
				my @dirs = split /\//, $source;
				$target = join '.', (pop @dirs), @dirs;
			} else {
				# simple copying (nesting maintained, globs okay)
				$source = $file;
				$target = '';
			}
			$install_script .= "\n/bin/cp -r $source $target_dir/$target";
		}
		$install_script .= "\n/bin/chmod -R go=u-w $target_dir";
	}

	# generate commands to install profile.d scripts
	if ($self->has_param("RuntimeVars")) {

		my ($var, $value, $vars, $properties);

		$vars = $self->param("RuntimeVars");
		# get rid of any indention first
		$vars =~ s/^\s+//gm;
		# Read the set of variables (but don't change the keys to lowercase)
		$properties = &read_properties_var(
			'runtimevars of "'.$self->{_filename}.'"', $vars,
			{ case_sensitive => 1, preserve_order => 1 });

		if (keys %$properties > 0) {
			$install_script .= "\n/usr/bin/install -d -m 755 %i/etc/profile.d";
			while (($var, $value) = each %$properties) {
				$install_script .= "\necho \"setenv $var '$value'\" >> %i/etc/profile.d/%n.csh.env";
				$install_script .= "\necho \"export $var='$value'\" >> %i/etc/profile.d/%n.sh.env";
			}
			# make sure the scripts exist
			$install_script .= "\n/usr/bin/touch %i/etc/profile.d/%n.csh";
			$install_script .= "\n/usr/bin/touch %i/etc/profile.d/%n.sh";
			# prepend *.env to *.[c]sh
			$install_script .= "\n/bin/cat %i/etc/profile.d/%n.csh >> %i/etc/profile.d/%n.csh.env";
			$install_script .= "\n/bin/cat %i/etc/profile.d/%n.sh >> %i/etc/profile.d/%n.sh.env";
			$install_script .= "\n/bin/mv -f %i/etc/profile.d/%n.csh.env %i/etc/profile.d/%n.csh";
			$install_script .= "\n/bin/mv -f %i/etc/profile.d/%n.sh.env %i/etc/profile.d/%n.sh";
			# make them executable (to allow them to be sourced by /sw/bin.init.[c]sh)
			$install_script .= "\n/bin/chmod 755 %i/etc/profile.d/%n.*";
		}
	}

	# generate commands to install App bundles
	if ($self->has_param("AppBundles")) {
		$install_script .= "\n/usr/bin/install -d -m 755 %i/Applications";
		for my $bundle (split(/\s+/, $self->param("AppBundles"))) {
			$bundle =~ s/\'/\\\'/gsi;
			$install_script .= "\n/bin/cp -pR '$bundle' '%i/Applications/'";
		}
		chomp (my $developer_dir=`xcode-select -print-path 2>/dev/null`);
		$install_script .= "\n/bin/chmod -R o-w '%i/Applications/'" .
			"\nif test -x $developer_dir/Tools/SplitForks; then $developer_dir/Tools/SplitForks '%i/Applications/'; fi";
	}

	# generate commands to install jar files
	if ($self->has_param("JarFiles")) {
		my (@jarfiles, $jarfile, $jarfilelist);
		# install jarfiles
		$install_script .= "\n/usr/bin/install -d -m 755 %i/share/java/%n";
		@jarfiles = split(/\s+/, $self->param("JarFiles"));
		$jarfilelist = "";
		foreach $jarfile (@jarfiles) {
			if ($jarfile =~ /^(.+)\:(.+)$/) {
				$install_script .= "\n/usr/bin/install -c -p -m 644 $1 %i/share/java/%n/$2";
			} else {
				$jarfilelist .= " $jarfile";
			}
		}
		if ($jarfilelist ne "") {
			$install_script .= "\n/usr/bin/install -c -p -m 644$jarfilelist %i/share/java/%n/";
		}
	}

	$install_script .= "\n/bin/rm -f %i/info/dir %i/info/dir.old %i/share/info/dir %i/share/info/dir.old";

	### install

	# NB: parameter-value "installing" is specially recognized by run_script!
	$self->run_script($install_script, "installing", 0, 1);

	### splitoffs

	my $splitoff;
	foreach	 $splitoff ($self->parent_splitoffs) {
		# iterate over all splitoffs and call their build phase
		$splitoff->phase_install(1);
	}

	### remove build dir

	if (not $do_splitoff) {
		$bdir = $self->get_fullname();
		chdir "$buildpath";
		if (not $config->param_boolean("KeepBuildDir") and not Fink::Config::get_option("keep_build") and -e $bdir) {
			rm_rf $bdir or
				&print_breaking("WARNING: Can't remove build directory $bdir. ".
								"This is not fatal, but you may want to remove ".
								"the directory manually to save disk space. ".
								"Continuing with normal procedure.");
		}
	}
}

### build .deb

sub phase_build {
	my $self = shift;
	my $do_splitoff = shift || 0;
	my ($ddir, $destdir, $control);
	my ($daemonicname, $daemonicfile);
	my ($cmd);

	$config->mixed_arch(msg=>'build a package', fatal=>1);

	my $notifier = Fink::Notify->new();

	if ($self->is_type('dummy')) {
		my $error = "can't build " . $self->get_fullname() . " because no package description is available";
		$notifier->notify(event => 'finkPackageBuildFailed', description => $error);
		die "build phase: " . $error . "\n";
	}
	if ($self->has_parent and not $do_splitoff) {
		($self->get_parent)->phase_build();
		return;
	}

	chdir "$buildpath";
	$destdir = $self->get_install_directory();
	$ddir = basename $destdir;

	if (not -d "$destdir/DEBIAN") {
		if (not mkdir_p "$destdir/DEBIAN") {
			my $error = "can't create directory for control files for package ".$self->get_fullname();
			$notifier->notify(event => 'finkPackageBuildFailed', description => $error);
			die $error . "\n";
		}
	}

	# switch everything back to root ownership if we were --build-as-nobody
	my $build_as_nobody = $self->get_family_parent()->param_boolean("BuildAsNobody", 1);
	if (Fink::Config::get_option("build_as_nobody") && $build_as_nobody) {
		print "Reverting ownership of install dir to root\n";
		unless (chowname_hr 'root:admin', $destdir) {
			my $error = "Could not revert ownership of install directory to root.";
			$notifier->notify(event => 'finkPackageBuildFailed', description => $error);
			die $error . "\n";
		}
	}

	# put the info file into the debian directory
	if (-d "$destdir/DEBIAN") {
		my $infofile = $self->get_filename();
		if (defined $infofile) {
			cp($infofile, "$destdir/DEBIAN/package.info");
		}
		my $build_pkg = $self->has_parent ? $self->get_parent : $self;
		if ($build_pkg->has_param('PatchFile')) {
			for my $suffix ($build_pkg->get_patchfile_suffixes()) {
				my $patchfile = &expand_percent("\%{PatchFile$suffix}", $build_pkg->{_expand}, $self->get_info_filename." \"PatchFile$suffix\"");
				# only get here after successful build, so we know
				# patchfile was present, readable, and matched checksum
				cp($patchfile, "$destdir/DEBIAN/package.patch$suffix");
			}
		}
	}

	# generate dpkg "control" file

	my ($pkgname, $parentpkgname, $version, $field, $section, $instsize, $prio);
	$pkgname = $self->get_name();
	$parentpkgname = $self->get_family_parent->get_name();
	$version = $self->get_fullversion();

	$section = $self->get_control_section();
	$prio = $self->get_priority();

	$instsize = $self->get_instsize("$destdir$basepath");	# kilobytes!
	my $debarch = $config->param('Debarch');
	$control = <<EOF;
Package: $pkgname
Source: $parentpkgname
Version: $version
Section: $section
Installed-Size: $instsize
Architecture: $debarch
Priority: $prio
EOF
	if ($self->param_boolean("BuildDependsOnly")) {
		$control .= "BuildDependsOnly: True\n";
	} elsif (defined $self->param_boolean("BuildDependsOnly")) {
		$control .= "BuildDependsOnly: False\n";
	} else {
		$control .= "BuildDependsOnly: Undefined\n";
	}
	if ($self->param_boolean("Essential")) {
		$control .= "Essential: yes\n";
	}

	eval {
		require File::Find;
		import File::Find;
	};

	# Add a dependency on the kernel version (if not already present).
	#   We depend on the major version only, in order to prevent users from
	#   installing a .deb file created with an incorrect MACOSX_DEPLOYMENT_TARGET
	#   value.
	# TODO: move all this kernel-dependency stuff into pkglist()
	# FIXME: Actually, if the package states a kernel version we should combine
	#   the version given by the package with the one we want to impose.
	#   Instead, right now, we just use the package's version but this means
	#   that a package will need to be revised if the kernel major version changes.

	my $kernel = lc((uname())[0]);
	my $kernel_major_version = Fink::Services::get_kernel_vers();

	my $has_kernel_dep;
	my $deps = $self->get_depends(0, 0); # get runtime dependencies

	foreach (@$deps) {
		foreach (@$_) {
			$has_kernel_dep = 1 if /^\Q$kernel\E(\Z|\s|\()/;
		}
	}
	push @$deps, ["$kernel (>= $kernel_major_version-1)"] if not $has_kernel_dep;

	$control .= "Depends: " . &lol2pkglist($deps) . "\n";
	if (Fink::Config::get_option("maintainermode")) {
		print "- Depends line is: " . &lol2pkglist($deps) . "\n";
	}

	### Look at other pkglists
	foreach $field (qw(Provides Replaces Conflicts Pre-Depends
										 Recommends Suggests Enhances)) {
		if ($self->has_pkglist($field)) {
			$control .= "$field: ".&collapse_space($self->pkglist($field))."\n";
		}
	}
	foreach $field (qw(Maintainer)) {
		if ($self->has_param($field)) {
			$control .= "$field: ".&collapse_space($self->param($field))."\n";
		}
	}
	$control .= "Description: ".$self->get_description();

	### write "control" file

	print "Writing control file...\n";

	if ( open(CONTROL,">$destdir/DEBIAN/control") ) {
		print CONTROL $control;
		close(CONTROL) or die "can't write control file for ".$self->get_fullname().": $!\n";
	} else {
		my $error = "can't write control file for ".$self->get_fullname().": $!";
		$notifier->notify(event => 'finkPackageBuildFailed', description => $error);
		die $error . "\n";
	}

	### create scripts as neccessary
	## TODO: refactor more of this stuff to fink-instscripts

	my %scriptbody;
	foreach (qw(postinst postrm preinst prerm)) {
		# get script piece from package description
		$scriptbody{$_} = $self->param_default($_.'Script','');
	}
	Hash::Util::lock_keys %scriptbody;  # safety: key typos become runtime errors

	my $autodpkg = $self->param_default_expanded('AutoDpkg','');
	$autodpkg =~ s/^\s+//gm if $self->info_level < 3;  # old-skool whitespace handler
	$autodpkg = &read_properties_var(
		$self->get_info_filename.' "AutoDpkg"',
		$autodpkg,
		{ remove_space => ($self->info_level >= 3) }
	);
	{
		# do not allow a deficient package to be built!
		my %allowed_autodpkg = map { lc($_)=>1 } (qw/ UpdatePOD /);
		foreach (sort keys %$autodpkg) {
			if (!exists $allowed_autodpkg{$_}) {
				my $error = "AutoDpkg flag \"$_\" in package " . $self->get_fullname() . " cannot be handled by this version of fink";
				$notifier->notify(event => 'finkPackageBuildFailed', description => $error);
				die $error . "\n";
			}
		}
	}
	$autodpkg = Fink::Base->new_from_properties($autodpkg);

	# let's not be crazy
	if ($self->has_param("UpdatePOD") and $autodpkg->has_param("UpdatePOD")) {
		my $error = "Cannot specify both UpdatePOD and AutoDpkg:UpdatePOD in package " . $self->get_fullname();
		$notifier->notify(event => 'finkPackageBuildFailed', description => $error);
		die $error . "\n";
	}

	# add UpdatePOD Code
	if ($self->param_boolean("UpdatePOD")) {
		# grab perl version, if present
		my ($perldirectory, $perlarchdir) = $self->get_perl_dir_arch();

		# bug in postinst: cat .../*.pod fails (leading to dpkg -i
		# abort) if no files (i.e., first pkg of this Type:perl
		# subtype) being installed
		$scriptbody{postinst} .=
			"\n\n# Updating \%p/lib/perl5/$perlarchdir$perldirectory/perllocal.pod\n".
			"/bin/mkdir -p \%p/lib/perl5$perldirectory/$perlarchdir\n".
			"/bin/cat \%p/share/podfiles$perldirectory/*.pod > \%p/lib/perl5$perldirectory/$perlarchdir/perllocal.pod\n";
		$scriptbody{postrm} .=
			"\n\n# Updating \%p/lib/perl5$perldirectory/$perlarchdir/perllocal.pod\n\n".
			"###\n".
			"### check to see if any .pod files exist in \%p/share/podfiles.\n".
			"###\n\n".
			"/bin/echo -n '' > \%p/lib/perl5$perldirectory/$perlarchdir/perllocal.pod\n".
			"perl <<'END_PERL'\n\n".
			"if (-e \"\%p/share/podfiles$perldirectory\") {\n".
			"	 \@files = <\%p/share/podfiles$perldirectory/*.pod>;\n".
			"	 if (\$#files >= 0) {\n".
			"		 exec \"/bin/cat \%p/share/podfiles$perldirectory/*.pod > \%p/lib/perl5$perldirectory/$perlarchdir/perllocal.pod\";\n".
			"	 }\n".
			"}\n\n".
			"END_PERL\n";
	} elsif ($autodpkg->param_boolean("UpdatePOD")) {
		# grab perl version, if present
		my ($perldirectory, $perlarchdir) = $self->get_perl_dir_arch();

		foreach my $script (qw/ preinst postinst prerm postrm /) {
			$scriptbody{$script} .= $self->_instscript($script, "updatepod", $perldirectory, $perlarchdir);
		}
	}

	# add JarFiles Code
	if ($self->has_param("JarFiles")) {
		my $scriptbody =
			"\n\n".
			"/bin/mkdir -p %p/share/java\n".
			"jars=`/usr/bin/find %p/share/java -name '*.jar'`\n".
			'if (test -n "$jars")'."\n".
			"then\n".
			'(for jar in $jars ; do /bin/echo -n "$jar:" ; done) | sed "s/:$//" > %p/share/java/classpath'."\n".
			"else\n".
			"/bin/rm -f %p/share/java/classpath\n".
			"fi\n".
			"unset jars\n";
		$scriptbody{postinst} .= $scriptbody;
		$scriptbody{postrm}   .= $scriptbody;
	}

	# add Fink symlink Code for .app OS X applications
	if ($self->has_param("AppBundles")) {
		# shell-escape app names and parse down to just the .app dirname
		my @apps = map { s/\'/\\\'/gsi; basename($_) } split(/\s+/, $self->param("AppBundles"));

		$scriptbody{postinst} .=
			"\n".
			"if \! test -e /Applications/Fink; then\n".
			"  /usr/bin/install -d -m 755 /Applications/Fink\n".
			"fi\n";
		foreach (@apps) {
			$scriptbody{postinst} .= "ln -s '%p/Applications/$_' /Applications/Fink/\n";
		}

		$scriptbody{postrm} .= "\n";
		foreach (@apps) {
			$scriptbody{postrm} .= "rm -f '/Applications/Fink/$_'\n";
		}
	}

	# add emacs texinfo files
	if ($self->has_param("InfoDocs")) {
		my $infodir = '%p/share/info';
		my @infodocs;

		# postinst needs to tweak @infodocs
		@infodocs = split(/\s+/, $self->param("InfoDocs"));
		@infodocs = grep { $_ } @infodocs;  # TODO: what is this supposed to do???

		# FIXME: This seems brokenly implemented for @infodocs that are already absolute path
		map { $_ = "$infodir/$_" unless $_ =~ /\// } @infodocs;

		# FIXME: debian install-info seems to always omit all path components when adding

		# NOTE: Validation::_validate_dpkg must be kept in sync with
		# this implementation!

		$scriptbody{postinst} .= "\n";
		$scriptbody{postinst} .= "# generated from InfoDocs directive\n";
		$scriptbody{postinst} .= "if [ -f $infodir/dir ]; then\n";
		$scriptbody{postinst} .= "\tif [ -f %p/sbin/install-info ]; then\n";
		foreach (@infodocs) {
			$scriptbody{postinst} .= "\t\t%p/sbin/install-info --infodir=$infodir $_\n";
		}
		$scriptbody{postinst} .= "\telif [ -f %p/bootstrap/sbin/install-info ]; then\n";
		foreach (@infodocs) {
			$scriptbody{postinst} .= "\t\t%p/bootstrap/sbin/install-info --infodir=$infodir $_\n";
		}
		$scriptbody{postinst} .= "\tfi\n";
		$scriptbody{postinst} .= "fi\n";

		# postinst tweaked @infodocs so reload the original form
		@infodocs = split(/\s+/, $self->param("InfoDocs"));
		@infodocs = grep { $_ } @infodocs;  # TODO: what is this supposed to do???

		# FIXME: this seems wrong for non-simple-filename $_ (since the dir only lists
		# the filename component and could have same value in different dirs)

		$scriptbody{prerm} .= "\n";
		$scriptbody{prerm} .= "# generated from InfoDocs directive\n";
		$scriptbody{prerm} .= "if [ -f $infodir/dir ]; then\n";
		foreach (@infodocs) {
			$scriptbody{prerm} .= "\t%p/sbin/install-info --infodir=$infodir --remove $_\n";
		}
		$scriptbody{prerm} .= "fi\n";
	}

	# write out each non-empty script
	foreach my $scriptname (sort keys %scriptbody) {
		next unless length $scriptbody{$scriptname};
		my $scriptbody = &expand_percent($scriptbody{$scriptname}, $self->{_expand}, $self->get_info_filename." \"$scriptname\"");
		my $scriptfile = "$destdir/DEBIAN/$scriptname";

		print "Writing package script $scriptname...\n";

		my $write_okay;
		# NB: if change the automatic #! line here, must adjust validator
		if ( $write_okay = open(SCRIPT,">$scriptfile") ) {
			print SCRIPT <<EOF;
#!/bin/sh
# $scriptname script for package $pkgname, auto-created by fink

set -e

$scriptbody

exit 0
EOF
			close(SCRIPT) or $write_okay = 0;
			chmod 0755, $scriptfile;
		}
		if (not $write_okay) {
			my $error = "can't write $scriptname script for ".$self->get_fullname().": $!";
			$notifier->notify(event => 'finkPackageBuildFailed', description => $error);
			die $error . "\n";
		}
	}

	### shlibs file

	if (length(my $shlibsbody = $self->get_shlibs_field)) {
		chomp $shlibsbody;

		my $shlibs_error = sub {
			my $self = shift;
			my $type = shift;
			my $error = "can't write to $type file for " . $self->get_fullname() . ": $!";
			$notifier->notify(event => 'finkPackageBuildFailed', description => $error);
			die $error . "\n";
		};

		print "Creating shlibs files...\n";

# FIXME-dmacks:
#    * Make sure each file is actually present in $destdir
#    * Remove file if package isn't listed as a provider
#      (needed since only some variants may provide but we don't
#      have any condiitonal syntax in Shlibs)
#    * Rejoin wrap continuation lines
#      (use \ not heredoc multiline-field)

		my (@shlibslines, @privateshlibslines);
		for my $line (split(/\n/, $shlibsbody)) {
			if ($line =~ /^\s*\!/) {
				push @privateshlibslines, $line."\n";
			} else {
				push @shlibslines, $line."\n";
			}
		}

		if (@shlibslines) {
			my $shlibsfile = IO::Handle->new();
			open $shlibsfile, ">$destdir/DEBIAN/shlibs" or &{$shlibs_error}($self, 'shlibs');
			print $shlibsfile @shlibslines;
			close $shlibsfile or &{$shlibs_error}($self, 'shlibs');
			chmod 0644, "$destdir/DEBIAN/shlibs";
		}
		if (@privateshlibslines) {
			my $shlibsfile = IO::Handle->new();
			open $shlibsfile, ">$destdir/DEBIAN/private-shlibs" or &{$shlibs_error}($self, 'private shlibs');
			print $shlibsfile @privateshlibslines;
			close $shlibsfile  or &{$shlibs_error}($self, 'private shlibs');
			chmod 0644, "$destdir/DEBIAN/private-shlibs";
		}

	}

	### config file list

	if ($self->has_param('ConfFiles')) {
		my $files = $self->param_expanded('ConfFiles');
		$files =~ s/\s+/ /g; # Make it one line
		$files = $self->conditional_space_list($files,
			"ConfFiles of ".$self->get_fullname()." in ".$self->get_info_filename
		);

		if ($files =~ /\S/) {
			# we actually have something
			print "Writing conffiles list...\n";

			my $listfile = "$destdir/DEBIAN/conffiles";
			if ( open my $scriptFH, '>', $listfile ) {
				print $scriptFH map "$_\n", split /\s+/, $files;
				close $scriptFH or die "can't write conffiles list file for ".$self->get_fullname().": $!\n";
				chmod 0644, $listfile;
			} else {
				my $error = "can't write conffiles list file for ".$self->get_fullname().": $!";
				$notifier->notify(event => 'finkPackageBuildFailed', description => $error);
				die $error . "\n";
			}
		}
	}

	### daemonic service file

	if ($self->has_param("DaemonicFile")) {
		$daemonicname = $self->param_default_expanded("DaemonicName", $self->get_name());
		$daemonicname .= ".xml";
		$daemonicfile = "$destdir$basepath/etc/daemons/".$daemonicname;

		print "Writing daemonic info file $daemonicname...\n";

		unless ( mkdir_p "$destdir$basepath/etc/daemons" ) {
			my $error = "can't write daemonic info file for ".$self->get_fullname();
			$notifier->notify(event => 'finkPackageBuildFailed', description => $error);
			die $error . "\n";
		}

		if ( open(SCRIPT,">$daemonicfile") ) {
			print SCRIPT $self->param_expanded("DaemonicFile"), "\n";
			close(SCRIPT) or die "can't write daemonic info file for ".$self->get_fullname().": $!\n";
			chmod 0644, $daemonicfile;
		} else {
			my $error = "can't write daemonic info file for ".$self->get_fullname().": $!";
			$notifier->notify(event => 'finkPackageBuildFailed', description => $error);
			die $error . "\n";
		}
	}

	### create .deb using dpkg-deb

	if (not -d $self->get_debpath()) {
		unless (mkdir_p $self->get_debpath()) {
			my $error = "can't create directory for packages";
			$notifier->notify(event => 'finkPackageBuildFailed', description => $error);
			die $error . "\n";
		}
	}

	### Create md5sum for deb, this is done as part of the debian package
	### policy and so that tools like debsums can check the consistancy
	### of installed file, this will also help for trouble shooting, since
	### we will know if a packages file has be changed

	require File::Find;
	my $md5s="";
	my $md5check=Fink::Checksum->new('MD5');

	File::Find::find({
		preprocess => sub {
			# Don't descend into the .deb control directory
			return () if $File::Find::dir eq "$destdir/DEBIAN";
			return @_;
		},
		wanted => sub {
			if (-f $_ && ! -l $_) {
				my $md5file = $File::Find::name;
				# We're already requiring Fink::Checksum so use that to get
				# the MD5.
				my $md5sum = $md5check->get_checksum($md5file);
				# md5sums wants filename relative to
				# installed-location FS root
				$md5file =~ s/^\Q$destdir\E\///;
				$md5s .= "$md5sum  $md5file\n";
			}
		},
	}, $destdir
	);

	# Only write if there are files that need md5sums
	if ( $md5s ne "") {
		print "Writing md5sums file...\n";
		if ( open(MD5SUMS,">$destdir/DEBIAN/md5sums") ) {
			print MD5SUMS $md5s;
			close(MD5SUMS) or die "can't write control file for ".$self->get_fullname().": $!\n";
		} else {
			my $error = "can't write md5sums file for ".$self->get_fullname().": $!";
			$notifier->notify(event => 'finkPackageBuildFailed', description => $error);
			die $error . "\n";
		}
	}

	if (Fink::Config::get_option("validate")) {
		my %saved_options = map { $_ => Fink::Config::get_option($_) } qw/ verbosity Pedantic /;
		Fink::Config::set_options( {
			'verbosity' => 3,
			'Pedantic'  => 1
			} );
		if (!Fink::Validation::validate_dpkg_unpacked($destdir)) {
			if (Fink::Config::get_option("validate") eq "on") {
				$self->package_error( phase => '.deb validation', preamble => "If you are the maintainer, please correct the above problems and try\nagain! Otherwise, consider this a bug that should be reported." );
			} else {
				warn "Validation of .deb failed.\n";
			}
		}
		Fink::Config::set_options(\%saved_options);
	}

	# Set ENV so for tar on 10.9+, dpkg-deb calls tar and thus requires it
	# as well.
	$cmd = "env LANG=C LC_ALL=C dpkg-deb -b $ddir ".$self->get_debpath();
	if (&execute($cmd)) {
		my $error = "can't create package ".$self->get_debname();
		$notifier->notify(event => 'finkPackageBuildFailed', description => $error);
		die $error . "\n";
	}

	my $debpath = $self->get_debpath();
	my $distribution = $config->param("Distribution");
	$debpath =~ s/$basepath\/fink\//..\//;
	unless (symlink_f $debpath."/".$self->get_debname(), "$basepath/fink/debs/".$self->get_debname()) {
		my $error = "can't symlink package ".$self->get_debname()." into pool directory";
		$notifier->notify(event => 'finkPackageBuildFailed', description => $error);
		die $error . "\n";
	}

	### splitoffs

	my $splitoff;
	foreach	 $splitoff ($self->parent_splitoffs) {
		# iterate over all splitoffs and call their build phase
		$splitoff->phase_build(1);
	}

	### remove root dir

	if (not $config->param_boolean("KeepRootDir") and not Fink::Config::get_option("keep_root") and -e $destdir) {
		rm_rf $destdir or
			&print_breaking("WARNING: Can't remove package root directory ".
							"$destdir. ".
							"This is not fatal, but you may want to remove ".
							"the directory manually to save disk space. ".
							"Continuing with normal procedure.");
	}

	$built_trees{$self->get_full_tree} = 1;
}

=item phase_activate

	phase_activate @packages;
	phase_activate \@packages, %opts;

Use dpkg to install a list of packages. The packages are passed as
PkgVersion objects. Stale buildlocks are automatically removed if
@packages is passed by reference. The following option is known:

=over 4

=item no_clean_bl (optional)

If present and true, do not check for stale buildlocks.

=back

=cut

sub phase_activate {
	my (@packages, %opts);
	if (ref $_[0]) {
		my $packages = shift;
		@packages = @$packages;
		%opts = (no_clean_bl => 0, @_);
	} else {
		@packages = @_;
		%opts = (no_clean_bl => 1);
	}

	$config->mixed_arch(msg=>'install a package', fatal=>1);

	my (@installable);

	my $notifier = Fink::Notify->new();

	for my $package (@packages) {
		my $deb = $package->find_debfile();

		unless (defined $deb and -f $deb) {
			my $error = "can't find package ".$package->get_debname();
			$notifier->notify(event => 'finkPackageInstallationFailed', description => $error);
			die $error . "\n";
		}

		push(@installable, $package);
	}

	if (@installable == 0) {
		my $error = "no installable .deb files found!";
		$notifier->notify(event => 'finkPackageInstallationFailed', description => $error);
		die $error . "\n";
	}

	# remove stale buildlocks (might interfere with pkg installations)
	Fink::Engine::cleanup_buildlocks(internally=>1) unless $opts{no_cleanup_bl};

	# Ensure consistency is maintained. May die!
	eval {
		require Fink::SysState;
		my $state = Fink::SysState->new();
		@installable = (@installable, $state->resolve_install(@installable));
	};
	if ($@) {
		die "$@" if $@ =~ /Fink::SysState/;	# Die if resolution failed

		# Some packages have serious  errors in them which can confuse dep
		# resolution. It's not obvious what safe action we can take!
		print_breaking_stderr "WARNING: $@";
	}

	my @deb_installable = map { $_->find_debfile() } @installable;
	if (&execute(dpkg_lockwait() . " -i @deb_installable", ignore_INT=>1)) {
		if (@installable == 1) {
			my $error = "can't install package ".$installable[0]->get_fullname();
			$notifier->notify(event => 'finkPackageInstallationFailed', description => $error);
			die $error . "\n";
		} else {
			$notifier->notify(event => 'finkPackageInstallationFailed', title => 'Fink installation of ' . int(@installable) . ' packages failed.',
				description => "can't batch-install packages:\n  " . join("\n  ", map { $_->get_fullname() } @installable));
			die "can't batch-install packages: @deb_installable\n";
		}
	} else {
		if (@installable == 1) {
			$notifier->notify(event => 'finkPackageInstallationPassed', description => "installed " . $installable[0]->get_fullname());
		} else {
			$notifier->notify(event => 'finkPackageInstallationPassed', title => 'Fink installation of ' . int(@installable) . ' packages passed.', description => "batch-installed packages:\n  " . join("\n  ", map { $_->get_fullname() } @installable));
		}
	}

	Fink::PkgVersion->dpkg_changed;
}

=item phase_deactivate

	phase_deactivate @packages;
	phase_deactivate \@packages, %opts;

Use dpkg to remove a list of packages, but leave their ConfFiles in
place. The packages are passed by name (no versioning requirements
allowed). Only real packages can be removed, not "Provides" virtuals.
Stale buildlocks are automatically removed if @packages is passed by
reference. The following option is known:

=over 4

=item no_clean_bl (optional)

If present and true, do not check for stale buildlocks.

=back

=cut

sub phase_deactivate {
	my (@packages, %opts);
	if (ref $_[0]) {
		my $packages = shift;
		@packages = @$packages;
		%opts = (no_clean_bl => 0, @_);
	} else {
		@packages = @_;
		%opts = (no_clean_bl => 1);
	}

	# remove stale buildlocks (might interfere with pkg removals)
	Fink::Engine::cleanup_buildlocks(internally=>1) unless $opts{no_cleanup_bl};

	my $notifier = Fink::Notify->new();

	if (&execute(dpkg_lockwait() . " --remove @packages", ignore_INT=>1)) {
		&print_breaking("ERROR: Can't remove package(s). If the above error message " .
		                "mentions dependency problems, you can try\n" .
		                "  fink remove --recursive @packages\n" .
		                "This will attempt to remove the package(s) specified as " .
		                "well as ALL packages that depend on it.");
		if (@packages == 1) {
			$notifier->notify(event => 'finkPackageRemovalFailed', title => 'Fink removal failed.', description => "can't remove package ".$packages[0]);
			die "can't remove package ".$packages[0]."\n";
		} else {
			$notifier->notify(event => 'finkPackageRemovalFailed', title => 'Fink removal of ' . int(@packages) . ' packages failed.',
				description => "can't batch-remove packages:\n  " . join("\n  ", @packages));
			die "can't batch-remove packages: @packages\n";
		}
	} else {
		if (@packages == 1) {
			$notifier->notify(event => 'finkPackageRemovalPassed', title => 'Fink removal passed.', description => "removed " . $packages[0]);
		} else {
			$notifier->notify(event => 'finkPackageRemovalPassed', title => 'Fink removal of ' . int(@packages) . ' packages passed.',
				description => "batch-removed packages:\n  " . join("\n  ", @packages));
		}
	}

	Fink::PkgVersion->dpkg_changed;
}

=item phase_deactivate_recursive

	phase_deactivate_recursive @packages;

Use apt to remove a list of packages and all packages that depend on
them, but leave their ConfFiles in place. The packages are passed by
name (no versioning requirements allowed). Only real packages can be
removed, not "Provides" virtuals. No explicit processing of buildlocks
is done: stale ones that depend on packages to be deactivated will be
removed and live buildlocks cannot be removed even via recursive
removal.

=cut

sub phase_deactivate_recursive {
	my @packages = @_;

	if (&execute(aptget_lockwait() . " remove @packages")) {
		if (@packages == 1) {
			die "can't remove package ".$packages[0]."\n";
		} else {
			die "can't batch-remove packages: @packages\n";
		}
	}
	Fink::PkgVersion->dpkg_changed;
}

=item phase_purge

	phase_purge @packages;
	phase_purge \@packages, %opts;

Use dpkg to remove a list of packages, including their ConfFiles. The
packages are passed by name (no versioning requirements allowed). Only
real packages can be removed, not "Provides" virtuals. Stale
buildlocks are automatically removed if @packages is passed by
reference. The following option is known:

=over 4

=item no_clean_bl (optional)

If present and true, do not check for stale buildlocks.

=back

=cut

sub phase_purge {
	my (@packages, %opts);
	if (ref $_[0]) {
		my $packages = shift;
		@packages = @$packages;
		%opts = (no_clean_bl => 0, @_);
	} else {
		@packages = @_;
		%opts = (no_clean_bl => 1);
	}

	# remove stale buildlocks (might interfere with pkg purgess)
	Fink::Engine::cleanup_buildlocks(internally=>1) unless $opts{no_cleanup_bl};


	if (&execute(dpkg_lockwait() . " --purge @packages", ignore_INT=>1)) {
		&print_breaking("ERROR: Can't purge package(s). Try 'fink purge --recursive " .
		                "@packages', which will also purge packages that depend " .
		                "on the package to be purged.");
		if (@packages == 1) {
			die "can't purge package ".$packages[0]."\n";
		} else {
			die "can't batch-purge packages: @packages\n";
		}
	}
	Fink::PkgVersion->dpkg_changed;
}

=item phase_purge_recursive

	phase_purge_recursive @packages;

Use apt to remove a list of packages and all packages that depend on
them, including their ConfFiles. The packages are passed by name (no
versioning information). Only real packages can be removed, not
"Provides" virtuals. No explicit processing of buildlocks is done:
stale ones that depend on packages to be deactivated will be removed
and live buildlocks cannot be removed even via recursive removal.

=cut

sub phase_purge_recursive {
	my @packages = @_;

	if (&execute(aptget_lockwait() . " remove --purge @packages")) {
		if (@packages == 1) {
			die "can't purge package ".$packages[0]."\n";
		} else {
			die "can't batch-purge packages: @packages\n";
		}
	}
	Fink::PkgVersion->dpkg_changed;
}

=item ensure_libcxx_prefix

	my $prefix_path = ensure_libcxx_prefix;

Ensures that a path-prefix directory exists to use libcxx wrapper for the C++ compilers.
Returns the path to the resulting directory.

=cut

sub ensure_libcxx_prefix {
	my $dir = "$basepath/var/lib/fink/path-prefix-libcxx";
	unless (-d $dir) {
		mkdir_p $dir or die "Path-prefix dir $dir cannot be created!\n";
	}

	my $gpp = "$dir/compiler_wrapper";
	unless (-x $gpp) {
		open GPP, ">$gpp" or die "Path-prefix file $gpp cannot be created!\n";
		print GPP <<EOF;
#!/bin/sh
compiler=\${0##*/}
save_IFS="\$IFS"
IFS=:
newpath=
for dir in \$PATH ; do
  case \$dir in
    *var/lib/fink/path-prefix*) ;;
    *) newpath="\${newpath:+\${newpath}:}\$dir" ;;
  esac
done
IFS="\$save_IFS"
export PATH="\$newpath"
# To avoid extra warning spew, don't add 
# -Wno-error=unused-command-line-argument-hard-error-in-future
# when clang doesn't support it .
clang_version=`clang --version | head -n1 | cut -d- -f2 | cut -d'.' -f1`
if [[ (\$clang_version -lt "503") || (\$clang_version -ge "600") ]]; then
	suppress_hard_error=""
else
	suppress_hard_error="-Wno-error=unused-command-line-argument-hard-error-in-future"
fi
exec \$compiler -stdlib=libc++ "\$suppress_hard_error" "\$@"
# strip path-prefix to avoid finding this wrapper again
# $basepath/bin is needed to pick up ccache-default
# This file was auto-generated via Fink::PkgVersion::ensure_libcxx_prefix()
EOF
		close GPP;
		chmod 0755, $gpp or die "Path-prefix file $gpp cannot be made executable!\n";
	}

	foreach my $cpp ("$dir/c++", "$dir/g++", "$dir/clang++") {
		unless (-l $cpp) {
			symlink 'compiler_wrapper', $cpp or die "Path-prefix link $cpp cannot be created!\n";
		}
	}

	return $dir;
}

=item ensure_clang_prefix

	my $prefix_path = ensure_clang_prefix;

Ensures that a path-prefix directory exists to use clang compilers
Returns the path to the resulting directory.

=cut

sub ensure_clang_prefix {
	my $dir = "$basepath/var/lib/fink/path-prefix-clang";
	unless (-d $dir) {
		mkdir_p $dir or die "Path-prefix dir $dir cannot be created!\n";
	}

	my $gpp = "$dir/compiler_wrapper";
	unless (-x $gpp) {
		open GPP, ">$gpp" or die "Path-prefix file $gpp cannot be created!\n";
		print GPP <<EOF;
#!/bin/sh
compiler=\${0##*/}
save_IFS="\$IFS"
IFS=:
newpath=
for dir in \$PATH ; do
  case \$dir in
    *var/lib/fink/path-prefix*) ;;
    *) newpath="\${newpath:+\${newpath}:}\$dir" ;;
  esac
done
IFS="\$save_IFS"
export PATH="\$newpath"
if [ "\$compiler" = "cc" -o "\$compiler" = "gcc" ]; then
   compiler="clang"
fi
if [ "\$compiler" = "c++" -o "\$compiler" = "g++" ]; then
  compiler="clang++"
fi
# To avoid extra warning spew, don't add 
# -Wno-error=unused-command-line-argument-hard-error-in-future
# when clang doesn't support it .
clang_version=`clang --version | head -n1 | cut -d- -f2 | cut -d'.' -f1`
if [[ (\$clang_version -lt "503") || (\$clang_version -ge "600") ]]; then
	suppress_hard_error=""
else
	suppress_hard_error="-Wno-error=unused-command-line-argument-hard-error-in-future"
fi
exec \$compiler "\$suppress_hard_error" "\$@"
# strip path-prefix to avoid finding this wrapper again
# $basepath/bin is needed to pick up ccache-default
# This file was auto-generated via Fink::PkgVersion::ensure_clang_prefix()
EOF
		close GPP;
		chmod 0755, $gpp or die "Path-prefix file $gpp cannot be made executable!\n";
	}

	foreach my $cpp ("$dir/cc", "$dir/c++", "$dir/gcc", "$dir/g++") {
		unless (-l $cpp) {
			symlink 'compiler_wrapper', $cpp or die "Path-prefix link $cpp cannot be created!\n";
		}
	}

	return $dir;
}

=item ensure_gpp106_prefix

  my $prefix_path = ensure_gpp106_prefix $arch;

Ensures that a path-prefix directory exists to make compilers single-arch
Returns the path to the resulting directory.

=cut

sub ensure_gpp106_prefix {
	my $arch = shift;

	my $dir = "$basepath/var/lib/fink/path-prefix-10.6";
	unless (-d $dir) {
		mkdir_p $dir or	die "Path-prefix dir $dir cannot be created!\n";
	}

	my $gpp = "$dir/compiler_wrapper";
	unless (-x $gpp) {
		open GPP, ">$gpp" or die "Path-prefix file $gpp cannot be created!\n";
		print GPP <<EOF;
#!/bin/sh
compiler=\${0##*/}
save_IFS="\$IFS"
IFS=:
newpath=
for dir in \$PATH ; do
  case \$dir in
    *var/lib/fink/path-prefix*) ;;
    *) newpath="\${newpath:+\${newpath}:}\$dir" ;;
  esac
done
IFS="\$save_IFS"
export PATH="\$newpath"
exec \$compiler "-arch" "$arch" "\$@"
# strip path-prefix to avoid finding this wrapper again
# $basepath/bin is needed to pick up ccache-default
# This file was auto-generated via Fink::PkgVersion::ensure_gpp106_prefix()
EOF
		close GPP;
		chmod 0755, $gpp or die "Path-prefix file $gpp cannot be made executable!\n";
	}

	foreach my $cpp (
		"$dir/cc",
		"$dir/c++", "$dir/c++-4.0", "$dir/c++-4.2",
		"$dir/gcc", "$dir/gcc-4.0", "$dir/gcc-4.2",
		"$dir/g++", "$dir/g++-4.0", "$dir/g++-4.2",
		"$dir/clang", "$dir/clang++",
	) {
		unless (-l $cpp) {
			symlink 'compiler_wrapper', $cpp or die "Path-prefix link $cpp cannot be created!\n";
		}
	}

	return $dir;
}


=item ensure_gpp_prefix

  my $prefix_path = ensure_gpp_prefix $gpp_version;

Ensures that a path-prefix directory exists for the given version of g++.
Returns the path to the resulting directory.

=cut

# NOTE: If you change this, you also must change the matching script in
# g++-wrapper.in!
sub ensure_gpp_prefix {
	my $vers = shift;

	my $dir = "$basepath/var/lib/fink/path-prefix-g++-$vers";
	unless (-d $dir) {
		mkdir_p $dir or	die "Path-prefix dir $dir cannot be created!\n";
	}

	my $gpp = "$dir/g++";
	unless (-x $gpp) {
		open GPP, ">$gpp" or die "Path-prefix file $gpp cannot be created!\n";
		print GPP <<EOF;
#!/bin/sh
exec g++-$vers "\$@"
EOF
		close GPP;
		chmod 0755, $gpp or die "Path-prefix file $gpp cannot be made executable!\n";
	}

	my $cpp = "$dir/c++";
	unless (-l $cpp) {
		symlink 'g++', $cpp or die "Path-prefix link $cpp cannot be created!\n";
	}

	return $dir;
}


# returns hashref for the ENV to be used while running package scripts
# does not alter global ENV

sub get_env {
	my $self = shift;
	my $phase = shift;		# string (selects cache item special-case)

	my $cache = '_script_env';	# standard cache token
	if (defined $phase && $phase eq 'installing') {
		# special-case cache token
		$cache .= "_$phase";
	}

	# just return cached copy if there is one
	if (not $self->{_bootstrap} and exists $self->{$cache} and defined $self->{$cache} and ref $self->{$cache} eq "HASH") {
		# return ref to a copy, so caller changes do not modify cached value
		return \%{$self->{$cache}};
	}

	# bits of ENV that can be altered by SetENVVAR and NoSetENVVAR in a .info
	# Remember to update Packaging Manual if you change this var list!
	our @setable_env_vars = (
		"CC", "CFLAGS",
		"CPP", "CPPFLAGS",
		"CXX", "CXXFLAGS",
		"DYLD_LIBRARY_PATH",
		"JAVA_HOME",
		"LD", "LDFLAGS",
		"LIBRARY_PATH", "LIBS",
		"MACOSX_DEPLOYMENT_TARGET",
		"MAKE", "MFLAGS", "MAKEFLAGS",
	);

	# default environment variable values
	# Remember to update FAQ 8.3 if you change this var list!
	my %defaults = (
		"CPPFLAGS"                 => "-I\%p/include",
		"LDFLAGS"                  => "-L\%p/lib",
	);

# for building 64bit libraries, we change LDFLAGS:

	if (exists $self->{_type_hash}->{"-64bit"}) {
		if ($self->{_type_hash}->{"-64bit"} eq "-64bit") {
			$defaults{"LDFLAGS"} = "-L\%p/\%lib -L\%p/lib";
		}
	}

	# uncomment this to be able to use distcc -- not officially supported!
	#$defaults{'MAKEFLAGS'} = $ENV{'MAKEFLAGS'} if (exists $ENV{'MAKEFLAGS'});

	# Special feature: SetMACOSX_DEPLOYMENT_TARGET does an implicit NoSet:true
	if (not $self->has_param("SetMACOSX_DEPLOYMENT_TARGET")) {
		my $sw_vers = Fink::Services::get_osx_vers() || Fink::Services::get_darwin_equiv();
		if (defined $sw_vers) {
			$defaults{'MACOSX_DEPLOYMENT_TARGET'} = $sw_vers;
		}
	}

	# start with a clean environment
	my %script_env = ();

	# create a dummy HOME directory
	# NB: File::Temp::tempdir CLEANUP breaks if we fork!
	$script_env{"HOME"} = tempdir( 'fink-build-HOME.XXXXXXXXXX', DIR => File::Spec->tmpdir, CLEANUP => 1 );
	if ($< == 0) {
		# we might be writing to ENV{HOME} during build, so fix ownership
		my $build_as_user_group = $self->pkg_build_as_user_group();
		chowname $build_as_user_group->{'user:group'}, $script_env{HOME} or
			die "can't chown '" . $build_as_user_group->{'user:group'} . "' $script_env{HOME}\n";
	}

	# add system path
	$script_env{"PATH"} = "/bin:/usr/bin:/sbin:/usr/sbin";

	# add bootstrap path if necessary
	my $bsbase = Fink::Bootstrap::get_bsbase();
	if (-d $bsbase) {
		$script_env{"PATH"} = "$bsbase/bin:$bsbase/sbin:" . $script_env{"PATH"};
	}

	# Stop ccache stompage: allow user to specify directory via fink.conf
	my $ccache_dir = $config->param_default("CCacheDir", "$basepath/var/ccache");
	unless ( lc $ccache_dir eq "none" ) {
		# make sure directory exists
		if ( not -d $ccache_dir and not mkdir_p($ccache_dir) ) {
			die "WARNING: Something is preventing the creation of " .
				"\"$ccache_dir\" for CCacheDir, so CCACHE_DIR will not ".
				"be set.\n";
		} else {
			$script_env{CCACHE_DIR} = $ccache_dir;
		}
	}

	# get full environment: parse what a shell has after sourcing init.sh
	# script when starting with the (purified) ENV we have so far
	if (-r "$basepath/bin/init.sh") {
		local %ENV = %script_env;
		my @vars = `sh -c ". $basepath/bin/init.sh ; /usr/bin/env"`;
		chomp @vars;
		%script_env = map { $_ =~ /^([^=]+)=(.*)$/ } @vars;
		delete $script_env{_};  # artifact of how we fetch init.sh results
	}

	# preserve TERM
	$script_env{"TERM"} = $ENV{"TERM"} if exists $ENV{"TERM"};

	# set variables according to the info file
	my $expand = $self->{_expand};
	foreach my $varname (@setable_env_vars) {
		my $s;
		# start with fink's default unless .info says not to
		$s = $defaults{$varname} unless $self->param_boolean("NoSet$varname");
		if ($self->has_param("Set$varname")) {
			# set package-defined value (prepend if still have a default)
			if (defined $s) {
				$s = $self->param("Set$varname") . " $s";
			} else {
				$s = $self->param("Set$varname");
			}
		}
		if (defined $s) {
			# %-expand and store if we have anything at all
			$script_env{$varname} = &expand_percent($s, $expand, $self->get_info_filename." \"set$varname\" or \%Fink::PkgVersion::get_env::defaults");
		} else {
			# otherwise do not set
			delete $script_env{$varname};
		}
	}

	# If UseMaxBuildJobs is absent or set to True, turn on MaxBuildJobs
	# (unless phase is 'installing')
	# UseMaxBuildJobs:true (explicit or absent) overrides SetNoMAKEFLAGS
	# but SetMAKEFLAGS values override MaxBuildJobs
	if ((!$self->has_param('UseMaxBuildJobs') || $self->param_boolean('UseMaxBuildJobs')) && !($phase eq 'installing') && $config->has_param('MaxBuildJobs')) {
		my $mbj = $config->param('MaxBuildJobs');
		if ($mbj =~ /^\d+$/  && $mbj > 0) {
			if (defined $script_env{'MAKEFLAGS'}) {
				# append (MAKEFLAGS has right-to-left precedence,
				# unlike compiler *FLAGS variables)
				$script_env{'MAKEFLAGS'} = "-j$mbj " . $script_env{'MAKEFLAGS'};
			} else {
				$script_env{'MAKEFLAGS'} = "-j$mbj";
			}
		} else {
			warn "Ignoring invalid MaxBuildJobs value in fink.conf: " .
				"$mbj is not a positive integer\n";
		}
	}

# FIXME: (No)SetPATH is undocumented
	unless ($self->has_param('NoSetPATH')) {
		# Get distribution once for better readability 
		# since we want to append a "v" for future-proofing.
		my $distro = version->parse ('v'.$config->param("Distribution")); 
		# use path-prefix-* to give magic to 'gcc' and related commands
		# Clang isn't the default compiler for Xcode 4.x, so wrapping mandatory on 10.7 and 10.8/Xcode 4.x .
		# Includes unused argument error suppression for clang-5's C compiler for 10.8 and 10.9 .
		$script_env{'PATH'} = ensure_clang_prefix() . ':' . $script_env{'PATH'}; 
		if  ( $distro ge version->parse ("v10.9") ) {
			# Use -stdlib=libc++ for c++/g++/clang++ on 10.9 and later.
			# Also includes unused argument error suppression for clang-5's C++ compiler for 10.9.
			$script_env{'PATH'} = ensure_libcxx_prefix() . ':' . $script_env{'PATH'};
		}
	}

# FIXME: On the other hand, (No)SetJAVA_HOME *is* documented (but unused)
	# special things for Type:java
	if (not $self->has_param('SetJAVA_HOME') or not $self->has_param('SetPATH')) {
		if ($self->is_type('java')) {
			my ($JAVA_HOME, $subtype, $dir, $versions_dir, @dirs);
			if ($subtype = $self->get_subtype('java')) {
				$subtype = '' if ($subtype eq 'java');
				chomp ($JAVA_HOME=`/usr/libexec/java_home`);
			}
			$script_env{'JAVA_HOME'} = $JAVA_HOME unless $self->has_param('SetJAVA_HOME');
			$script_env{'PATH'}      = $JAVA_HOME . '/bin:' . $script_env{'PATH'} unless $self->has_param('SetPATH');
		}
	}

	# cache a copy so caller's changes to returned val don't touch cached val
	if (not $self->{_bootstrap}) {
		$self->{$cache} = { %script_env };
	}

	return \%script_env;
}

### run script

sub run_script {
	my $self = shift;
	my $script = shift;
	my $phase = shift;
	my $no_expand = shift || 0;
	my $nonroot_okay = shift || 0;
	my $ignore_result = shift || 0;

	# Expand percent shortcuts
	$script = &expand_percent($script, $self->{_expand}, $self->get_info_filename." $phase script") unless $no_expand;

	# Run the script under the modified environment
	my $result;
	# Don't build as nobody if BuildAsNobody: false
	my $build_as_nobody = $self->get_family_parent()->param_boolean("BuildAsNobody", 1);
	$nonroot_okay = $nonroot_okay && $build_as_nobody;
	{
		local %ENV = %{$self->get_env($phase)};
		$result = &execute($script, nonroot_okay=>$nonroot_okay);
	}
	if ($result and !$ignore_result) {
		$self->package_error( phase => $phase );
	}
	return $result;
}

=item package_error

	$self->package_error %opts;

Issue an error message, for when part of the build process fails. The
following %opts are known:

=over 4

=item phase (required)

The phase of the build process ("patching", "compiling", "installing",
etc.)

=item nonfatal (optional)

If defined and true, the message is issued as a warning and program
control returns rather than aborting the script.

=item preamble (optional)

Text displayed prior to the standard error-message block.

=back

=cut

sub package_error {
	my $self = shift;
	my %opts = @_;
	my $mbj=$config->param('MaxBuildJobs');
	my $umbj=(!$self->has_param('UseMaxBuildJobs') || $self->param_boolean('UseMaxBuildJobs'));

	my $notifier = Fink::Notify->new();
	my $error = "phase " . $opts{'phase'} . ": " . $self->get_fullname()." failed";
	$notifier->notify(event => 'finkPackageBuildFailed', description => $error);
	if (defined $opts{'preamble'}) {
		$error .= "\n\n" . $opts{'preamble'};
	}
	$error .= "\n\n" .
		"Before reporting any errors, please run \"fink selfupdate\" and try again.\n" ;
	if ( $umbj && ($mbj > 1)) {
		$error .= 	"Also try using \"fink configure\" to set your maximum build jobs to 1 and\n" .
					"attempt to build the package again." ;
		}
	$error .= "\nIf you continue to have issues, please check to see if the FAQ on Fink's \n".
		"website solves the problem.  If not, ask on one (not both, please) of\n".
		"these mailing lists:\n\n" .
		"\tThe Fink Users List <fink-users\@lists.sourceforge.net>\n".
		"\tThe Fink Beginners List <fink-beginners\@lists.sourceforge.net>";
	if ($self->has_param('maintainer')) {
		if ($self->param('maintainer') !~ /fink(.*-core|-devel)/) {
			$error .= ",\n\nwith a carbon copy to the maintainer:\n" .
				"\n".
				"\t" . $self->param('maintainer') . "\n" .
				"\n" .
				"Note that this is preferable to emailing just the maintainer directly,\n".
				"since most fink package maintainers do not have access to all possible\n" .
				"hardware and software configurations"
		}
	}

	$error .= ".\n\nPlease try to include the complete error message in your report.  This\n" .
			"generally consists of a compiler line starting with e.g. \"gcc\" or \"g++\"\n" .
			"followed by the actual error output from the compiler.\n\n".
			"Also include the following system information:\n";

	{       # pulled from Config.pm  Maybe we ought to have a separate module
		# for this
		require Fink::FinkVersion;
		require Fink::SelfUpdate;

		my ($method, $timestamp, $misc) = &Fink::SelfUpdate::last_done;
		my $dv = "selfupdate-$method";
		$dv .= " ($misc)" if length $misc;
		$dv .= ' '.localtime($timestamp) if $timestamp;

		$error .= "Package manager version: "
			. Fink::FinkVersion::fink_version() . "\n";
		$error .= "Distribution version: "
			. $dv
			. ', ' . $config->param('Distribution')
			. ', ' . $config->param('Architecture')
			. ($config->mixed_arch() ? ' (forged)' : '')
			. "\n";

		my @trees=$config->get_treelist();
		$error .= "Trees: @trees\n";
		my $hash = Fink::VirtPackage->list()->{'xcode.app'};
		my $version = $hash->{version};
		if ($hash->{status} !~ "not-installed") {
			$error .= "Xcode.app: ".(split /-/,$version)[0]."\n"; # Revision not needed
		} else {
			$error .= "No recognized Xcode.app installed\n";
		}
		$hash = Fink::VirtPackage->list()->{'xcode'};
		$version = $hash->{version};
		if ($hash->{status} !~ "not-installed") {
			$error .= "Xcode command-line tools: ".(split /-/,$version)[0]."\n"; # Revision not needed
		} else {
			$error .= "No recognized Xcode CLI installed\n";
		}
		if ($umbj) {
			$error .= "Max. Fink build jobs:  ".$config->param('MaxBuildJobs')."\n";
		} else {
			$error .= $self->get_fullname() ." is set to build with only one job.\n";
		}
	}

	# need trailing newline in the actual die/warn to prevent
	# extraneous perl diagnostic msgs?
	$opts{'nonfatal'} ? warn "$error\n"	: die "$error\n";
}

### get_perl_dir_arch

sub get_perl_dir_arch {
	my $self = shift;

	# grab perl version, if present
	my $perlversion   = "";
	my $perldirectory = "";
	my $perlarchdir;
	if ($self->is_type('perl') and $self->get_subtype('perl') ne 'perl') {
		$perlversion = $self->get_subtype('perl');
		$perldirectory = "/" . $perlversion;
	}

	### PERL= needs a full path or you end up with
	### perlmods trying to run ../perl$perlversion
	###
	### But when $perlversion is at least 5.10.0, we call it
	### with /usr/bin/arch instead, unless the architecture is powerpc
	###
	my $perlcmd;
	if ($perlversion) {
		if ((&version_cmp($perlversion, '>=',  "5.10.0")) and $config->param('Architecture') ne 'powerpc') {
			$perlcmd = "/usr/bin/arch -%m perl".$perlversion ;
			### FIXME: instead of hardcoded expectation of system-perl
			### perl kernel, check if matches %v of system-perl, then
			###   $perlversion =~ /(5\.\d+)\.*/;
			###   $perlcmd = "/usr/bin/arch -%m perl$1";
			if ($perlversion eq  "5.12.3" and Fink::Services::get_kernel_vers() eq '11') {
				# 10.7 system-perl is 5.12.3, but the only supplied
				# interpreter is /usr/bin/perl5.12 (not perl5.12.3).
				$perlcmd = "/usr/bin/arch -%m perl5.12";
			} elsif ($perlversion eq  "5.12.4" and Fink::Services::get_kernel_vers() eq '12') {
				# 10.8 system-perl is 5.12.4, but the only supplied
				# interpreter is /usr/bin/perl5.12 (not perl5.12.4).
				$perlcmd = "/usr/bin/arch -%m perl5.12";
			} elsif ($perlversion eq  "5.16.2" and Fink::Services::get_kernel_vers() eq '13') {
				# 10.9 system-perl is 5.16.2, but the only supplied
				# interpreter is /usr/bin/perl5.16 (not perl5.16.2)
				$perlcmd = "/usr/bin/arch -%m perl5.16";
			} elsif ($perlversion eq  "5.18.2" and Fink::Services::get_kernel_vers() eq '14') {
				# 10.10 system-perl is 5.18.2, but the only supplied
				# interpreter is /usr/bin/perl5.18 (not perl5.18.2)
				$perlcmd = "/usr/bin/arch -%m perl5.18";
			} elsif ($perlversion eq  "5.18.2" and Fink::Services::get_kernel_vers() eq '15') {
				# 10.11 system-perl is 5.18.2, but the only supplied
				# interpreter is /usr/bin/perl5.18 (not perl5.18.2)
				$perlcmd = "/usr/bin/arch -%m perl5.18";
			} elsif ($perlversion eq  "5.18.2" and Fink::Services::get_kernel_vers() eq '16') {
				# 10.12 system-perl is 5.18.2, but the only supplied
				# interpreter is /usr/bin/perl5.18 (not perl5.18.2)
				$perlcmd = "/usr/bin/arch -%m perl5.18";
			} elsif ($perlversion eq  "5.18.2" and Fink::Services::get_kernel_vers() eq '17') {
				# 10.13 system-perl is 5.18.2, but the only supplied
				# interpreter is /usr/bin/perl5.18 (not perl5.18.2)
				$perlcmd = "/usr/bin/arch -%m perl5.18";
			}
		} else {
			$perlcmd = get_path('perl'.$perlversion);
		}
	} else {
		# Hardcode so it doesn't change as packages are installed, removed
		$perlcmd = "/usr/bin/perl";
		# 10.5/x86_64 is a special case
		if (($config->param("Distribution") eq "10.5") and (get_arch() eq "x86_64")) {
			$perlcmd = "$basepath/bin/perl5.8.8";
		}
	}

	if (exists $perl_archname_cache{$perlcmd}) {
		return (@{$perl_archname_cache{$perlcmd}});
	}

	if (-x $perlcmd) {
		($perlarchdir) = (`/usr/bin/env -i $perlcmd -MConfig -eprint+Config::config_vars+archname` =~ /archname='(.*)'/);
	} else {
		# hardcode just in case  :P
		if (&version_cmp($perlversion, '>=' ,  "5.8.1")) {
			$perlarchdir = 'darwin-thread-multi-2level';
		} else {
			$perlarchdir = 'darwin';
		}
	}

	$perl_archname_cache{$perlcmd} = [ $perldirectory, $perlarchdir, $perlcmd ];
	return ($perldirectory, $perlarchdir, $perlcmd);
}

### get_ruby_dir_arch

sub get_ruby_dir_arch {
	my $self = shift;

	# grab ruby version, if present
	my $rubyversion   = "";
	my $rubydirectory = "";
# FIXME: Hardcoded arch :/
	my $rubyarchdir   = "powerpc-darwin";
	if ($self->is_type('ruby') and $self->get_subtype('ruby') ne 'ruby') {
		$rubyversion = $self->get_subtype('ruby');
		$rubydirectory = "/" . $rubyversion;
	}
	### ruby= needs a full path or you end up with
	### rubymods trying to run ../ruby$rubyversion
	my $rubycmd = get_path('ruby'.$rubyversion);

	return ($rubydirectory, $rubyarchdir, $rubycmd);
}

=item get_install_directory

  my $dir = $pv->get_install_directory;
  my $dir = $pv->get_install_directory $pkg;

Get the directory into which the install phase will put files. If $pkg is
specified, will get get the destdir for a package of that full-name.

=cut

sub get_install_directory {
	my $self = shift;
	my $pkg = shift || $self->get_fullname();
	return "$buildpath/root-$pkg";
}

=item get_control_section

  my $section = $pv->get_control_section();

Get the section of the package for the purposes of .deb control files. May be
distinct from get_section.

=cut

sub get_control_section {
	my $self = shift;
	my $section = $self->get_section();
	$section = "base" if $section eq "bootstrap";
	return $section;
}

=item get_priority

  my $prio = $pv->get_priority();

Get the apt priority of this package.

=cut

sub get_priority {
	my $self = shift;
	my $prio = "optional";
	if (grep { $_ eq $self->get_name() } qw(apt apt-shlibs storable)) {
		$prio = "important";
	}
	if ($self->param_boolean("Essential")) {
		$prio = "required";
	}
	return $prio;
}

=item make_spec

  my $spec = $pv-make_spec;

Make a unique specifier for this package object.

=cut

sub make_spec {
	my $self = shift;
	return { name => $self->get_name, version => $self->get_fullversion };
}

=item resolve_spec

  my $pv = Fink::PkgVersion->resolve_spec($spec);

Find the PkgVersion corresponding to the given specifier. If none exists,
die! Invalid specifiers should NOT exist.

=cut

sub resolve_spec {
	my $class = shift;
	my $spec = shift;

	# Don't use this unless you know what you're doing!
	my $noload = shift || 0;

	my $pv = undef;
	my $po = Fink::Package->package_by_name($spec->{name});
	$pv = $po->get_version($spec->{version}, $noload) if $po;

	confess "FATAL: Could not resolve package spec $spec->{name} $spec->{version}"
		unless $pv;
	return $pv;
}

# PRIVATE: $pv->_disconnect
# Disconnect this package from other package objects.
# Magic happens here, do not use from outside of Fink::Package.
sub _disconnect {
	my $self = shift;

	if ($self->has_parent) {
		$self->{parent} = $self->get_parent->make_spec;
		delete $self->{parent_obj};
	} else {
		$self->{_splitoffs} = [ map { $_->make_spec } $self->parent_splitoffs ];
		delete $self->{_splitoffs_obj};
	}
}

=item is_essential

  my $bool = $pv->is_essential;

Returns whether or not this package is essential.

=cut

sub is_essential {
	my $self = shift;
	return $self->param_boolean('Essential');
}

=item built_with_essential

  my $bool = $pv->built_with_essential;

Returns true if and only if building this package involves also building an
essential package.

=cut

sub built_with_essential {
	my $self = shift;
	return scalar(grep { $_->is_essential } $self->get_splitoffs(1, 1));
}

=item is_obsolete

  my $bool = $pv->is_obsolete;

Returns true if the package is marked as obsolete. That status is
indicated by listing a Depends:fink-obsolete-packages.

=cut

sub is_obsolete {
	my $self = shift;

	my $deps = $self->pkglist_default('Depends','');
	my $rdeps = $self->pkglist_default('RuntimeDepends','');
	$deps = $deps.", ".$rdeps;

	return $deps =~ /(\A|,)\s*fink-obsolete-packages(\(|\s|,|\Z)/;
}


=item info_level

  my $info_level = $pv->info_level;

Get the value of N in the InfoN that wrapped this package, or 1 (one) if no
InfoN wrapper was used.

=cut

sub info_level {
	my $self = shift;
	return $self->param('_info_level', 1);
}

=item dpkg_changed

  Fink::PkgVersion->dpkg_changed;

This method should be called whenever the state of dpkg has changed,
ie: whenever packages are installed or removed. It makes sure that caches
of dpkg information are regenerated.

=cut

sub dpkg_changed {
	# Do nothing for now.
}

=item log_output

	$self->log_output;
	$self->log_output $loggable;

If the $loggable is true, open a logfile in /tmp and begin sending a
copy of all STDOUT and STDERR to it. The logfile must not already
exist (there is no "append" or "overwrite" mode). If $loggable is
false (or not given), the logfile is closed. Multiple logfiles cannot
be chained together. If one is already active, from B<any> PkgVersion
object, attempting to open another one will first close the
previously-opened one.

=cut

our $output_logfile = undef;
our %orig_fh = ();

sub log_output {
	my $self = shift;
	my $loggable = shift;

	# if user gave logfile filename, assume he meant to log output
	return unless Fink::Config::get_option("log_output")
		||        Fink::Config::get_option("logfile");

	# stop logging if we were doing so
	# (redirect STD* back to their original file descriptors)
	if (defined $output_logfile) {
		foreach (qw/ STDOUT STDERR /) {
			fileno($orig_fh{lc $_}) or die "Bogus saved $_!\n";
		}
		open STDOUT, '>&=', $orig_fh{stdout};
		open STDERR, '>&=', $orig_fh{stderr};
		print "Closed logfile $output_logfile\n";
		undef $output_logfile;
	}

	# start logging if caller wants us to do so
	if ($loggable) {
		$output_logfile = Fink::Config::get_option("logfile");
		if ($output_logfile) {
			$output_logfile = &expand_percent(
				$output_logfile,
				$self->get_family_parent()->{_expand},
				'build log filename'
			);

			# so many layers of sublaunching, changing uid, and $HOME,
			# and cwd fiddling, too confusing to know what the base is
			# for relative paths
			unless ($output_logfile =~ /^\//) {
				die "--logfile must be an absolute path\n";
			}

			# make sure logfile can be written
			sysopen my $log_fh, $output_logfile, O_WRONLY | O_CREAT
				or die "Can't write logfile $output_logfile: $!\n";
			close $log_fh;
			# No tests of explicitly given filename...trust that user
			# knows what he's doing.

		} else {
			# no user-specified, so we'll use default
			$output_logfile = '/tmp/fink-build-log'
				. '_' . $self->get_family_parent()->get_name()
				. '_' . $self->get_family_parent()->get_fullversion()
				. '_' . strftime('%Y.%m.%d-%H.%M.%S', localtime);

			# make sure logfile does not already exist (blindly writing to
			# a file with a predictable filename in a world-writable
			# directory as root is Bad)
			sysopen my $log_fh, $output_logfile, O_WRONLY | O_CREAT | O_EXCL
				or die "Can't write logfile $output_logfile: $!\n";
			close $log_fh;
		}

		# stash original STD* file descriptors
		open $orig_fh{stdout}, '>&', STDOUT
			or die "Can't dup STDOUT: $!\n";
		open $orig_fh{stderr}, '>&', STDERR
			or die "Can't dup STDERR: $!\n";

		# set up the logging handle tees
		print "Logging output to logfile $output_logfile\n";
		open STDOUT, "| tee -i -a \"$output_logfile\""
			or die "Can't log STDOUT: $!\n";
		open STDERR, "| tee -i -a \"$output_logfile\" >&2"
			or die "Can't log STDERR: $!\n";
	}
}

=item _instscript

	print DPKG_SCRIPT $self->_instscript(@args);

Returns a bash shell fragment that checks for the fink-instscripts
helper program and calls it using the given @args list. $args[0] is
the script name (preinst, postinst, prerm, postrm) and $args[1] is the
script action type (for example, updatepod). The meaning of the
remainder of @args depends on the specific script and action type.

=cut

sub _instscript {
	my $self = shift;
	my @args;

	for (@_) {
		my $arg = $_;
		$arg =~ s/\'/\\\'/gs;
		push(@args, $arg);
	}

	my $return = "\n";
	$return .= "[ -x \%p/bin/fink-instscripts ] && \%p/bin/fink-instscripts " . join(" ", map { "'" . $_ . "'" } @args) . "\n";
	$return .= "[ ! -x \%p/bin/fink-instscripts ] && echo 'WARNING: this package was generated with fink 0.25 or higher, and will lose some functionality if' && \\\n";
	$return .=                                      "echo '         installed using an older version of fink.'\n";

	return $return;
}

=item get_full_trees

  my @trees = $pv->get_full_trees;

Get the fink.conf trees in which this package is located. This includes both
the 'Archive' and 'Component', eg: 'stable/main'.

=item get_full_tree

  my $trees = $pv->get_full_tree;

Get the highest priority tree in which this package is located.

=cut

sub get_full_trees {
	my ($self) = @_;
	return map { join('/', @$_) } @{$self->{_full_trees}};
}
sub get_full_tree {
	return ($_[0]->get_full_trees)[-1];
}

=item get_shlibs_field

	my $shlibs_field = $pv->get_shlibs_field;

Returns a multiline string of the Shlibs entries. Conditionals are
supported as prefix to a whole entry (not to specific dependencies
like a pkglist field). The string will always be defined, but will be
null if no entries, and every entry (even last) will have trailing
newline.

=cut

sub get_shlibs_field {
	my $self = shift;

	my @shlibs_raw = split /\n/, $self->param_default_expanded('Shlibs', '');  # lines from .info
	my $shlibs_cooked = '';  # processed results
	foreach my $info_line (@shlibs_raw) {
		next if $info_line =~ /^#/;  # skip comments
		if ($info_line =~ s/^\s*\((.*?)\)//) {
			# have a conditional
			next if not &eval_conditional($1, "Shlibs of ".$self->get_info_filename);
		}
		$info_line =~ /^\s*(.*?)\s*$/;  # strip off leading/trailing whitespace
		$shlibs_cooked .= "$1\n" if length $1;
	}
	$shlibs_cooked;
}

=item scanpackages

  scanpackages;

Scan the packages for the packages we built this run.

=cut

sub scanpackages {
	# Scan packages in the built trees, if that's desired
	if (%built_trees) {
		my $autoscan = !$config->has_param("AutoScanpackages")
			|| $config->param_boolean("AutoScanpackages");

		if ($autoscan && apt_available) {
			require Fink::Engine; # yuck
			Fink::Engine::scanpackages({}, [ keys %built_trees ]);
			Fink::Engine::aptget_update();
		}
		%built_trees = ();
	}
}

=item pkg_build_as_user_group

  $self->pkg_build_as_user_group();

If BuildAsNobody: false is set, return
{qw/ user root group admin user:group root:admin /}

Otherwise, return the results from Fink::Config::build_as_user_group()

=cut

sub pkg_build_as_user_group {
	my $self = shift;
	if ($self->has_parent()) {
		# whole build process for .info, not overrideable in splitoffs
		return $self->get_parent()->pkg_build_as_user_group();
	}
	if (! $self->param_boolean("BuildAsNobody", 1)) {
		# package asserts BAN:false, so use root
		# NB: keep this in sync with Config::build_as_user_group!
		return {
			'user'       => "root",
			'group'      => "admin",
			'user:group' => "root:admin"
		};
	}
	# default to fink global control
	return Fink::Config::build_as_user_group();
}

=back

=cut

### EOF

1;
# vim: ts=4 sw=4 noet
