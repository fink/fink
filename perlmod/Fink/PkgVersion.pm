#
# Fink::PkgVersion class
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

package Fink::PkgVersion;
use Fink::Base;
use Fink::Services qw(&filename &execute &execute_script
					  &expand_percent &latest_version
					  &print_breaking
					  &prompt_boolean &prompt_selection
					  &collapse_space &read_properties_var
					  &file_MD5_checksum &version_cmp
					  &get_arch &get_system_perl_version
					  &get_path);
use Fink::Config qw($config $basepath $libpath $debarch $buildpath);
use Fink::NetAccess qw(&fetch_url_to_file);
use Fink::Mirror;
use Fink::Package;
use Fink::Status;
use Fink::VirtPackage;
use Fink::Bootstrap qw(&get_bsbase);

use File::Basename qw(&dirname);

use POSIX qw(uname);

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

END { }				# module clean-up code here (global destructor)


### self-initialization
sub initialize {
	my $self = shift;
	my ($pkgname, $epoch, $version, $revision, $filename, $source, $type);
	my ($depspec, $deplist, $dep, $expand, $configure_params, $destdir);
	my ($parentpkgname, $parentdestdir);
	my ($i, $path, @parts, $finkinfo_index, $section);
	my $arch = get_arch();

	$self->SUPER::initialize();

	$self->{_name} = $pkgname = $self->param_default("Package", "");
	$self->{_version} = $version = $self->param_default("Version", "0");
	$self->{_revision} = $revision = $self->param_default("Revision", "0");
	$self->{_epoch} = $epoch = $self->param_default("Epoch", "0");
	$self->{_type} = $type = lc $self->param_default("Type", "");
	# split off perl version number, when given with the type
	if ($type =~ s/^perl\s+([0-9]+\.[0-9]+\.[0-9]+)/perl/) {
		$self->{_perlversion} = $1;
		$self->{_type} = $type;
	}
	# the following is set by Fink::Package::scan
	$self->{_filename} = $filename = $self->{thefilename};

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
			die "Path \"$filename\" contains no finkinfo directory!\n";
		}
		
		# compute the "section" of this package, e.g. "net", "devel", "crypto"...
		$section = $parts[$finkinfo_index-1]."/";
		if ($finkinfo_index < $#parts) {
			$section = "" if $section eq "main/";
			$section .= join("/", @parts[$finkinfo_index+1..$#parts])."/";
		}
		$self->{_section} = substr($section,0,-1);	 # cut last /
		$parts[$finkinfo_index] = "binary-$debarch";
		$self->{_debpath} = join("/", @parts);
		$self->{_debpaths} = [];
		for ($i = $#parts; $i >= $finkinfo_index; $i--) {
			push @{$self->{_debpaths}}, join("/", @parts[0..$i]);
		}
		
		# determine the package tree ("stable", "unstable", etc.)
				@parts = split(/\//, substr($filename,length("$basepath/fink/dists/")));
		$self->{_tree}	= $parts[0];
	} else {
		# for dummy descriptions generated from dpkg status data alone
		$self->{_patchpath} = "";
		$self->{_section} = "unknown";
		$self->{_debpath} = "";
		$self->{_debpaths} = [];
		
		# assume "binary" tree
		$self->{_tree} = "binary";
	}

	# some commonly used stuff
	$self->{_fullversion} = (($epoch ne "0") ? "$epoch:" : "").$version."-".$revision;
	$self->{_fullname} = $pkgname."-".$version."-".$revision;
	$self->{_debname} = $pkgname."_".$version."-".$revision."_".$debarch.".deb";
	# percent-expansions
	if ($self->param("_type") eq "perl") {
		# grab perl version, if present
		my ($perldirectory, $perlarchdir, $perlcmd) = $self->get_perl_dir_arch();

		$configure_params = "PERL=$perlcmd PREFIX=\%p INSTALLPRIVLIB=\%p/lib/perl5$perldirectory INSTALLARCHLIB=\%p/lib/perl5$perldirectory/$perlarchdir INSTALLSITELIB=\%p/lib/perl5$perldirectory INSTALLSITEARCH=\%p/lib/perl5$perldirectory/$perlarchdir INSTALLMAN1DIR=\%p/share/man/man1 INSTALLMAN3DIR=\%p/share/man/man3 INSTALLSITEMAN1DIR=\%p/share/man/man1 INSTALLSITEMAN3DIR=\%p/share/man/man3 INSTALLBIN=\%p/bin INSTALLSITEBIN=\%p/bin INSTALLSCRIPT=\%p/bin ".
			$self->param_default("ConfigureParams", "");
	} else {
		$configure_params = "--prefix=\%p ".
			$self->param_default("ConfigureParams", "");
	}
	$destdir = "$buildpath/root-".$self->{_fullname};
	if ($self->{_type} eq "splitoff") {
		my $parent = $self->{parent};
		$parentpkgname = $parent->{_name};
		$parentdestdir = "$buildpath/root-".$parent->{_fullname};
	} else {
		$parentpkgname = $pkgname;
		$parentdestdir = $destdir;
		$self->{_splitoffs} = [];
	}
	$expand = { 'n' => $pkgname,
				'e' => $epoch,
				'v' => $version,
				'r' => $revision,
				'f' => $self->{_fullname},
				'p' => $basepath,
				'd' => $destdir,
				'i' => $destdir.$basepath,
				'm' => $arch,

				'N' => $parentpkgname,
				'P' => $basepath,
				'D' => $parentdestdir,
				'I' => $parentdestdir.$basepath,

				'a' => $self->{_patchpath},
				'c' => $configure_params,
				'b' => '.'
			};

	$self->{_expand} = $expand;

	$self->{_bootstrap} = 0;

	# expand percents in various fields
	$self->expand_percent_if_available('BuildDepends');
	$self->expand_percent_if_available('Conflicts');
	$self->expand_percent_if_available('Depends');
	$self->expand_percent_if_available('Enhances');
	$self->expand_percent_if_available('Pre-Depends');
	$self->expand_percent_if_available('Provides');
	$self->expand_percent_if_available('Recommends');
	$self->expand_percent_if_available('Replaces');
	$self->expand_percent_if_available('Suggests');

	# from here on we have to distinguish between "real" packages and splitoffs
	if ($self->{_type} eq "splitoff") {
		# so it's a splitoff
		my ($parent, $field);

		$parent = $self->{parent};
		
		if ($parent->has_param('maintainer')) {
			$self->{'maintainer'} = $parent->{'maintainer'};
		}
		if ($parent->has_param('essential')) {
		    $self->{'_parentessential'} = $parent->{'essential'};
		}

		# handle inherited fields
		our @inherited_fields =
		 qw(Description DescDetail Homepage License);

		foreach $field (@inherited_fields) {
			$field = lc $field;
			if (not $self->has_param($field) and $parent->has_param($field)) {
				$self->{$field} = $parent->{$field};
			}
		}
	} else {
		# expand source / sourcerename fields
		$source = $self->param_default("Source", "\%n-\%v.tar.gz");
		if ($source eq "gnu") {
			$source = "mirror:gnu:\%n/\%n-\%v.tar.gz";
		} elsif ($source eq "gnome") {
			$version =~ /(^[0-9]+\.[0-9]+)\.*/;
			$source = "mirror:gnome:sources/\%n/$1/\%n-\%v.tar.gz";
		}
		
		$source = &expand_percent($source, $expand);
		$self->{source} = $source;
		$self->{_sourcecount} = 1;
	
		$self->expand_percent_if_available('SourceRename');
	
		for ($i = 2; $self->has_param('source'.$i); $i++) {
			$self->{'source'.$i} = &expand_percent($self->{'source'.$i}, $expand);
			$self->expand_percent_if_available('Source'.$i.'Rename');
			$self->{_sourcecount} = $i;
		}
	
		# handle splitoff(s)
		if ($self->has_param('splitoff')) {
			$self->add_splitoff($self->{'splitoff'});
		}
		for ($i = 2; $self->has_param('splitoff'.$i); $i++) {
			$self->add_splitoff($self->{'splitoff'.$i});
		}
	}

	if (exists $self->{_splitoffs} and @{$self->{_splitoffs}} > 0) {
		my $splitoff;
		for $splitoff (@{$self->{_splitoffs}}) {
			@{$splitoff->{_relatives}} = ($self, grep {$_->get_name() ne $splitoff->get_name()} @{$self->{_splitoffs}});
		}
		$self->{_relatives} = $self->{_splitoffs};
	}
}

### expand percent chars in the given field, if that field exists

sub expand_percent_if_available {
	my $self = shift;
	my $field = lc shift;

	if ($self->has_param($field)) {
		$self->{$field} = &expand_percent($self->{$field}, $self->{_expand});
	}
}

### add a splitoff package

sub add_splitoff {
	my $self = shift;
	my $splitoff_data = shift;
	my $filename = $self->{_filename};
	my ($properties, $package, $pkgname, $splitoff);
	
	# get rid of any indention first
	$splitoff_data =~ s/^\s+//gm;
	
	# get the splitoff package name
	$properties = &read_properties_var($filename, $splitoff_data);
	$pkgname = $properties->{'package'};
	unless ($pkgname) {
		print "No package name for SplitOff in $filename\n";
	}
	
	# expand percents in it, to allow e.g. "%n-shlibs"
	$properties->{'package'} = $pkgname = &expand_percent($pkgname, $self->{_expand});
	
	# copy version information
	$properties->{'version'} = $self->{_version};
	$properties->{'revision'} = $self->{_revision};
	$properties->{'epoch'} = $self->{_epoch};
	
	# set the type, and link the splitoff to its "parent" (=us)
	$properties->{'type'} = "splitoff";
	$properties->{parent} = $self;
	
	# get/create package object for the splitoff
	$package = Fink::Package->package_by_name_create($pkgname);
	
	# create object for this particular version
	$properties->{thefilename} = $filename;
	$splitoff = Fink::Package->inject_description($package, $properties);
	
	# add it to the list of splitoffs
	push @{$self->{_splitoffs}}, $splitoff;
}

### merge duplicate package description

sub merge {
	my $self = shift;
	my $dup = shift;
	
	print "Warning! Not a dummy package\n" if $self->{_type} ne 'dummy';
	push @{$self->{_debpaths}}, @{$dup->{_debpaths}};
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

	$self->{_bootstrap} = 1;
	
	foreach	 $splitoff (@{$self->{_splitoffs}}) {
		$splitoff->enable_bootstrap($bsbase);
	}

}

sub disable_bootstrap {
	my $self = shift;
	my ($destdir);
	my $splitoff;

	$destdir = "$buildpath/root-".$self->{_fullname};
	$self->{_expand}->{p} = $basepath;
	$self->{_expand}->{d} = $destdir;
	$self->{_expand}->{i} = $destdir.$basepath;
	if ($self->{_type} eq "splitoff") {
		my $parent = $self->{parent};
		my $parentdestdir = "$buildpath/root-".$parent->{_fullname};
		$self->{_expand}->{D} = $parentdestdir;
		$self->{_expand}->{I} = $parentdestdir.$basepath;
	} else {
		$self->{_expand}->{D} = $self->{_expand}->{d};
		$self->{_expand}->{I} = $self->{_expand}->{i};
	};
	
	$self->{_bootstrap} = 0;
	
	foreach	 $splitoff (@{$self->{_splitoffs}}) {
		$splitoff->disable_bootstrap();
	}
}

### get package name, version etc.

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

sub get_fullversion {
	my $self = shift;
	return $self->{_fullversion};
}

sub get_fullname {
	my $self = shift;
	return $self->{_fullname};
}

sub get_debname {
	my $self = shift;
	return $self->{_debname};
}

sub get_debpath {
	my $self = shift;
	return $self->{_debpath};
}

sub get_debfile {
	my $self = shift;
	return $self->{_debpath}."/".$self->{_debname};
}

sub get_section {
	my $self = shift;
	return $self->{_section};
}

sub get_instsize {
	my $self = shift;
	my $path = shift;

	### FIXME ### This should be done in perl
	### Need to get the full size in bytes of %i
	my ($size) = split(/\s+/, `/usr/bin/du -sk "$path" 2>/dev/null`);
	if ($size =~ /^(\d+)$/) {
		$size = ($1 * 1024);
	} else {
		$size = 0;
	}

	return $size;
}

sub get_tree {
	my $self = shift;
	return $self->{_tree};
}

### other accessors

sub is_multisource {
	my $self = shift;
	return $self->{_sourcecount} > 1;
}

sub get_source {
	my $self = shift;
	my $index = shift || 1;
	if ($index < 2) {
		return $self->param("Source");
	} elsif ($index <= $self->{_sourcecount}) {
		return $self->param("Source".$index);
	}
	return "-";
}

sub get_tarball {
	my $self = shift;
	my $index = shift || 1;
	if ($index < 2) {
		if ($self->has_param("SourceRename")) {
			return $self->param("SourceRename");
		}
		return &filename($self->param("Source"));
	} elsif ($index <= $self->{_sourcecount}) {
		if ($self->has_param("Source".$index."Rename")) {
			return $self->param("Source".$index."Rename");
		}
		return &filename($self->param("Source".$index));
	}
	return "-";
}

sub get_checksum {
	my $self = shift;
	my $index = shift || 1;
	if ($index == 1) {
		if ($self->has_param("Source-MD5")) {
			return $self->param("Source-MD5");
		}
	} elsif ($index >= 2 and $index <= $self->{_sourcecount}) {
		if ($self->has_param("Source".$index."-MD5")) {
			return $self->param("Source".$index."-MD5");
		}
	}		
	return "-";
}


sub get_custom_mirror {
	my $self = shift;

	if (exists $self->{_custom_mirror}) {
		return $self->{_custom_mirror};
	}

	if ($self->has_param("CustomMirror")) {
		$self->{_custom_mirror} =
			Fink::Mirror->new_from_field(&expand_percent($self->param("CustomMirror"), $self->{_expand}));
	} else {
		$self->{_custom_mirror} = 0;
	}
	return $self->{_custom_mirror};
}

sub get_build_directory {
	my $self = shift;
	my ($dir);

	if (exists $self->{_builddir}) {
		return $self->{_builddir};
	}

	if ($self->{_type} eq "bundle" || $self->{_type} eq "nosource"
			|| $self->param_boolean("NoSourceDirectory")) {
		$self->{_builddir} = $self->get_fullname();
	}
	elsif ($self->has_param("SourceDirectory")) {
		$self->{_builddir} = $self->get_fullname()."/".
			&expand_percent($self->param("SourceDirectory"), $self->{_expand});
	}
	else {
		$dir = $self->get_tarball();
		if ($dir =~ /^(.*)\.tar(\.(gz|z|Z|bz2))?$/) {
			$dir = $1;
		}
		if ($dir =~ /^(.*)\.(tgz|zip)$/) {
			$dir = $1;
		}

		$self->{_builddir} = $self->get_fullname()."/".$dir;
	}

	$self->{_expand}->{b} = "$buildpath/".$self->{_builddir};
	return $self->{_builddir};
}

### generate description

sub format_description {
	my $s = shift;

	# remove last newline (if any)
	chomp $s;
	# replace empty lines with "."
	$s =~ s/^\s*$/\./mg;
	# add leading space
	$s =~ s/^/ /mg;

	return "$s\n";
}

sub format_oneline {
	my $s = shift;
	my $maxlen = shift || 0;

	chomp $s;
	$s =~ s/\s*\n\s*/ /sg;
	$s =~ s/^\s+//g;
	$s =~ s/\s+$//g;

	if ($maxlen && length($s) > $maxlen) {
		$s = substr($s, 0, $maxlen-3)."...";
	}

	return $s;
}

sub get_shortdescription {
	my $self = shift;
	my $limit = shift || 75;
	my ($desc);

	if ($self->has_param("Description")) {
		$desc = &format_oneline($self->param("Description"), $limit);
	} else {
		$desc = "[Package ".$self->get_name()." version ".$self->get_fullversion()."]";
	}
	return $desc;
}

sub get_description {
	my $self = shift;
	my $style = shift || 0;
	my ($desc, $s);

	if ($self->has_param("Description")) {
		$desc = &format_oneline($self->param("Description"), 75);
	} else {
		$desc = "[Package ".$self->get_name()." version ".$self->get_fullversion()."]";
	}
	$desc .= "\n";

	if ($self->has_param("DescDetail")) {
		$desc .= &format_description($self->param("DescDetail"));
	}

	if ($style != 1) {
		if ($self->has_param("DescUsage")) {
			$desc .= " .\n Usage Notes:\n";
			$desc .= &format_description($self->param("DescUsage"));
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
	my ($i);

	if ($self->{_type} eq "bundle" || $self->{_type} eq "nosource" ||
			$self->{_type} eq "dummy") {
		return 1;
	}

	for ($i = 1; $i <= $self->{_sourcecount}; $i++) {
		if (not defined $self->find_tarball($i)) {
			return 0;
		}
	}
	return 1;
}

sub is_present {
	my $self = shift;

	if (defined $self->find_debfile()) {
		return 1;
	}
	return 0;
}

sub is_installed {
	my $self = shift;

	if ((&version_cmp(Fink::Status->query_package($self->{_name}), '=', $self->get_fullversion())) or
	   (&version_cmp(Fink::VirtPackage->query_package($self->{_name}), '=', $self->get_fullversion()))) {
		return 1;
	}
	return 0;
}

### source tarball finding

sub find_tarball {
	my $self = shift;
	my $index = shift || 1;
	my ($archive, $found_archive);
	my (@search_dirs, $search_dir);

	$archive = $self->get_tarball($index);
	if ($archive eq "-") {	# bad index
		return undef;
	}

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

### binary package finding

sub find_debfile {
	my $self = shift;
	my ($path, $fn);

	foreach $path (@{$self->{_debpaths}}, "$basepath/fink/debs") {
		$fn = $path."/".$self->{_debname};
		if (-f $fn) {
			return $fn;
		}
	}
	return undef;
}

### get dependencies

# Possible parameters:
# 0 - return runtime dependencies only
# 1 - return runtime & build dependencies
# 2 - return build dependencies only
sub resolve_depends {
	my $self = shift;
	my $include_build = shift || 0;
	my (@speclist, @deplist, $altlist);
	my ($altspec, $depspec, $depname, $versionspec, $package);
	my ($splitoff, $idx, $split_idx);

	@deplist = ();

	$idx = 0;
	$split_idx = 0;

	# If this is a splitoff, and we are asked for build depends, add the build deps
	# of the master package to the list. In 
	if ($include_build and $self->{_type} eq "splitoff") {
		push @deplist, ($self->{parent})->resolve_depends(2);
		if ($include_build == 2) {
			# The pure build deps of a splitoff are equivalent to those of the parent.
			return @deplist;
		}
	}
	
	@speclist = split(/\s*\,\s*/, $self->param_default("Depends", ""));
	if ($include_build) {
		push @speclist,
			split(/\s*\,\s*/, $self->param_default("BuildDepends", ""));

		# If this is a master package with splitoffs, and build deps are requested,
		# then add to the list the deps of all our aplitoffs.
		# We remember the offset at which we added these in $split_idx, so that we
		# can remove any inter-splitoff deps that would otherwise be introduced by this.
		$split_idx = @speclist;
		foreach	 $splitoff (@{$self->{_splitoffs}}) {
		    push @speclist,
		    split(/\s*\,\s*/, $splitoff->param_default("Depends", ""));
		}
	}

	SPECLOOP: foreach $altspec (@speclist) {
		$altlist = [];
		foreach $depspec (split(/\s*\|\s*/, $altspec)) {
			if ($depspec =~ /^\s*([0-9a-zA-Z.\+-]+)\s*\((.+)\)\s*$/) {
				$depname = $1;
				$versionspec = $2;
			} elsif ($depspec =~ /^\s*([0-9a-zA-Z.\+-]+)\s*$/) {
				$depname = $1;
				$versionspec = "";
			} else {
				die "Illegal spec format: $depspec\n";
			}

			if ($include_build and @{$self->{_splitoffs}} > 0 and
				 ($idx >= $split_idx or $include_build == 2)) {
				# To prevent circular refs in the build dependency graph, we have to
				# remove all our splitoffs from the graph. Exception: any splitoffs
				# this master depends on directly are not filtered. Exception from the
				# exception: if we were called by a splitoff to determine the "meta
				# dependencies" of it, then we again filter out all splitoffs.
				# If you've read till here without mental injuries, congrats :-)
				next SPECLOOP if ($depname eq $self->{_name});
				foreach	 $splitoff (@{$self->{_splitoffs}}) {
					 next SPECLOOP if ($depname eq $splitoff->get_name());
				}
			}

			$package = Fink::Package->package_by_name($depname);

			if (not defined $package) {
				print "WARNING: While resolving dependency \"$depspec\" for package \"".$self->get_fullname()."\", package \"$depname\" was not found.\n";
				next;
			}

			push(@{$package->{_versionspecs}}, $versionspec) unless ($versionspec =~ /^\s*$/);

			if ($versionspec) {
				push @$altlist, $package->get_matching_versions($versionspec);
			} else {
				push @$altlist, $package->get_all_providers();
			}
		}
		if (scalar(@$altlist) <= 0) {
			die "Can't resolve dependency \"$altspec\" for package \"".$self->get_fullname()."\" (no matching packages/versions found)\n";
		}
		push @deplist, $altlist;
		$idx++;
	}

	return @deplist;
}

sub resolve_conflicts {
	my $self = shift;
	my ($confname, $package, @conflist);

	# conflict with other versions of the same package
	# this here includes ourselves, it is treated The Right Way
	# by other routines
	@conflist = Fink::Package->package_by_name($self->get_name())->get_all_versions();

	foreach $confname (split(/\s*\,\s*/,
													 $self->param_default("Conflicts", ""))) {
		$package = Fink::Package->package_by_name($confname);
		if (not defined $package) {
			die "Can't resolve anti-dependency \"$confname\" for package \"".$self->get_fullname()."\"\n";
		}
		push @conflist, [ $package->get_all_providers() ];
	}

	return @conflist;
}

sub get_binary_depends {
	my $self = shift;
	my ($depspec);

	# TODO: modify dependency list on the fly to account for minor
	#	 library versions

	$depspec = $self->param_default("Depends", "");

	return &collapse_space($depspec);
}


### find package and version by matching a specification

sub match_package {
	shift;	# class method - ignore first parameter
	my $s = shift;
	my $quiet = shift || 0;

	my ($pkgname, $package, $version, $pkgversion);
	my ($found, @parts, $i, @vlist, $v, @rlist);

	if (Fink::Config::verbosity_level() < 3) {
		$quiet = 1;
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
			unless $quiet;
		return undef;
	}

	# we now have the package name in $pkgname, the package
	# object in $package, and the
	# still to be matched version (or "###") in $version.
	if ($version eq "###") {
		# find the newest version

		$version = &latest_version($package->list_versions());
		if (not defined $version) {
			# there's nothing we can do here...
			die "no version info available for $pkgname\n";
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
			die "no matching version found for $pkgname\n";
		}
	}

	return $package->get_version($version);
}

###
### PHASES
###

### fetch

sub phase_fetch {
	my $self = shift;
	my $conditional = shift || 0;
	my $dryrun = shift || 0;
	my ($i);

	if ($self->{_type} eq "bundle" || $self->{_type} eq "nosource" ||
			$self->{_type} eq "dummy") {
		return;
	}
	if ($self->{_type} eq "splitoff") {
		($self->{parent})->phase_fetch($conditional, $dryrun);
		return;
	}

	for ($i = 1; $i <= $self->{_sourcecount}; $i++) {
		if (not $conditional or not defined $self->find_tarball($i)) {
			$self->fetch_source($i,0,0,0,$dryrun);
		}
	}
}

sub fetch_source {
	my $self = shift;
	my $index = shift;
	my $tries = shift || 0;
	my $continue = shift || 0;
	my $nomirror = shift || 0;
	my $dryrun = shift || 0;
	my ($url, $file, $checksum, $urlnofile);

	chdir "$basepath/src";

	$url = $self->get_source($index);
	$file = $self->get_tarball($index);
	if($self->has_param("license")) {
		if($self->param("license") =~ /Restrictive\s*$/) {
			$nomirror = 1;
		} 
	}
	
	$checksum = $self->get_checksum($index);
	
	if($dryrun) {
		$urlnofile = $url;
		$urlnofile =~ s/$file//;
		if($urlnofile eq "") {
			return;
		}
		print "$file $checksum";
	} else {
		if($checksum eq '-') {	
			print "WARNING: No MD5 specified for Source #".$index.
							" of package ".$self->get_fullname();
			if ($self->has_param("Maintainer")) {
				print ' Maintainer: '.$self->param("Maintainer") . "\n";
			} else {
				print "\n";
			}		
		}
	}
	
	if (&fetch_url_to_file($url, $file, $self->get_custom_mirror(), 
						   $tries, $continue, $nomirror, $dryrun)) {

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
		&print_breaking("In any case, you can download '$file' manually and ".
						"put it in '$basepath/src', then run fink again with ".
						"the same command.");
		print "\n";
		}
		if($dryrun) {
			if ($self->has_param("Maintainer")) {
				print ' "'.$self->param("Maintainer") . "\"\n";
			}
		} else {
			die "file download failed for $file of package ".$self->get_fullname()."\n";
		}
	}
}

### unpack

sub phase_unpack {
	my $self = shift;
	my ($archive, $found_archive, $bdir, $destdir, $unpack_cmd);
	my ($i, $verbosity, $answer, $tries, $checksum, $continue);
	my ($renamefield, @renamefiles, $renamefile, $renamelist, $expand);
	my ($tarcommand, $tarflags, $cat, $gzip, $bzip2, $unzip, $found_archive_sum);

	if ($self->{_type} eq "bundle") {
		return;
	}
	if ($self->{_type} eq "dummy") {
		die "can't build ".$self->get_fullname().
			" because no package description is available\n";
	}
	if ($self->{_type} eq "splitoff") {
		($self->{parent})->phase_unpack();
		return;
	}

	my ($gcc);
	my %gcchash = ('2.95.2' => '2', '2.95' => '2', '3.1' => '3', '3.3' => '3.3');

	if ($self->has_param("GCC")) {
		$gcc = $self->param("GCC");
		chomp(my $gcc_select = `gcc_select`);
		if (not $gcc_select =~ s/^.*gcc version (\S+)\s+.*$/$1/gs) {
			$gcc_select = 'an unknown version';
		}
		if (not exists $gcchash{$gcc}) {
			$gcchash{$gcc} = $gcc;
		}
		if ($gcc_select !~ /^$gcc/) {
			die <<END;

This package must be compiled with GCC $gcc, but you currently have $gcc_select selected.
To correct this problem, run the command:

	sudo gcc_select $gcchash{$gcc}

You may need to install a more recent version of the Developer Tools to be able
to do so.

END
		}
	}

	$bdir = $self->get_fullname();

	$verbosity = "";
	if (Fink::Config::verbosity_level() > 1) {
		$verbosity = "v";
	}

	# remove dir if it exists
	chdir "$buildpath";
	if (-e $bdir) {
		if (&execute("/bin/rm -rf $bdir")) {
			die "can't remove existing directory $bdir\n";
		}
	}

	if ($self->{_type} eq "nosource") {
		$destdir = "$buildpath/$bdir";
		if (&execute("/bin/mkdir -p $destdir")) {
			die "can't create directory $destdir\n";
		}
		return;
	}

	$tries = 0;
	for ($i = 1; $i <= $self->{_sourcecount}; $i++) {
		$archive = $self->get_tarball($i);

		# search for archive, try fetching if not found
		$found_archive = $self->find_tarball($i);
		if (not defined $found_archive or $tries > 0) {
			$self->fetch_source($i, $tries, $continue);
			$continue = 0;
			$found_archive = $self->find_tarball($i);
		}
		if (not defined $found_archive) {
			die "can't find source file $archive for package ".$self->get_fullname()."\n";
		}
		
		# verify the MD5 checksum, if specified
		$checksum = $self->get_checksum($i);
		$found_archive_sum = &file_MD5_checksum($found_archive);
		if ($checksum ne "-" ) { # Checksum was specified
		# compare to the MD5 checksum of the tarball
			if ($checksum ne $found_archive_sum) {
				# mismatch, ask user what to do
				$tries++;
				&print_breaking("The checksum of the file $archive of package ".
								$self->get_fullname()." is incorrect. The most likely ".
								"cause for this is a corrupted or incomplete download\n".
								"Expected: $checksum \nActual: $found_archive_sum \n".
								"It is recommended that you download it ".
								"again. How do you want to proceed?");
				$answer =
					&prompt_selection("Make your choice: ",
								($tries >= 3) ? 1 : 2,
								{ "error" => "Give up",
									"redownload" => "Delete it and download again",													
									"continuedownload" => "Assume it is a partial download and try to continue",
									"continue" => "Don't download, use existing file" },
								( "error", "redownload", "continuedownload", "continue" ));
				if ($answer eq "redownload") {
					&execute("/bin/rm -f $found_archive");
					$i--;
					# Axel leaves .st files around for partial files, need to remove
					if($config->param_default("DownloadMethod") =~ /^axel/)
					{
									&execute("/bin/rm -f $found_archive.st");
					}
					next;		# restart loop with same tarball
				} elsif($answer eq "error") {
					die "checksum of file $archive of package ".$self->get_fullname()." incorrect\n";
				} elsif($answer eq "continuedownload") {
					$continue = 1;
					$i--;
					next;		# restart loop with same tarball			
				}
			}
		} else {
		# No checksum was specifed in the .info file, die die die
			die "No checksum specifed for ".$self->get_fullname()." I got a sum of $found_archive_sum \n";
		}

		# Determine the name of the TarFilesRename in the case of multi tarball packages
		if ($i < 2) {
			$renamefield = "TarFilesRename";
		} else {
			$renamefield = "Tar".$i."FilesRename";
		}

		$renamelist = "";

		# Determine the rename list (if any)
		$tarflags = "-x${verbosity}f -";
		$tarcommand = "/usr/bin/gnutar $tarflags"; # Default to Apple's GNU Tar
		if ($self->has_param($renamefield)) {
			@renamefiles = split(/\s+/, $self->param($renamefield));
			foreach $renamefile (@renamefiles) {
				$renamefile = &expand_percent($renamefile, $expand);
				if ($renamefile =~ /^(.+)\:(.+)$/) {
					$renamelist .= " -s ,$1,$2,";
				} else {
					$renamelist .= " -s ,${renamefile},${renamefile}_tmp,";
				}
			}
			$tarcommand = "/bin/pax -r${verbosity}"; # Use pax for extracting with the renaming feature
		} elsif ( -e "$basepath/bin/tar" ) {
			$tarcommand = "$basepath/bin/tar $tarflags"; # Use Fink's GNU Tar if available
		}
		$bzip2 = "bzip2";
		$unzip = "unzip";
		$gzip = "gzip";
		$cat = "/bin/cat";

		# Determine unpack command
		$unpack_cmd = "cp $found_archive .";
		if ($archive =~ /[\.\-]tar\.(gz|z|Z)$/ or $archive =~ /\.tgz$/) {
		    $unpack_cmd = "$gzip -dc $found_archive | $tarcommand $renamelist";
		} elsif ($archive =~ /[\.\-]tar\.bz2$/) {
			$unpack_cmd = "$bzip2 -dc $found_archive | $tarcommand $renamelist";
		} elsif ($archive =~ /[\.\-]tar$/) {
			$unpack_cmd = "$cat $found_archive | $tarcommand $renamelist";
		} elsif ($archive =~ /\.zip$/) {
			$unpack_cmd = "$unzip -o $found_archive";
		}

		# calculate destination directory
		$destdir = "$buildpath/$bdir";
		if ($i > 1) {
			if ($self->has_param("Source".$i."ExtractDir")) {
				$destdir .= "/".&expand_percent($self->param("Source".$i."ExtractDir"), $self->{_expand});
			}
		}

		# create directory
		if (! -d $destdir) {
			if (&execute("/bin/mkdir -p $destdir")) {
				die "can't create directory $destdir\n";
			}
		}

		# unpack it
		chdir $destdir;
		if (&execute($unpack_cmd)) {
			$tries++;

			$answer =
				&prompt_boolean("Unpacking the file $archive of package ".
								$self->get_fullname()." failed. The most likely ".
								"cause for this is a corrupted or incomplete ".
								"download. Do you want to delete the tarball ".
								"and download it again?",
								($tries >= 3) ? 0 : 1);
			if ($answer) {
				&execute("/bin/rm -f $found_archive");
				$i--;
				next;		# restart loop with same tarball
			} else {
				die "unpacking file $archive of package ".$self->get_fullname()." failed\n";
			}
		}

		$tries = 0;
	}
}

### patch

sub phase_patch {
	my $self = shift;
	my ($dir, $patch_script, $cmd, $patch, $subdir);

	if ($self->{_type} eq "bundle") {
		return;
	}
	if ($self->{_type} eq "dummy") {
		die "can't build ".$self->get_fullname().
				" because no package description is available\n";
	}
	if ($self->{_type} eq "splitoff") {
		($self->{parent})->phase_patch();
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
			"cp -f $libpath/update/config.guess .\n".
			"cp -f $libpath/update/config.sub .\n";
	}
	if ($self->has_param("UpdateConfigGuessInDirs")) {
		foreach $subdir (split(/\s+/, $self->param("UpdateConfigGuessInDirs"))) {
			next unless $subdir;
			$patch_script .=
				"cp -f $libpath/update/config.guess $subdir\n".
				"cp -f $libpath/update/config.sub $subdir\n";
		}
	}

	### copy libtool scripts (ltconfig and ltmain.sh) if required

	if ($self->param_boolean("UpdateLibtool")) {
		$patch_script .=
			"cp -f $libpath/update/ltconfig .\n".
			"cp -f $libpath/update/ltmain.sh .\n";
	}
	if ($self->has_param("UpdateLibtoolInDirs")) {
		foreach $subdir (split(/\s+/, $self->param("UpdateLibtoolInDirs"))) {
			next unless $subdir;
			$patch_script .=
				"cp -f $libpath/update/ltconfig $subdir\n".
				"cp -f $libpath/update/ltmain.sh $subdir\n";
		}
	}

	### copy po/Makefile.in.in if required

	if ($self->param_boolean("UpdatePoMakefile")) {
		$patch_script .=
			"cp -f $libpath/update/Makefile.in.in po/\n";
	}

	### patches specifies by filename

	if ($self->has_param("Patch")) {
		foreach $patch (split(/\s+/,$self->param("Patch"))) {
			$patch_script .= "patch -p1 <\%a/$patch\n";
		}
	}

	### patch

	if ($patch_script ne "") {
		$self->run_script($patch_script, "patching");
	}

	### run custom patch script (if any)

	if ($self->has_param("PatchScript")) {
		$self->run_script($self->param("PatchScript"), "patching");
	}
}

### compile

sub phase_compile {
	my $self = shift;
	my ($dir, $compile_script, $cmd);

	if ($self->{_type} eq "bundle") {
		return;
	}
	if ($self->{_type} eq "dummy") {
		die "can't build ".$self->get_fullname().
				" because no package description is available\n";
	}
	if ($self->{_type} eq "splitoff") {
		($self->{parent})->phase_compile();
		return;
	}

	$dir = $self->get_build_directory();
	if (not -d "$buildpath/$dir") {
		die "directory $buildpath/$dir doesn't exist, check the package description\n";
	}
	chdir "$buildpath/$dir";

	# generate compilation script
	if ($self->has_param("CompileScript")) {
		$compile_script = $self->param("CompileScript");
	} else {
		if ($self->param("_type") eq "perl") {
		    my ($perldirectory, $perlarchdir, $perlcmd) = $self->get_perl_dir_arch();
			$compile_script =
				"$perlcmd Makefile.PL \%c\n".
				"make\n";
			unless ($self->param_boolean("NoPerlTests")) {
				$compile_script .= "make test\n";
			}
		} else {
			$compile_script = 
				"./configure \%c\n".
				"make\n";
		}
	}	 

	### compile

	$self->run_script($compile_script, "compiling");
}

### install

sub phase_install {
	my $self = shift;
	my $do_splitoff = shift || 0;
	my ($dir, $install_script, $cmd, $bdir);

	if ($self->{_type} eq "dummy") {
		die "can't build ".$self->get_fullname().
				" because no package description is available\n";
	}
	if ($self->{_type} eq "splitoff" and not $do_splitoff) {
		($self->{parent})->phase_install();
		return;
	}
	if ($self->{_type} ne "bundle") {
		if ($do_splitoff) {
			$dir = ($self->{parent})->get_build_directory();
		} else {
			$dir = $self->get_build_directory();
		}
		if (not -d "$buildpath/$dir") {
			die "directory $buildpath/$dir doesn't exist, check the package description\n";
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
		$install_script .= "/bin/mkdir -p \%d/DEBIAN\n";
	}
	if ($self->{_type} eq "bundle") {
		$install_script .= "/bin/mkdir -p \%i/share/doc/\%n\n";
		$install_script .= "echo \"\%n is a bundle package that doesn't install any files of its own.\" >\%i/share/doc/\%n/README\n";
	} else {
		if ($self->has_param("InstallScript")) {
			# Run the script part we have so far, then reset it.
			$self->run_script($install_script, "installing");
			$install_script = "";
			# Now run the custom install script
			$self->run_script($self->param("InstallScript"), "installing");
		} elsif ($self->param("_type") eq "perl") {
			# grab perl version, if present
			my ($perldirectory, $perlarchdir) = $self->get_perl_dir_arch();

			$install_script .= 
				"make install PREFIX=\%i INSTALLPRIVLIB=\%i/lib/perl5$perldirectory INSTALLARCHLIB=\%i/lib/perl5$perldirectory/$perlarchdir INSTALLSITELIB=\%i/lib/perl5$perldirectory INSTALLSITEARCH=\%i/lib/perl5$perldirectory/$perlarchdir INSTALLMAN1DIR=\%i/share/man/man1 INSTALLMAN3DIR=\%i/share/man/man3 INSTALLSITEMAN1DIR=\%i/share/man/man1 INSTALLSITEMAN3DIR=\%i/share/man/man3 INSTALLBIN=\%i/bin INSTALLSITEBIN=\%i/bin INSTALLSCRIPT=\%i/bin\n";
		} elsif (not $do_splitoff) {
			$install_script .= "make install prefix=\%i\n";
		} 

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
		my (@files, $file, $source, $target, $target_dir);

		@files = split(/\s+/, $self->param("Files"));
		foreach $file (@files) {
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

			$target_dir = dirname($target);
			$install_script .= "\n/usr/bin/install -d -m 755 $target_dir";
			$install_script .= "\n/bin/mv $source $target_dir/";
		}
	}

	# generate commands to install documentation files
	if ($self->has_param("DocFiles")) {
		my (@docfiles, $docfile, $docfilelist);
		$install_script .= "\n/usr/bin/install -d -m 755 %i/share/doc/%n";

		@docfiles = split(/\s+/, $self->param("DocFiles"));
		$docfilelist = "";
		foreach $docfile (@docfiles) {
			if ($docfile =~ /^(.+)\:(.+)$/) {
				$install_script .= "\n/usr/bin/install -c -p -m 644 $1 %i/share/doc/%n/$2";
			} else {
				$docfilelist .= " $docfile";
			}
		}
		if ($docfilelist ne "") {
			$install_script .= "\n/usr/bin/install -c -p -m 644$docfilelist %i/share/doc/%n/";
		}
	}

	# generate commands to install profile.d scripts
	if ($self->has_param("RuntimeVars")) {
	
		my ($var, $value, $vars, $properties);

		$vars = $self->param("RuntimeVars");
		# get rid of any indention first
		$vars =~ s/^\s+//gm;
		# Read the set if variavkes (but don't change the keys to lowercase)
		$properties = &read_properties_var($self->{_filename}, $vars, 1);

		if(scalar keys %$properties > 0){
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

	$self->run_script($install_script, "installing");

	### splitoffs
	
	my $splitoff;
	foreach	 $splitoff (@{$self->{_splitoffs}}) {
		# iterate over all splitoffs and call their build phase
		$splitoff->phase_install(1);
	}

	### remove build dir

	if (not $do_splitoff) {
		$bdir = $self->get_fullname();
		chdir "$buildpath";
		if (not $config->param_boolean("KeepBuildDir") and not Fink::Config::get_option("keep_build") and -e $bdir) {
			if (&execute("/bin/rm -rf $bdir")) {
				&print_breaking("WARNING: Can't remove build directory $bdir. ".
								"This is not fatal, but you may want to remove ".
								"the directory manually to save disk space. ".
								"Continuing with normal procedure.");
			}
		}
	}
}

### build .deb

sub phase_build {
	my $self = shift;
	my $do_splitoff = shift || 0;
	my ($ddir, $destdir, $control);
	my ($scriptname, $scriptfile, $scriptbody);
	my ($shlibsfile, $shlibsbody);
	my ($conffiles, $listfile, $infodoc);
	my ($daemonicname, $daemonicfile);
	my ($cmd);

	if ($self->{_type} eq "dummy") {
		die "can't build ".$self->get_fullname().
				" because no package description is available\n";
	}
	if ($self->{_type} eq "splitoff" and not $do_splitoff) {
		($self->{parent})->phase_build();
		return;
	}

	chdir "$buildpath";
	$ddir = "root-".$self->get_fullname();
	$destdir = "$buildpath/$ddir";

	if (not -d "$destdir/DEBIAN") {
		if (&execute("/bin/mkdir -p $destdir/DEBIAN")) {
			die "can't create directory for control files for package ".$self->get_fullname()."\n";
		}
	}

	# generate dpkg "control" file

	my ($pkgname, $version, $field, $section, $instsize);
	$pkgname = $self->get_name();
	$version = $self->get_fullversion();
	$section = $self->get_section();
	$instsize = $self->get_instsize("$destdir$basepath");
	$control = <<EOF;
Package: $pkgname
Source: $pkgname
Version: $version
Section: $section
Installed-Size: $instsize
Architecture: $debarch
EOF
	if ($self->param_boolean("Essential")) {
		$control .= "Essential: yes\n";
	}

	eval {
		require File::Find;
		import File::Find;
	};

	my $depline = $self->get_binary_depends();

# Add a dependency on the darwin version (if not already present).
#   We depend on the major version only, in order to prevent users from
#   installing a .deb file created with an incorrect MACOSX_DEPLOYMENT_TARGET
#   value.
# FIXME: Actually, if the package states a darwin version we should combine
#   the version given by the package with the one we want to impose.
#   Instead, right now, we just use the package's version but this means
#   that a package will need to be revised if the darwin major version changes.

	my ($dummy, $darwin_version, $darwin_major_version);
	($dummy,$dummy,$darwin_version) = uname();
	if ($darwin_version =~ /(\d+)/) {
	    $darwin_major_version = $1;
	} else {
	    die "No major version number for darwin!";
	}

	if (not $depline =~ /\bdarwin\b/) {
	    if (not $depline eq '') {
		$depline = $depline . ", ";
	    }
	    $depline = $depline . "darwin (>= $darwin_major_version-1)";
	}

	# FIXME: make sure there are no linebreaks in the following fields
	$control .= "Depends: ".$depline."\n";
	foreach $field (qw(Provides Replaces Conflicts Pre-Depends
										 Recommends Suggests Enhances
										 Maintainer)) {
		if ($self->has_param($field)) {
			$control .= "$field: ".&collapse_space($self->param($field))."\n";
		}
	}
	$control .= "Description: ".$self->get_description();

	### write "control" file

	print "Writing control file...\n";

	open(CONTROL,">$destdir/DEBIAN/control") or die "can't write control file for ".$self->get_fullname().": $!\n";
	print CONTROL $control;
	close(CONTROL) or die "can't write control file for ".$self->get_fullname().": $!\n";

	### update Mach-O Object List
	###
	### (but not for distributions prior to 10.2-gcc3.3)

	my $skip_prebinding = 0;
	my $pkgref = ($self);
	$skip_prebinding++ unless ($config->param("Distribution") ge "10.2-gcc3.3");

	# Why do this?  On the off-chance the parent relationship is recursive (ie, a splitoff
	# depends on a splitoff, instead of the top-level package in the splitoff)
	# we work our way back to the top level, and skip prebinding if things are set
	# anywhere along the way (since the LD_* variables are normally set in the top-level
	# but need to take effect in, say, -shlibs)

	while (exists $pkgref->{_parent}) {
		$skip_prebinding++ if ($pkgref->param_boolean("NoSetLD_PREBIND"));
		$skip_prebinding++ if ($pkgref->has_param("NoSetLD_PREBIND"));
		$pkgref = $pkgref->{_parent};
	}
	$skip_prebinding++ if ($pkgref->param_boolean("NoSetLD_PREBIND"));
	$skip_prebinding++ if ($pkgref->has_param("NoSetLD_PREBIND"));

	# "our" instead of "my", so that it can be referenced later in the post-install script
	our %prebound_files = ();
	unless ($skip_prebinding) {

		print "Finding prebound objects...\n";
		my ($is_prebound, $is_exe, $name);
		find({ wanted => sub {
			# common things that shouldn't be objects
			return if (/\.(bz2|c|cfg|conf|class|cpp|csh|db|dll|gif|gz|h|html|info|ini|jpg|m4|mng|pdf|pl|png|po|py|sh|tar|tcl|txt|wav|xml)$/i);
			return unless (defined $_ and $_ ne "" and -f $_ and not -l $_);
			return if (readlink $_ =~ /\/usr\/lib/); # don't re-prebind stuff in /usr/lib
			#print "\$_ = $_\n";
			$is_prebound = 0;
			$is_exe      = 0;
			$name        = undef;
			my @dep_list;
			if (open(OTOOL, "otool -hLv '$_' |")) {
				while (<OTOOL>) {
					if (/^\s*MH_MAGIC.*EXECUTE.*PREBOUND.*$/) {
						# executable has no install_name, add to the list
						$name = $File::Find::name;
						my $destmeta = quotemeta($destdir);
						$name =~ s/^$destmeta//;
						$is_exe = 1;
						$is_prebound = 1;
					} elsif (/^\s*MH_MAGIC.*EXECUTE.*$/) {
						# if the last didn't match, but this did, it's a
						# non-prebound executable, so skip it
						last;
					} elsif (/^\s*MH_MAGIC.*PREBOUND.*$/) {
						# otherwise it's a dylib of some form, mark it
						# so we can pull the install_name in a few lines
						$is_prebound = 1;
					} elsif (/^\s*MH_MAGIC.*$/) {
						# if it wasn't an executable, and the last didn't
						# match, then it's not a prebound lib
						last;
					} elsif (my ($lib) = $_ =~ /^\s*(.+?) \(compatibility.*$/ and $is_prebound) {
						# we hit the install_name, add it to the list
						unless ($lib =~ /\/libSystem/ or $lib =~ /^\/+[Ss]ystem/ or $lib =~ /^\/usr\/lib/) {
							push(@dep_list, $lib);
						}
					}
				}
				close(OTOOL);
				if ($is_exe) {
					$prebound_files{$name} = \@dep_list;
				} else {
					$name = shift(@dep_list);
					return if (not defined $name);
					$prebound_files{$name} = \@dep_list;
				}
			}
		} }, $destdir);

		if (keys %prebound_files) {
			system('install', '-d', '-m', '755', $destdir . $basepath . '/var/lib/fink/prebound/files') == 0 or
				die "can't make $destdir$basepath/var/lib/fink/prebound/files for ".$self->get_name().": $!\n";
			open(PREBOUND, '>' . $destdir . $basepath . '/var/lib/fink/prebound/files/' . $self->get_name() . '.pblist') or
				die "can't write " . $self->get_name() . '.pblist';
			print PREBOUND join("\n", sort keys %prebound_files), "\n";
			close(PREBOUND);
		}

		print "Writing dependencies...\n";
		for my $key (sort keys %prebound_files) {
			for my $file (@{$prebound_files{$key}}) {
				$file =~ s/\//-/g;
				$file =~ s/^-+//;
				system('install', '-d', '-m', '755', $destdir . $basepath . '/var/lib/fink/prebound/deps/'. $file) == 0 or
					die "can't make $destdir$basepath/var/lib/fink/prebound/deps/$file for ".$self->get_name().": $!\n";
				open(DEPS, '>>' . $destdir . $basepath . '/var/lib/fink/prebound/deps/' . $file . '/' . $self->get_name() . '.deplist') or
					die "can't write " . $self->get_name() . '.deplist';
				print DEPS $key, "\n";
				close(DEPS);
			}
		}
	} # unless ($skip_prebinding)

	### create scripts as neccessary

	foreach $scriptname (qw(preinst postinst prerm postrm)) {
		# get script piece from package description
		if ($self->has_param($scriptname."Script")) {
			$scriptbody = $self->param($scriptname."Script");
		} else {
			$scriptbody = "";
		}

		# add UpdatePOD Code
		if ($self->param_boolean("UpdatePOD")) {
			# grab perl version, if present
			my ($perldirectory, $perlarchdir) = $self->get_perl_dir_arch();

			if ($scriptname eq "postinst") {
				$scriptbody .=
					"\n\n# Updating \%p/lib/perl5/$perlarchdir$perldirectory/perllocal.pod\n".
					"/bin/mkdir -p \%p/lib/perl5$perldirectory/$perlarchdir\n".
					"/bin/cat \%p/share/podfiles$perldirectory/*.pod > \%p/lib/perl5$perldirectory/$perlarchdir/perllocal.pod\n";
			} elsif ($scriptname eq "postrm") {
				$scriptbody .=
					"\n\n# Updating \%p/lib/perl5$perldirectory/$perlarchdir/perllocal.pod\n\n".
					"###\n".
					"### check to see if any .pod files exist in \%p/share/podfiles.\n".
					"###\n\n".
					"perl <<'END_PERL'\n\n".
					"if (-e \"\%p/share/podfiles$perldirectory\") {\n".
					"	 \@files = <\%p/share/podfiles$perldirectory/*.pod>;\n".
					"	 if (\$#files >= 0) {\n".
					"		 exec \"/bin/cat \%p/share/podfiles$perldirectory/*.pod > \%p/lib/perl5$perldirectory/$perlarchdir/perllocal.pod\";\n".
					"	 }\n".
					"}\n\n".
					"END_PERL\n";
			} 
		}

		# add JarFiles Code
		if ($self->has_param("JarFiles")) {
			if (($scriptname eq "postinst") || ($scriptname eq "postrm")) {
				$scriptbody.=
						"\n/bin/mkdir -p %p/share/java".
						"\njars=`/usr/bin/find %p/share/java -name '*.jar'`".
						"\n".'if (test -n "$jars")'.
						"\nthen".
						"\n".'(for jar in $jars ; do echo -n "$jar:" ; done) | sed "s/:$//" > %p/share/java/classpath'.
						"\nelse".
						"\n/bin/rm -f %p/share/java/classpath".
						"\nfi".
						"\nunset jars";
			}
		}

		# add auto-generated parts
		if ($self->has_param("InfoDocs")) {
			if ($scriptname eq "postinst") {
				$scriptbody .= "\n\n# generated from InfoDocs directive\n";
				$scriptbody .= "if [ -f %p/share/info/dir ]; then\n";
				foreach $infodoc (split(/\s+/, $self->param("InfoDocs"))) {
					next unless $infodoc;
					$infodoc = " \%p/share/info/$infodoc" unless $infodoc =~ /\//;
					$scriptbody .= "if [ -f %p/sbin/install-info ]; then\n";
					$scriptbody .= "	%p/sbin/install-info --infodir=\%p/share/info $infodoc\n";
					$scriptbody .= " elif [ -f %p/bootstrap/sbin/install-info ]; then\n";
					$scriptbody .= "	%p/bootstrap/sbin/install-info --infodir=\%p/share/info $infodoc\n";
					$scriptbody .= " fi\n";
								}
				$scriptbody .= "fi\n";
			} elsif ($scriptname eq "prerm") {
				$scriptbody .= "\n\n# generated from InfoDocs directive\n";
				$scriptbody .= "if [ -f %p/share/info/dir ]; then\n";
				foreach $infodoc (split(/\s+/, $self->param("InfoDocs"))) {
					next unless $infodoc;
					$scriptbody .= "	%p/sbin/install-info --infodir=\%p/share/info --remove $infodoc\n";
				}
				$scriptbody .= "fi\n";
			}
		}

		# add the call to redo prebinding on any packages with prebound files
		if (keys %prebound_files > 0 and $scriptname eq "postinst") {
			my $name = $self->get_name();
			$scriptbody .= <<EOF;

if test -x "$basepath/var/lib/fink/prebound/queue-prebinding.pl"; then
	$basepath/var/lib/fink/prebound/queue-prebinding.pl $name
fi

EOF
		}

		# do we have a non-empty script?
		next if $scriptbody eq "";

		# no, so write it out
		$scriptbody = &expand_percent($scriptbody, $self->{_expand});
		$scriptfile = "$destdir/DEBIAN/$scriptname";

		print "Writing package script $scriptname...\n";

		open(SCRIPT,">$scriptfile") or die "can't write $scriptname script for ".$self->get_fullname().": $!\n";
		print SCRIPT <<EOF;
#!/bin/sh
# $scriptname script for package $pkgname, auto-created by fink

set -e

$scriptbody

exit 0
EOF
		close(SCRIPT) or die "can't write $scriptname script for ".$self->get_fullname().": $!\n";
		chmod 0755, $scriptfile;
	}

	### shlibs file

	if ($self->has_param("Shlibs")) {
			$shlibsbody = $self->param("Shlibs");
			chomp $shlibsbody;
			$shlibsbody = &expand_percent($shlibsbody, $self->{_expand});
			$shlibsfile = "$destdir/DEBIAN/shlibs";

			print "Writing shlibs file...\n";

			open(SHLIBS,">$shlibsfile") or die "can't write shlibs file for ".$self->get_fullname().": $!\n";
			print SHLIBS <<EOF;
$shlibsbody
EOF
close(SHLIBS) or die "can't write shlibs file for ".$self->get_fullname().": $!\n";
			chmod 0644, $shlibsfile;
	}

	### config file list

	if ($self->has_param("conffiles")) {
		$listfile = "$destdir/DEBIAN/conffiles";
		$conffiles = join("\n", grep {$_} split(/\s+/, $self->param("conffiles")));
		$conffiles = &expand_percent($conffiles, $self->{_expand})."\n";

		print "Writing conffiles list...\n";

		open(SCRIPT,">$listfile") or die "can't write conffiles list file for ".$self->get_fullname().": $!\n";
		print SCRIPT $conffiles;
		close(SCRIPT) or die "can't write conffiles list file for ".$self->get_fullname().": $!\n";
		chmod 0644, $listfile;
	}

	### daemonic service file

	if ($self->has_param("DaemonicFile")) {
		$daemonicname = $self->param_default("DaemonicName", $self->get_name());
		$daemonicname .= ".xml";
		$daemonicfile = "$destdir$basepath/etc/daemons/".$daemonicname;

		print "Writing daemonic info file $daemonicname...\n";

		if (&execute("/bin/mkdir -p $destdir$basepath/etc/daemons")) {
			die "can't write daemonic info file for ".$self->get_fullname()."\n";
		}
		open(SCRIPT,">$daemonicfile") or die "can't write daemonic info file for ".$self->get_fullname().": $!\n";
		print SCRIPT &expand_percent($self->param("DaemonicFile"), $self->{_expand});
		close(SCRIPT) or die "can't write daemonic info file for ".$self->get_fullname().": $!\n";
		chmod 0644, $daemonicfile;
	}

	### create .deb using dpkg-deb

	if (not -d $self->get_debpath()) {
		if (&execute("/bin/mkdir -p ".$self->get_debpath())) {
			die "can't create directory for packages\n";
		}
	}
	$cmd = "dpkg-deb -b $ddir ".$self->get_debpath();
	if (&execute($cmd)) {
		die "can't create package ".$self->get_debname()."\n";
	}

	if (&execute("/bin/ln -sf ".$self->get_debpath()."/".$self->get_debname()." ".
							 "$basepath/fink/debs/")) {
		die "can't symlink package ".$self->get_debname()." into pool directory\n";
	}

	### splitoffs
	
	my $splitoff;
	foreach	 $splitoff (@{$self->{_splitoffs}}) {
		# iterate over all splitoffs and call their build phase
		$splitoff->phase_build(1);
	}

	### remove root dir

	if (not $config->param_boolean("KeepRootDir") and not Fink::Config::get_option("keep_root") and -e $destdir) {
		if (&execute("/bin/rm -rf $destdir")) {
			&print_breaking("WARNING: Can't remove package root directory ".
							"$destdir. ".
							"This is not fatal, but you may want to remove ".
							"the directory manually to save disk space. ".
							"Continuing with normal procedure.");
		}
	}
}

### activate

sub phase_activate {
	my @packages = @_;
	my (@installable);

	for my $package (@packages) {
		my $deb = $package->find_debfile();

		unless (defined $deb and -f $deb) {
			die "can't find package ".$package->get_debname()."\n";
		}

		push(@installable, $package);
	}

	if (@installable == 0) {
		die "no installable .deb files found!\n";
	}

	my @deb_installable = map { $_->find_debfile() } @installable;
	if (&execute("dpkg -i @deb_installable")) {
		if (@installable == 1) {
			die "can't install package ".$installable[0]->get_fullname()."\n";
		} else {
			die "can't batch-install packages: @deb_installable\n";
		}
	}

	Fink::Status->invalidate();
}

### deactivate

sub phase_deactivate {
	my @packages = @_;

	if (&execute("dpkg --remove @packages")) {
		if (@packages == 1) {
			die "can't remove package ".$packages[0]."\n";
		} else {
			die "can't batch-remove packages: @packages\n";
		}
	}
	Fink::Status->invalidate();
}

### purge

sub phase_purge {
	my @packages = @_;

	if (&execute("dpkg --purge @packages")) {
		if (@packages == 1) {
			die "can't purge package ".$packages[0]."\n";
		} else {
			die "can't batch-purge packages: @packages\n";
		}
	}
	Fink::Status->invalidate();
}

### set environment variables according to spec

sub set_env {
	my $self = shift;
	my ($varname, $s, $expand);
	my %defaults = (
		"CPPFLAGS"                 => "-I\%p/include",
		"LDFLAGS"                  => "-L\%p/lib",
		"LD_PREBIND"               => 1,
		"LD_PREBIND_ALLOW_OVERLAP" => 1,
		"LD_SEG_ADDR_TABLE"        => "$basepath/var/lib/fink/prebound/seg_addr_table",
	);
	my $bsbase = Fink::Bootstrap::get_bsbase();

	if (! -f "$basepath/var/lib/fink/prebound/seg_addr_table") {
		system("mkdir -p '$basepath/var/lib/fink/prebound'");
		if (open(FILEOUT, ">$basepath/var/lib/fink/prebound/seg_addr_table")) {
			print FILEOUT <<END;
0x90000000  0xa0000000  <<< Next split address to assign >>>
0x20000000  <<< Next flat address to assign >>>
END
			close(FILEOUT);
		} else {
			warn "couldn't create seg_addr_table, this may cause compilation to fail!\n";
		}
	}

	# clean the environment
	%ENV = ("HOME" => $ENV{"HOME"});

	# add system path
	$ENV{"PATH"} = "/bin:/usr/bin:/sbin:/usr/sbin";
	
	# add bootstrap path if necessary
	if (-d $bsbase) {
		$ENV{"PATH"} = "$bsbase/bin:$bsbase/sbin:" . $ENV{"PATH"};
	}

	# run init.sh script which will set the path and other additional variables
	if (-r "$basepath/bin/init.sh") {
		my @vars = `sh -c ". $basepath/bin/init.sh ; /usr/bin/env"`;
		chomp @vars;
		%ENV = map { split /=/,$_,2 } @vars;
	}

	# set variables according to the info file
	$expand = $self->{_expand};
	foreach $varname (
			"CC", "CFLAGS",
			"CPP", "CPPFLAGS",
			"CXX", "CXXFLAGS",
			"DYLD_LIBRARY_PATH",
			"LD_PREBIND",
			"LD_PREBIND_ALLOW_OVERLAP",
			"LD_FORCE_NO_PREBIND",
			"LD_SEG_ADDR_TABLE",
			"LD", "LDFLAGS", 
			"LIBRARY_PATH", "LIBS",
			"MACOSX_DEPLOYMENT_TARGET",
			"MAKE", "MFLAGS", "MAKEFLAGS") {
		if ($self->has_param("Set$varname")) {
			$s = $self->param("Set$varname");
			if (exists $defaults{$varname} and
					not $self->param_boolean("NoSet$varname")) {
				$s .= " ".$defaults{$varname};
			}
			$ENV{$varname} = &expand_percent($s, $expand);
		} else {
			if (exists $defaults{$varname} and
					defined $defaults{$varname} and 
					not $self->param_boolean("NoSet$varname")) {
				$s = $defaults{$varname};
				$ENV{$varname} = &expand_percent($s, $expand);
			} else {
				delete $ENV{$varname};
			}
		}
	}
	my $sw_vers = Fink::Services::get_sw_vers();
	if (not $self->has_param("SetMACOSX_DEPLOYMENT_TARGET") and defined $sw_vers and $sw_vers ne "0") {
		$sw_vers =~ s/^(\d+\.\d+).*$/$1/;
		if ($sw_vers eq "10.2") {
			$ENV{'MACOSX_DEPLOYMENT_TARGET'} = '10.1';
		} else {
			$ENV{'MACOSX_DEPLOYMENT_TARGET'} = $sw_vers;
		}
	}
}

### run script

sub run_script {
	my $self = shift;
	my $script = shift;
	my $phase = shift;
	my %env_bak;
	
	# Backup the environment variables
	%env_bak = %ENV;
	
	# Expand percent shortcuts
	$script = &expand_percent($script, $self->{_expand});
	
	# Clean the environment
	$self->set_env();
	
	# Run the script
	if (&execute_script($script)) {
		die $phase." ".$self->get_fullname()." failed\n";
	}
	
	# Restore the environment
	%ENV = %env_bak;
}



### get_perl_version_dir_arch

sub get_perl_dir_arch {
	my $self = shift;

	# grab perl version, if present
	my $perlversion   = "";
#get_system_perl_version();
	my $perldirectory = "";
	my $perlarchdir;
	if ($self->has_param("_perlversion")) {
		$perlversion = $self->param("_perlversion");
		$perldirectory = "/" . $perlversion;
	    }
	### PERL= needs a full path or you end up with
	### perlmods trying to run ../perl$perlversion
	my $perlcmd = get_path('perl'.$perlversion);

	if ($perlversion ge "5.8.1") {
		$perlarchdir = 'darwin-thread-multi-2level';
	} else {
		$perlarchdir = 'darwin';
	}

	return ($perldirectory, $perlarchdir,$perlcmd);
}

### EOF
1;
