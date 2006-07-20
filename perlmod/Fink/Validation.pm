# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Validation module
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2006 The Fink Package Manager Team
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
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#

package Fink::Validation;

use Fink::Services qw(&read_properties &read_properties_var &expand_percent &file_MD5_checksum &pkglist2lol &version_cmp);
use Fink::Config qw($config);
use Cwd qw(getcwd);
use File::Find qw(find);
use File::Path qw(rmtree);
use File::Temp qw(tempdir);
use File::Basename qw(basename);

use strict;
use warnings;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
	$VERSION	 = 1.00;
	@ISA		 = qw(Exporter);
	@EXPORT		 = qw();
	@EXPORT_OK	 = qw(&validate_info_file &validate_dpkg_file &validate_dpkg_unpacked);
	%EXPORT_TAGS = ( );			# eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

# Currently, the Set* and NoSet* fields only support a limited list of variables.
our @set_vars =
	qw(
		cc cflags cpp cppflags cxx cxxflags dyld_library_path
		ld_prebind ld_prebind_allow_overlap ld_force_no_prebind
		ld_seg_addr_table ld ldflags library_path libs
		macosx_deployment_target make mflags makeflags path
	);

# Required fields.
our @required_fields = map {lc $_}
	qw(Package Version Revision Maintainer);
our @splitoff_required_fields = map {lc $_}
	qw(Package);

# All fields that expect a boolean value
our %boolean_fields = map {$_, 1}
	(
		qw(builddependsonly addshlibdeps essential nosourcedirectory updateconfigguess updatelibtool updatepod noperltests),
		map {"noset".$_} @set_vars
	);

# Obsolete fields, generate a warning
our %obsolete_fields = map {$_, 1}
	qw(comment commentport commenstow usegettext);

# Fields to check for hardcoded /sw
our %check_hardcode_fields = map {$_, 1}
	( 
		qw(
		 patchscript
		 configureparams
		 compilescript
		 installscript
		 shlibs
		 preinstscript
		 postinstscript
		 prermscript
		 postrmscript
		 conffiles
		 daemonicfile
		),
		(map {"set".$_} @set_vars)
	);

# Fields in which %n/%v can and should be used
our %name_version_fields = map {$_, 1}
	qw(
		 source sourcedirectory sourcerename
		 source0 source0extractdir source0rename
		 patch
		);

# Free-form text fields which display in 'fink describe'
our %text_describe_fields = map {$_, 1}
	qw(
		 descdetail descusage
		);

# Allowed values for the license field
our %allowed_license_values = map {$_, 1}
	(
	 "GPL", "LGPL", "GPL/LGPL", "BSD", "Artistic", "Artistic/GPL", "GFDL", 
	 "GPL/GFDL", "LGPL/GFDL", "GPL/LGPL/GFDL", "LDP", "GPL/LGPL/LDP", 
	 "OSI-Approved", "Public Domain", "Restrictive/Distributable", 
	 "Restrictive", "Commercial", "DFSG-Approved"
	);

# Allowed values of the architecture field
our %allowed_arch_values = map {lc $_, 1}
	(
	 'powerpc',
	 'i386',
	);

# List of all valid fields, 
# sorted in the same order as in the packaging manual.
# (A few are handled elsewhere in this module, but are also included here,
#  commented out, for easier reference when comparing with the manual.)

our %valid_fields = map {$_, 1}
	(
		(
#  initial data:
		 'package',
		 'version',
		 'revision',
		 'epoch',
		 'description',
		 'type',
		 'license',
		 'maintainer',
		 'architecture',
#  dependencies:
		 'depends',
		 'runtimedepends',
		 'builddepends',
		  #  need documentation for buildconflicts
		 'buildconflicts',
		 'provides',
		 'conflicts',
		 'replaces',
		 'recommends',
		 'suggests',
		 'enhances',
		 'pre-depends',
		 'essential',
		 'builddependsonly',
		 'addshlibdeps',
#  unpack phase:
		 'custommirror',
		 'source',
		 #sourceN
		 'sourcedirectory',
		 'nosourcedirectory',
		 #sourceNextractdir
		 'sourcerename',
		 #sourceNRename
		 'source-checksum',
		 #sourceN-checksum
		 'source-md5',
		 #sourceN-md5
		 'tarfilesrename',
		 #tarNfilesrename
#  patch phase:
		 'updateconfigguess',
		 'updateconfigguessindirs',
		 'updatelibtool',
		 'updatelibtoolindirs',
		 'updatepomakefile',
		 'patch',
		 'patchfile',
		 'patchfile-md5',
		 'patchscript'
#  compile phase:
		),
		(map {"set".$_} @set_vars),
		(map {"noset".$_} @set_vars),
		(
		 'configureparams',
		 'gcc',
		 'compilescript',
		 'noperltests',
#  install phase:
		 'updatepod',
		 'installscript',
		 'appbundles',
		 'jarfiles',
		 'docfiles',
		 'shlibs',
		 'runtimevars',
		 'splitoff',
		 #splitoffN
		 #files
#  build phase:
		 'preinstscript',
		 'postinstscript',
		 'prermscript',
		 'postrmscript',
		 'conffiles',
		 'infodocs',
		 'daemonicfile',
		 'daemonicname',
#  additional data:
		 'homepage',
		 'descdetail',
		 'descusage',
		 'descpackaging',
		 'descport'
		)
	);

# List of all fields which are legal in a splitoff
our %splitoff_valid_fields = map {$_, 1}
	(
		(
#  initial data:
		 'package',
		 'type',
		 'license',
#  dependencies:
		 'depends',
		 'provides',
		 'conflicts',
		 'replaces',
		 'recommends',
		 'suggests',
		 'enhances',
		 'pre-depends',
		 'essential',
		 'builddependsonly',
#  install phase:
		 'updatepod',
		 'installscript',
		 'jarfiles',
		 'docfiles',
		 'shlibs',
		 'runtimevars',
		 'files',
#  build phase:
		 'preinstscript',
		 'postinstscript',
		 'prermscript',
		 'postrmscript',
		 'conffiles',
		 'infodocs',
		 'daemonicfile',
		 'daemonicname',
#  additional data:
		 'homepage',
		 'description',
		 'descdetail',
		 'descusage',
		 'descpackaging',
		 'descport',
		)
	);

# fields that are dpkg "Depends"-style lists of packages
our %pkglist_fields = map {lc $_, 1}
	(
	 'Depends',
	 'BuildDepends',
	 'Conflicts',
	 'BuildConflicts',
	 'Provides',
	 'Suggests',
	 'Recommends',
	 'Enhances',
	 'Architecture',
	);

END { }				# module clean-up code here (global destructor)

#
# Check a given .deb file for standard compliance
# returns boolean of whether everything is okay
# 
# Should check/verify the following in .info files:
#	+ the filename matches %f.info
#	+ patch file (from Patch and PatchScript) is present
#	+ if PatchFile given, make sure file is present, validate its
#		checksum (vs PatchFile-MD5), make sure Patch is not present,
#		that %a is not used in PatchScript but that %{patchfile} or
#		{%default_script} is, and that pkg declares BuildDepends on a
#		version of fink that supports this field.
#	+ all required fields are present
#	+ warn if obsolete fields are encountered
#	+ warn about missing Description/Maintainer/License fields
#	+ warn about overlong Description fields
#	+ warn about Description starting with "A" or "An"
#	+ warn about Description containing the package name
#	+ warn if Description looks like a reserved/keyword form
#	+ warn if boolean fields contain bogus values
#	+ warn if fields seem to contain the package name/version, suggest %n/%v
#		 be used (excluded from this are fields like Description, Homepage etc.)
#	+ warn if unknown fields are encountered
#	+ warn if /sw is hardcoded in the script or set fields or patch file
#		(from Patch and PatchScript)
#	+ correspondence between source* and source*-md5 fields
#	+ if type is bundle/nosource - warn about usage of "Source" etc.
#	+ if 'fink describe' output will display poorly on vt100
#	+ Check Package/Version/Revision for disallowed characters
#	+ Check if have sufficient InfoN if using their features
#	+ Warn if shbang in dpkg install-time scripts
#	+ Error if %i used in dpkg install-time scripts
#	+ Warn if non-ASCII chars in any field
#	+ Check syntax of dpkg Depends-style fields
#	+ validate dependency syntax
#	+ Type is not 'dummy'
#	+ Explicit interp in pkg-building *Script get -ev or -ex
#	+ Check syntax and values in Architecture field
#	+ Make sure PV objects can be created
#	+ No duplicate %n in a variant set
#
# TODO: Optionally, should sort the fields to the recommended field order
#	- better validation of splitoffs
#	- correct format of Shlibs: (including misuse of %v-%r)
#	- use of %n in SplitOff:Package: (should be %N)
#	- use of SplitOff:Depends: %n (should be %N (tracker Bugs #622810)
#	- actually instantiate the Package or PkgVersion object
#	  (easier to try it than to check for some broken-ness here)
#	- run a mock build phase (catch typos in dependencies,
#	  BuildDependsOnly violations, etc.)
#	- make sure for each %type_*[foo] there is a Type: foo
#	- ... other things, make suggestions ;)
#
sub validate_info_file {
	my $filename = shift;
	my $val_prefix = shift;
	my ($properties, $info_level);
	my ($pkgname, $pkginvarname, $pkgversion, $pkgrevision, $pkgfullname, $pkgdestdir, $pkgpatchpath, @patchfiles);
	my $value;
	my ($basepath, $buildpath);
	my ($type, $type_hash);
	my $expand = {};
	my $looks_good = 1;
	my $error_found = 0;

	my $full_filename = $filename;  # we munge $filename later

	if ($config->verbosity_level() >= 3) {
		print "Validating package file $filename...\n";
	}
	
	#
	# Check for line endings before reading properties
	#
	open(INPUT, "<$filename") or die "Couldn't read $filename: $!\n";
	my $info_file_content = <INPUT>;
	close INPUT or die "Couldn't read $filename: $!\n";
	if ($info_file_content =~ m/\r\n/s) {
		print "Error: Info file has DOS line endings. ($filename)\n";
		return 0;
	}
	if ($info_file_content =~ m/\r/s) {
		print "Error: Info file has Mac line endings. ($filename)\n";
		return 0;
	}

	# read the file properties
	$properties = &read_properties($filename);
	($properties, $info_level) = Fink::PkgVersion->handle_infon_block($properties, $filename);
	return 0 unless keys %$properties;
	
	# determine the base path
	if (defined $val_prefix) {
		$basepath = $val_prefix;
		$buildpath = "$basepath/src/fink.build";
	} else {
		$basepath = $config->param_default("basepath", "/sw");
		$buildpath = $config->param_default("buildpath", "$basepath/src/fink.build");
	}

	# make sure have InfoN (N>=2) if use Info2 features
	if ($info_level < 2) {
		# fink-0.16.1 can't even index if unknown %-exp in *any* field!
		foreach (sort keys %$properties) {
			next if /^splitoff\d*$/;  # SplitOffs checked later
			if ($properties->{$_} =~ /\%type_(raw|pkg)\[.*?\]/) {
				print "Error: Use of %type_ expansions (field \"$_\") requires InfoN level 2 or higher. ($filename)\n";
				return 0;
			}
		}
	}

	( $pkginvarname = $pkgname = $properties->{package} ) =~ s/\%type_(raw|pkg)\[.*?\]//g;
	# right now we don't know how to deal with variants too well
	if (defined ($type = $properties->{type}) ) {
		$type =~ s/(\S+?)\s*\(:?.*?\)/$1 ./g;  # use . for all subtype lists
		$type_hash = Fink::PkgVersion->type_hash_from_string($type,$filename);
		foreach (keys %$type_hash) {
			( $expand->{"type_pkg[$_]"} = $expand->{"type_raw[$_]"} = $type_hash->{$_} ) =~ s/\.//g;
		}
		$pkgname = &expand_percent($pkgname, $expand, $filename.' Package');
	}

	$pkgversion = $properties->{version};
	$pkgversion = '' unless defined $pkgversion;
	$pkgrevision = $properties->{revision};
	$pkgrevision = '' unless defined $pkgrevision;
	$pkgfullname = "$pkgname-$pkgversion-$pkgrevision";
	$pkgdestdir = "$buildpath/root-".$pkgfullname;
	
	if ($filename =~ /\//) {
		my @parts = split(/\//, $filename);
		$filename = pop @parts;		# remove filename
		$pkgpatchpath = join("/", @parts);
	} else {
		$pkgpatchpath = "";
	}

	#
	# First check for critical errors
	#

	if ($pkgname =~ /[^+\-.a-z0-9]/) {
		print "Error: Package name may only contain lowercase letters, numbers,";
		print "'.', '+' and '-' ($filename)\n";
		$looks_good = 0;
	}
	if ($pkgversion =~ /[^+\-.a-z0-9]/) {
		print "Error: Package version may only contain lowercase letters, numbers,";
		print "'.', '+' and '-' ($filename)\n";
		$looks_good = 0;
	}
	if ($pkgrevision =~ /[^+.a-z0-9]/) {
		print "Error: Package revision may only contain lowercase letters, numbers,";
		print "'.' and '+' ($filename)\n";
		$looks_good = 0;
	}
	
	# TODO: figure out how to validate multivariant Type:
	#  - make sure syntax is okay
	#  - make sure each type appears as a type_*[] in Package

	return 0 unless ($looks_good);

	#
	# Now check for other mistakes
	#

	# .info filename contains parent package-name (without variants)
	# and may contain version-revision and/or arch components
{
	my $base_filename = $pkgname;

	# variants with Package: foo-%type[bar] leave excess hyphens
	$base_filename =~ s/-+/-/g;
	$base_filename =~ s/-*$//g;

	# build permutations
	my (@ok_filenames) = (
		"$base_filename",
		"$base_filename-$pkgversion-$pkgrevision",
	);	
	if (my $arch = $properties->{architecture}) {
		if ($arch !~ /,/) {
			# single-arch package
			$arch =~ s/\s+//g;
			
			push @ok_filenames, (
				"$base_filename-$arch",
				"$base_filename-$arch-$pkgversion-$pkgrevision",
				"$base_filename-$pkgversion-$pkgrevision-$arch",
			);
		}
	}
	map $_ .= ".info", @ok_filenames;

	unless (grep $filename eq $_, @ok_filenames) {
		print "Warning: File name should be one of [", (join ' ', sort @ok_filenames), "]. ($filename)\n";
		$looks_good = 0;
	}
}

	# Make sure Maintainer is in the correct format: Joe Bob <jbob@foo.com>
	$value = $properties->{maintainer};
	if (!defined $value or $value !~ /^[^<>@]+\s+<\S+\@\S+>$/) {
		print "Warning: Malformed value for \"maintainer\". ($filename)\n";
		$looks_good = 0;
	}

	# License should always be specified, and must be one of the allowed set
	$value = $properties->{license};
	if (defined $value) {
		if ($value =~ /,\s*\([^,]*$/) {
			print "Warning: Last license in list must not be conditional. ($filename)\n";
			$looks_good = 0;
		}
		$value =~ s/\(.*?\)//g;  # remove all conditionals
		$value =~ s/^\s*//;      # ...which sometimes leaves leading whitespace
		foreach (split /\s*,\s*/, $value) {
			if (not $allowed_license_values{$_}) {
				print "Warning: Unknown license \"$_\". ($filename)\n";
				$looks_good = 0;
			}
		}
	} elsif (not (defined($properties->{type}) and $properties->{type} =~ /\bbundle\b/i)) {
		print "Warning: No license specified. ($filename)\n";
		$looks_good = 0;
	}

	# check SourceN and corresponding fields

	# find them all
	my %source_fields = map { lc $_, 1 } grep { /^source(|[2-9]|[1-9]\d+)$/ } keys %$properties;

	# have Source or SourceN when we shouldn't
	if (exists $properties->{type} and $properties->{type} =~ /\b(nosource|bundle)\b/i) {
		if (keys %source_fields) {
			print "Warning: Source and/or SourceN field(s) found for \"Type: $1\". ($filename)\n";
			$looks_good = 0;
		}
	} else {
		if (!exists $source_fields{source}) {
			print "Warning: the implicit \"Source\" feature is deprecated and will be removed soon.\nAdd \"Source: %n-%v.tar.gz\" to assure future compatibility. ($filename)\n";
			$looks_good = 0;
		}
		$source_fields{source} = 1;  # always have Source (could be implicit)
	}
	if (exists $properties->{source} and $properties->{source} =~ /^none$/i and keys %source_fields > 1) {
		print "Error: \"Source: none\" but found SourceN field(s). ($filename)\n";
		$looks_good = 0;
	}

	# check for bogus "none" sources and sources without MD5
	# remove "none" from %source_fields (will use in main field loop)
	foreach (keys %source_fields) {
		if (exists $properties->{$_} and $properties->{$_} =~ /^none$/i) {
			delete $source_fields{$_};  # keep just real ones
			if (/\d+/) {
				print "Warning: \"$_: none\" is a no-op. ($filename)\n";
				$looks_good = 0;
			}
		} else {
			my $md5_field      = $_ . "-md5";
			my $checksum_field = $_ . "-checksum";
			if (!exists $properties->{$md5_field} and !defined $properties->{$md5_field} and !exists $properties->{$checksum_field} and !defined $properties->{$checksum_field}) {
				print "Error: \"$_\" does not have a corresponding \"$md5_field\" or \"$checksum_field\" field. ($filename)\n";
				$looks_good = 0;
			}
		}
		
	}

	if (&validate_info_component($properties, "", $filename, $info_level) == 0) {
		$looks_good = 0;
	}

	# Loop over all fields and verify them
	foreach my $field (keys %$properties) {
		$value = $properties->{$field};

		# Warn if field is obsolete
		if ($obsolete_fields{$field}) {
			print "Warning: Field \"$field\" is obsolete. ($filename)\n";
			$looks_good = 0;
			next;
		}

		# Boolean field?
		if ($boolean_fields{$field} and not ((lc $value) =~ /^\s*(true|yes|on|1|false|no|off|0)\s*$/)) {
			print "Warning: Boolean field \"$field\" contains suspicious value \"$value\". ($filename)\n";
			$looks_good = 0;
			next;
		}

		# If this field permits percent expansion, check if %f/%n/%v should be used
		if ($name_version_fields{$field} and $value) {
			 if ($value =~ /\b\Q$pkgfullname\E\b/) {
				 print "Warning: Field \"$field\" contains full package name. Use %f instead. ($filename)\n";
				 $looks_good = 0;
			 } elsif ($value =~ /\b\Q$pkgversion\E\b/) {
				 print "Warning: Field \"$field\" contains package version. Use %v instead. ($filename)\n";
				 $looks_good = 0;
			 }
		}

		# these fields are printed verbatim, so check to make sure
		# they won't look weird on an 80-column plain-text terminal
		if (Fink::Config::get_option("Pedantic") and $text_describe_fields{$field} and $value) {
			# no intelligent word-wrap so warn for long lines
			my $maxlinelen = 79;
			foreach my $line (split /\n/, $value) {
				if (length $line > $maxlinelen) {
					print "Warning: \"$field\" contains line(s) exceeding $maxlinelen characters. ($filename)\nThis field may be displayed with line-breaks in the middle of words.\n";
					$looks_good = 0;
					next;
				}
			}
		}

		# Check for any source-related field without associated Source(N) field
		if ($field =~ /^source(\d*)-checksum|source(\d*)-md5|source(\d*)rename|tar(\d*)filesrename|source(\d+)extractdir$/) {
			my $sourcefield = defined $+  # corresponding Source(N) field
				? "source$+"
				: "source";  
			if (!exists $source_fields{$sourcefield}) {
				my $msg = $field =~ /-(checksum|md5)$/
					? "Warning" # no big deal
					: "Error";  # probably means typo, giving broken behavior
					print "$msg: \"$field\" specified for non-existent \"$sourcefield\". ($filename)\n";
					$looks_good = 0;
				}
			next;
		}

		# Validate splitoffs
		if ($field =~ m/^splitoff([2-9]|[1-9]\d+)?$/) {
			# Parse the splitoff properties
			my $splitoff_properties = $properties->{$field};
			my $splitoff_field = $field;
			$splitoff_properties =~ s/^\s+//gm;
			$splitoff_properties = &read_properties_var("$field of \"$filename\"", $splitoff_properties);

			# make sure have InfoN (N>=2) if use Info2 features
			if ($info_level < 2) {
				# fink-0.16.1 can't even index if unknown %-exp in *any* field!
				foreach (sort keys %$splitoff_properties) {
					if ($splitoff_properties->{$_} =~ /\%type_(raw|pkg)\[.*?\]/) {
						print "Error: Use of %type_ expansions (field \"$_\" of \"$field\") requires InfoN level 2 or higher. ($filename)\n";
						$looks_good = 0;
						return 0;
					}
				}
			}

			if (&validate_info_component($splitoff_properties, $splitoff_field, $filename, $info_level) == 0) {
				$looks_good = 0;
			}

			if (defined ($value = $splitoff_properties->{files})) {
				if ($value =~ /\/[\s\r\n]/ or $value =~ /\/$/) {
					print "Warning: Field \"files\" of \"$splitoff_field\" contains entries that end in \"/\" ($filename)\n";
					$looks_good = 0;
				}
			}
		} # end of SplitOff field validation
	}

	# error for having %p/lib in RuntimeVars
	if (exists $properties->{runtimevars} and defined $properties->{runtimevars}) {
		for my $line (split(/\n/, $properties->{runtimevars})) {
			if ($line =~ m,^\s*(DYLD_LIBRARY_PATH:\s+($basepath|\%p)/lib/?)\s*$,) {
				print "Error: '$1' in RuntimeVars will break many shared libraries. ($filename)\n";
				$looks_good = 0;
			}
		}
	}

	# Warn for missing / overlong package descriptions
	$value = $properties->{description};
	if (not (defined $value and length $value)) {
		print "Error: No package description supplied. ($filename)\n";
		$looks_good = 0;
	} elsif (length($value) > 60) {
		print "Error: Length of package description exceeds 60 characters. ($filename)\n";
		$looks_good = 0;
	} elsif (Fink::Config::get_option("Pedantic")) {
		# Some pedantic checks
		if (length($value) > 45) {
			print "Warning: Length of package description exceeds 45 characters. ($filename)\n";
			$looks_good = 0;
		}
		if ($value =~ m/^[Aa]n? /) {
			print "Warning: Description starts with \"A\" or \"An\". ($filename)\n";
			$looks_good = 0;
		}
		if ($value =~ m/^[a-z]/) {
			print "Warning: Description starts with lower case. ($filename)\n";
			$looks_good = 0;
		}
		if ($value =~ /(\b\Q$pkgname\E\b|%\{?n)/i) {
			print "Warning: Description contains package name. ($filename)\n";
			$looks_good = 0;
		}
		if ($value =~ m/\.$/) {
			print "Warning: Description ends with \".\". ($filename)\n";
			$looks_good = 0;
		}
		if ($value =~ m/^\[/) {
			print "Warning: Descriptions beginning with \"[\" are only for special types of packages. ($filename)\n";
			$looks_good = 0;
		}
	}
	
	$expand = { 'n' => $pkgname,
				'v' => $pkgversion,
				'r' => $pkgrevision,
				'f' => $pkgfullname,
				'p' => $basepath, 'P' => $basepath,
				'd' => $pkgdestdir,
				'i' => $pkgdestdir.$basepath,
				'a' => $pkgpatchpath,
				'b' => '.',
				'm' => $config->param('Architecture'),
				%{$expand},
				'ni' => $pkginvarname,
				'Ni' => $pkginvarname
	};

	if (exists $properties->{patchfile}) {
		if ($pkgpatchpath eq "") {
			$expand->{patchfile} = $properties->{patchfile};
		} else {
			$expand->{patchfile} = $pkgpatchpath . '/' . $properties->{patchfile};
		}
	}

	# Verify the patch file(s) exist and check some things
	@patchfiles = ();
	# anything in PatchScript that looks like a patch file name
	# (i.e., strings matching the glob %a/*.patch)
	$value = $properties->{patchscript};
	if ($value) {
		@patchfiles = ($value =~ /\%a\/.*?\.patch/g);
		# strip directory if info is simple filename (in $PWD)
		map {s/\%a\///} @patchfiles unless $pkgpatchpath;
		if (@patchfiles and exists $properties->{patchfile}) {
			print "Error: Cannot use %a if using PatchFile. ($filename)\n";
			$looks_good = 0;
		}			
	}

	# the contents if Patch (if any)
	$value = $properties->{patch};
	if ($value) {
		# add directory if info is not simple filename (not in $PWD)
		$value = "\%a/" .$value if $pkgpatchpath;
		unshift @patchfiles, $value;
	}

	# the contents if PatchFile (if any)
	if (exists $properties->{expand}->{patchfile}) {
		unshift @patchfiles, '%{patchfile}';
	}

	# now check each one in turn
	foreach $value (@patchfiles) {
		$value = &expand_percent($value, $expand, $filename.' Patch');
		unless (-f $value) {
			print "Error: can't find patchfile \"$value\"\n";
			$looks_good = 0;
		}
		else {
			# Check patch file
			open(INPUT, "<$value") or die "Couldn't read $value: $!\n";
			my $patch_file_content = <INPUT>;
			close INPUT or die "Couldn't read $value: $!\n";
			# Check for empty patch file
			if (!$patch_file_content) {
				print "Warning: Patch file is empty. ($value)\n";
				$looks_good = 0;
			}
			# Check for line endings of patch file
			elsif ($patch_file_content =~ m/\r\n/s) {
				print "Error: Patch file has DOS line endings. ($value)\n";
				$looks_good = 0;
			}
			elsif ($patch_file_content =~ m/\r/s) {
				print "Error: Patch file has Mac line endings. ($value)\n";
				$looks_good = 0;
			}
			# Check for hardcoded /sw.
			open(INPUT, "<$value") or die "Couldn't read $value: $!\n";
			while (defined($patch_file_content=<INPUT>)) {
				# only check lines being added (and skip diff header line)
				next unless $patch_file_content =~ /^\+(?!\+\+ )/;
				if ($patch_file_content =~ /\/sw([\s\/]|\Z)/) {
					print "Warning: Patch file appears to contain a hardcoded /sw. ($value)\n";
					$looks_good = 0;
					last;
				}
			}
			close INPUT or die "Couldn't read $value: $!\n";
		}
	}

	# if we are using new PatchFile field, check some things about it
	if (exists $properties->{patchfile}) {

		# must declare BuildDepends on a fink that supports it
		my $has_fink_bdep = 0;
		$value = &pkglist2lol($properties->{builddepends});
		foreach (@$value) {
			foreach my $atom (@$_) {
				$atom =~ s/^\(.*?\)\s*//;
				next unless $atom =~ /^fink\s*\(\s*(>>|>=)\s*(.*?)\)\s*$/;
				$has_fink_bdep = 1 if version_cmp($2, '>=', '0.24.12');
			}
		}
		if (!$has_fink_bdep) {
			print "Error: Use of PatchFile requires declaring a BuildDepends on \"fink (>= 0.24.99)\" or higher. ($filename)\n";
			$looks_good = 0;
		}

		# can't mix old and new patching styles
		if (exists $properties->{patch}) {
			print "Error: Cannot use both Patch and PatchFile. ($filename)\n";
			$looks_good = 0;
		}

		# must have PatchFile-MD5 field that matches file's checksum
		if (defined ($value = $properties->{'patchfile-md5'})) {
			my $file = &expand_percent('%{patchfile}', $expand, $filename.' PatchFile');
			my $file_md5 = file_MD5_checksum($file);
			if ($value ne $file_md5) {
				print "Error: PatchFile-MD5 does not match PatchFile checksum. ($filename)\n\tActual: $file_md5\n\tExpected: $value\n";
				$looks_good = 0;
			}
		} else {
			print "Error: No PatchFile-MD5 given for PatchFile. ($filename)\n";
			$looks_good = 0;
		}

		# must actually be used
		if (defined ($value = $properties->{'patchscript'})) {
			if ($value !~ /%{(PatchFile|default_script)}/) {
				print "Warning: PatchFile does not appear to be used in PatchScript. ($filename)\n";
				$looks_good = 0;
			}
		}

	} elsif (exists $properties->{'patchfile-md5'}) {
		# sanity check
		print "Warning: No PatchFile given for PatchFile-MD5. ($filename)\n";
		$looks_good = 0;
	}
	
	# Check for Type: dummy, only allowed for internal use
	if (exists $type_hash->{dummy}) {
		print "Error: Package has type \"dummy\". ($filename)\n";
		$looks_good = 0;
	}
	
	# instantiate the PkgVersion objects
	my @pv = Fink::PkgVersion->pkgversions_from_info_file($full_filename, no_exclusions => 1);

	if (@pv > 1) {
		my %names;
		foreach (map {$_->get_name()} @pv) {
			if ($names{$_}++) {
				print "Error: Duplicate declaration of package \"$_\". ($filename)\n";
				$looks_good = 0;
			}
		}
	}

	if ($looks_good and $config->verbosity_level() >= 3) {
		print "Package looks good!\n";
	}

	return $looks_good;
}

# checks that are common to a parent and a splitoff package of a .info file
# returns boolean of whether everything is okay
sub validate_info_component {
	my $properties = shift;      # hashref (will not be altered)
	my $splitoff_field = shift;  # "splitoffN", or null or undef in parent
	my $filename = shift;
	my $info_level = shift;

	my (@pkg_required_fields, %pkg_valid_fields);

	my $is_splitoff = 0;
	$splitoff_field = "" unless defined $splitoff_field;
	if (defined $splitoff_field && length $splitoff_field) {
		$is_splitoff = 1;
		$splitoff_field = sprintf ' of "%s"', $splitoff_field;
		@pkg_required_fields = @splitoff_required_fields;
		%pkg_valid_fields = %splitoff_valid_fields;
	} else {
		@pkg_required_fields = @required_fields;
		%pkg_valid_fields = %valid_fields;
	}

	my $value;
	my $looks_good = 1;

	### field-specific checks

	# Verify that all required fields are present
	foreach my $field (@pkg_required_fields) {
		unless (exists $properties->{$field}) {
			print "Error: Required field \"$field\"$splitoff_field missing. ($filename)\n";
			$looks_good = 0;
		}
	}

	# dpkg install-time script stuff
	foreach my $field (qw/preinstscript postinstscript prermscript postrmscript/) {
		next unless defined ($value = $properties->{$field});

		# A #! line is worthless
		if ($value =~ /^\s*\#!\s*(.*)/) {
			my $real_interp = '/bin/sh';
			if ($1 eq $real_interp) {
				print 'Warning: Useless use of explicit interpreter';
			} else {
				print "Error: ignoring explicit interpreter (will use \"$real_interp\" instead)";
			}
			print " in \"$field\"$splitoff_field. ($filename)\n";
			$looks_good = 0;
		}

		# must operate on %p not %i
		if ($value =~ /\%i\//) {
			print "Error: Use of \%i in field \"$field\"$splitoff_field. ($filename)\n";
			$looks_good = 0;
		}
	}

	### checks that apply to all fields

	foreach my $field (keys %$properties) {
		next if $field =~ /^splitoff/;   # we don't do recursive stuff here
		$value = $properties->{$field};

		# Check for hardcoded /sw
		if ($check_hardcode_fields{$field} and $value =~ /\/sw([\s\/]|\Z)/) {
			print "Warning: Field \"$field\"$splitoff_field appears to contain a hardcoded /sw. ($filename)\n";
			$looks_good = 0;
		}

		# Check for %p/src
		if ($value =~ /\%p\\?\/src\\?\//) {
			print "Warning: Field \"$field\"$splitoff_field appears to contain \%p/src. ($filename)\n";
			$looks_good = 0;
		}

		# warn for non-plain-text chars
		if ($value =~ /[^[:ascii:]]/) {
			print "Warning: \"$field\"$splitoff_field contains non-standard characters. ($filename)\n";
			$looks_good = 0;
		}

		# Warn if field is unknown
		unless ($pkg_valid_fields{$field}) {
			unless (!$is_splitoff and
					( $field =~ m/^source([2-9]|[1-9]\d+)(|extractdir|rename|-md5|-checksum)$/
					  or $field =~ m/^tar([2-9]|[1-9]\d+)filesrename$/
					  ) ) {
				print "Warning: Field \"$field\"$splitoff_field is unknown. ($filename)\n";
				$looks_good = 0;
			}
		}

		# check dpkg Depends-style field syntax
		# Architecture is a special case of this same syntax
		if ($pkglist_fields{$field}) {
			(my $pkglist = $value) =~ tr/\n//d; # convert to single line
			if ($info_level >= 3) {
				$pkglist =~ s/#.*$//mg;
				$pkglist =~ s/,\s*$//;
			} else {
				if ($pkglist =~ /#/) {
					print "Warning: bad character \"#\" in \"$field\"$splitoff_field. ($filename)\n";
					$looks_good = 0;
				}
				if ($pkglist =~ /,\s*$/) {
					print "Warning: trailing \",\" in \"$field\"$splitoff_field. ($filename)\n";
					$looks_good = 0;
				}
			}
			foreach my $atom (split /[,|]/, $pkglist) {
				$atom =~ s/\A\s*//;
				$atom =~ s/\s*\Z//;
				# each atom must be  '(optional cond) pkg (optional vers)'
				unless ($atom =~ /\A(?:\(([^()]*)\)|)\s*([^()\s]+)\s*(?:\(([^()]+)\)|)\Z/) {
					print "Warning: invalid dependency \"$atom\" in \"$field\"$splitoff_field. ($filename)\n";
					$looks_good = 0;
				}
				my ($cond, $pkgname, $vers) = ($1, $2, $3);
				# no logical AND (OR would be split() and give broken atoms)
				if (defined $cond and $cond =~ /&/) {
					print "Warning: invalid dependency \"$atom\" in \"$field\"$splitoff_field. ($filename)\n";
				}
				if ($field eq 'architecture') {
					$pkgname .= " ($vers)" if defined $vers;
					if (!exists $allowed_arch_values{lc $pkgname}) {
						print "Warning: Unknown value \"$pkgname\" in Architecture field. ($filename)\n";
						$looks_good = 0;
					}
				} elsif (my($verspec) = $atom =~ /.*\(\s*(.*?)\s*\)\Z/) {
					# yes, we *do* need the seemingly useless initial .* there
					if (my($ver) = $verspec =~ /^(?:<<|<=|=|!=|>=|>>)\s*(.*)/) {
						unless ($ver =~ /\A\S+\Z/) {
							print "Warning: invalid version in \"$atom\" in \"$field\"$splitoff_field. ($filename)\n";
							$looks_good = 0;
						}
					} else {
						print "Warning: invalid version comparator in \"$atom\" in \"$field\"$splitoff_field. ($filename)\n";
						$looks_good = 0;
					}
				}
			}
		}
	}

	# Provides is not versionable
	$value = $properties->{provides};
	if (defined $value) {
		if ($value =~ /\)\s*(,|\Z)/) {
			print "Warning: Not allowed to specify version information in \"Provides\"$splitoff_field. ($filename)\n";
			$looks_good = 0;
		}
	}

	# check syntax of each line of Shlibs field
	$value = $properties->{shlibs};
	if (defined $value) {
		my @shlibs = split /\n/, $value;
		my %shlibs;
		foreach (@shlibs) {
			next unless /\S/;
			my @shlibs_parts;
			if (scalar(@shlibs_parts = split ' ', $_, 3) != 3) {
				print "Warning: Malformed line in field \"shlibs\"$splitoff_field. ($filename)\n  $_\n";
				$looks_good = 0;
				next;
			}
			if (not $shlibs_parts[0] =~ /^(\%p)?\//) {
				print "Warning: Pathname \"$shlibs_parts[0]\" is not absolute and is not in \%p in field \"shlibs\"$splitoff_field. ($filename)\n";
				$looks_good = 0;
			}
			if ($shlibs{$shlibs_parts[0]}++) {
				print "Warning: File \"$shlibs_parts[0]\" is listed more than once in field \"shlibs\"$splitoff_field. ($filename)\n";
				$looks_good = 0;
			}
			if (not $shlibs_parts[1] =~ /^\d+\.\d+\.\d+$/) {
				print "Warning: Malformed compatibility_version for \"$shlibs_parts[0]\" in field \"shlibs\"$splitoff_field. ($filename)\n";
				$looks_good = 0;
			}
			my @shlib_deps = split /\s*\|\s*/, $shlibs_parts[2], -1;
			foreach (@shlib_deps) {
				if (not /^[a-z%]\S*\s+\(>=\s*(\S+-\S+)\)$/) {
					print "Warning: Malformed dependency \"$_\" for \"$shlibs_parts[0]\" in field \"shlibs\"$splitoff_field. ($filename)\n";
					$looks_good = 0;
					next;
				}
				my $shlib_dep_vers = $1;
				if ($shlib_dep_vers =~ /\%/) {
					print "Warning: Non-hardcoded version in dependency \"$_\" for \"$shlibs_parts[0]\" in field \"shlibs\"$splitoff_field. ($filename)\n";
					$looks_good = 0;
					next;
				}
			}
		}
	}

	# Explicit interpretters in fink package building script should be
	# called with -ev or -ex so that they abort if any command fails
	foreach my $field (qw/patchscript compilescript installscript/) {
		next unless defined ($value = $properties->{$field});
		if ($value =~ /^\s*\#!\s*(\S+)([^\n]*)/) {
			my ($shell, $args) = ($1, $2);
			$shell = basename $shell;
			if (grep {$shell eq $_} qw/bash csh ksh sh tcsh zsh/) {
				unless ($args =~ /-\S*e/) {
					print "Warning: -e flag not passed to explicit interpreter in \"$field\"$splitoff_field. ($filename)\n";
					$looks_good = 0;
				}
				if (Fink::Config::get_option("Pedantic") and $args !~ /-\S*[vx]/) {
					print "Warning: -v or -x flag not passed to explicit interpreter in \"$field\"$splitoff_field. ($filename)\n";
					$looks_good = 0;
				}
			}
		}
	}

	return $looks_good;
}

#
# Public function to validate a .deb, given its .deb filename
# returns boolean of whether everything is okay
#
sub validate_dpkg_file {
	my $dpkg_filename = shift;
	my $val_prefix = shift;

	# create a dummy packaging directory (%d)
	# NB: File::Temp::tempdir CLEANUP breaks if we fork!
	my $destdir = tempdir('fink-validate-deb-unpack.XXXXXXXXXX', TMPDIR => 1 );

	print "Validating .deb file $dpkg_filename...\n";
	
	# unpack the actual filesystem
	if (system('dpkg', '-x', $dpkg_filename, $destdir)) {
		print "Error: couldn't unpack .deb\n";
		return 0;
	}

	# unpack the dpkg control module
	if (system('dpkg', '-e', $dpkg_filename, "$destdir/DEBIAN")) {
		print "Error: couldn't unpack .deb control\n";
		return 0;
	}

	# we now have the equivalent of %d after phase_install for the family
	my $looks_good = &_validate_dpkg($destdir, $val_prefix);

	# clean up...need better implementation?
	#   File::Temp::tempdir(CLEANUP) only runs when whole perl program exits
	#   Fink::Command::rm_rf leaves behind things that aren't chmod +w
	rmtree [$destdir], 0, 0;

	return $looks_good;
}

#
# Public function to validate a .deb, given a dir that contains its
# unpacked or (pre-packed) contents (both filesystem and control)
# returns boolean of whether everything is okay
#
sub validate_dpkg_unpacked {
	my $destdir = shift;
	my $val_prefix = shift;

	print "Validating .deb dir $destdir...\n";
	
	my $looks_good = &_validate_dpkg($destdir, $val_prefix);

	return $looks_good;
}

#
# Private function that performs the actual .deb validation checks
# Check a given unpacked .deb file for standards compliance
# returns boolean of whether everything is okay
#
# - usage of non-recommended directories (/sw/src, /sw/man, /sw/info, /sw/doc, /sw/libexec, /sw/lib/locale)
# - usage of other non-standard subdirs 
# - storage of a .bundle inside /sw/lib/perl5/darwin or /sw/lib/perl5/auto
# - Emacs packages
#     - installation of .elc files
#     - (it's now OK to install files directly into
#        /sw/share/emacs/site-lisp, so we no longer check for this)
# - BuildDependsOnly: if package stores files in /sw/include, it should
#     declare BuildDependsOnly true
# - Check presence and execute-flag on executable specified in daemonicfile
# - If a package contains a daemonicfile, it should Depends:daemonic
# - Check for symptoms of running update-scrollkeeper during package building
# - If a package has .omf sources, it should call update-scrollkeeper during Post(Inst,Rm}Script
# - If a package Post{Inst,Rm}Script calls update-scrollkeeper, it should Depends:scrollkeeper
# - Only gettext should should have charset.alias
# - If a package *Script uses debconf, it should Depends:debconf
#   (TODO: should be in preinst not postinst, should be PreDepends not Depends)
# - if a pkg is a -pmXXX but installs files that are not in a XXX-specific path
# - Catch common error relating to usage of -framework flag in .pc file
# - Look for symptoms of missing InfoDocs field in .info
# - Look for packages that contain no files
#
# - any other ideas?
#
sub _validate_dpkg {
	my $destdir = shift;  # %d, or its moral equivalent
	my $val_prefix = shift;

	my $basepath;   # %p
	my $buildpath;  # BuildPath from fink.conf
	# determine the base path
	if (defined $val_prefix) {
		$basepath = $val_prefix;
		$buildpath = "$basepath/src/fink.build";
	} else {
		$basepath = $config->param_default("basepath", "/sw");
		$buildpath = $config->param_default("buildpath", "$basepath/src/fink.build");
	}

	# these are used in a regex and are automatically prepended with ^
	# make sure to protect regex metachars!
	my @bad_dirs = ("$basepath/src/", "$basepath/man/", "$basepath/info/", "$basepath/doc/", "$basepath/libexec/", "$basepath/lib/locale/", ".*/CVS/", ".*/RCS/");
	my @good_dirs = ( map "$basepath/$_", qw/ bin sbin include lib share var etc src Applications X11 / );

	my @found_bad_dir;
	my $installed_headers = 0;
	my $installed_dylibs = 0;

	# the whole control module is loaded and pre-precessed before any actual validation
	my $deb_control;        # key:value of all %d/DEBIAN/control fields
	my $control_processed;  # parsed data from $deb_control
	my $dpkg_script;        # key={pre,post}{inst,rm}, value=ref to array of file's lines

	my $looks_good = 1;
	# read some fields from the control file
	if (open my $control, '<', "$destdir/DEBIAN/control") {
		while (<$control>) {
			chomp;
			if (/^([0-9A-Za-z_.\-]+):\s*(.*?)\s*$/) {
				$deb_control->{lc $1} = $2;
			} elsif (/^\s/) {
				# we don't care about continuation lines
				# {description} will only be Description not other Desc*
			} else {
				print "Error: malformed line in control file. Offending line:\n$_\n";
				$looks_good = 0;
			}
		}
		close $control;
	} else {
		print "Error: could not read control file!\n";
		$looks_good = 0;
	}

	# read some control script files
	foreach my $scriptfile (qw/ preinst postinst prerm postrm /) {
		# values for all normal scriptfiles are always valid array refs
		$dpkg_script->{$scriptfile} = [];
		my $filename = "$destdir/DEBIAN/$scriptfile";
		if (-f $filename) {
			if (open my $script, '<', $filename) {
				# slurp an array of lines
				$dpkg_script->{$scriptfile} = [<$script>];
				close $script;
			} else {
				print "Error: could not read dpkg script $scriptfile: $!\n";
				$looks_good = 0;
			}
		}
	}

	# create hash where keys are names of packages listed in Depends
	$control_processed->{depends_pkgs} = {
		map { /\s*([^ \(]*)/, undef } split /[|,]/, $deb_control->{depends}
	};

	# prepare to check that -pmXXX and -pyXX packages only contain
	# file in language-versioned locations: define a regex for the
	# language-versioned path component
	my $langver_re;
	if ($deb_control->{package} =~ /-(pm|py)(\d+)$/) {
		$langver_re = $2;
		if ($1 eq 'pm') {
			# perl language is major.minor.teeny
			if ($langver_re =~ /^(\d)(\d)(\d)$/) {
				# -pmXYZ is perlX.Y.Z
				$langver_re = "(?:$langver_re|$1.$2.$3)";
			} elsif ($langver_re =~ /^(\d)(\d)(\d)(\d)$/) {
				# -pmWXYZ is perlW.X.YZ or perlW.XY.Z
				$langver_re = "(?:$langver_re|$1.$2.$3$4|$1.$2$3.$4)";
			}
		} else {
			# python language is major.minor
			# numbers are all "small" (one-digit)
			$langver_re =~ /^(\d)(\d)$/;
			# -pyXY is pythonX.Y
			$langver_re = "(?:$langver_re|$1.$2)";
		}
	}

	# prepare regexes to check for use of %b, and %d or %D
	my ($pkgbuilddir, $pkginstdirs);
	{
		my $vers = $deb_control->{version};
		$vers = $1 if $vers =~ /:(.*)/;  # epoch not used in %b or %d
		
		$pkgbuilddir = sprintf '%s/%s-%s/', map { qr{\Q$_\E} } $buildpath, $deb_control->{source}, $vers;  # %b
		$pkginstdirs = sprintf '%s/root-(?:%s|%s)-%s/', map { qr{\Q$_\E} } $buildpath, $deb_control->{source}, $deb_control->{package}, $vers;  # %d or %D
	}


	my $install_info_called =
		grep /install-info.*--info(-|)dir=$basepath\/share\/info /, @{$dpkg_script->{postinst}} &&
		grep /install-info.*--info(-|)dir=$basepath\/share\/info /, @{$dpkg_script->{postinst}};

	# during File::Find loop, we stack all error msgs
	my $msgs = [ [], {} ];  # poor-man's Tie::IxHash

	my $dpkg_file_count = 0;

	# this sub gets called by File::Find::find for each file in the .deb
	# expects cwd==%d and File::Find::find to be called with no_chdir=1
	my $perform_dpkg_file_checks = sub {
		# the full path/filename as it will be installed at its real location
		my($filename) = $File::Find::name =~ /^\.(.*)/;
		return if not length $filename;              # skip top-level directory
		$filename .= '/' if -d $File::Find::name;    # add trailing slash to dirnames
		return if $filename =~ /^\/DEBIAN/;          # skip dpkg control module
		return if "$basepath/" =~ /^\Q$filename\E/;  # skip parent components of basepath hierarchy

		# check for files in well-known bad locations
		if (not $filename =~ /^$basepath\//) {
			if (($filename =~ /^\/etc/) || ($filename =~ /^\/tmp/) || ($filename =~ /^\/var/)) {
				&stack_msg($msgs, "Overwriting essential system symlink pointing to /private$filename", $filename);
			} elsif ($filename =~ /^\/mach/) {
				&stack_msg($msgs, "Overwriting essential system symlink pointing to /mach.sym", $filename);
			} elsif ($deb_control->{package} !~ /^(xfree86|xorg)/) {
				&stack_msg($msgs, "File installed outside of $basepath", $filename);
			} else {
				if (not (($filename =~ /^\/Applications\/XDarwin.app/) || ($filename =~ /^\/usr\/X11R6/) || ($filename =~ /^\/private\/etc\/fonts/) )) {
					return if (($filename eq "/Applications/") || ($filename eq "/private/") || ($filename eq "/private/etc/") || ($filename eq "/usr/"));
					&stack_msg($msgs, "File installed outside of $basepath, /Applications/XDarwin.app, /private/etc/fonts, and /usr/X11R6", $filename);
				}
			}
		} elsif ($filename ne "$basepath/src/" and @found_bad_dir = grep { $filename =~ /^$_/ } @bad_dirs) {
			# Directories from this list are not allowed to exist in the .deb.
			# The only exception is $basepath/src which may exist but must be empty
			&stack_msg($msgs, "File installed into deprecated directory $found_bad_dir[0]", $filename);
		} elsif (not grep { $filename =~ /^$_/ } @good_dirs) {
			# Directories from this list are the top-level dirs that may exist in the .deb.
			&stack_msg($msgs, "File installed outside of allowable subdirectories of $basepath", $filename);
		}

		# check for compiled-perl modules in unversioned place
		if ($filename =~ /^$basepath\/lib\/perl5\/(auto|darwin)\/.*\.bundle/) {
			&stack_msg($msgs, "Apparent perl XS module installed directly into $basepath/lib/perl5 instead of a versioned subdirectory.", $filename);
		}

		# check for compiled emacs libs
		if ($filename =~ /\.elc$/ &&
			$deb_control->{package} !~ /^emacs\d\d(|-.*)$/ &&
			$deb_control->{package} !~ /^xemacs(|-.*)$/
		   ) {
			&stack_msg($msgs, "Compiled .elc file installed. Package should install .el files, and provide a /sw/lib/emacsen-common/packages/install/<package> script that byte compiles them for each installed Emacs flavour.", $filename);
		}

		# track whether BuildDependsOnly will be needed
		if ($filename =~/^$basepath\/include\// && !-d $File::Find::name) {
			$installed_headers = 1;
		}
		if ($filename =~/\.dylib$/) {
			$installed_dylibs = 1;
		}

		# make sure scrollkeeper is being used according to its documentation
		if ( $filename =~/^$basepath\/share\/omf\/.*\.omf$/ ) {
			foreach (qw/ postinst postrm /) {
				next if $_ eq "postrm" && $deb_control->{package} eq "scrollkeeper"; # circular dep
				if (not grep { /^\s*scrollkeeper-update/ } @{$dpkg_script->{$_}}) {
					&stack_msg($msgs, "Scrollkeeper source file found, but scrollkeeper-update not called in $_. See scrollkeeper package docs, starting with 'fink info scrollkeeper', for information.", $filename);
				}
			}
		}

		# check for presence of compiled scrollkeeper
		if ($filename =~ /^$basepath\/var\/scrollkeeper\/.+/) {
			&stack_msg($msgs, "Runtime scrollkeeper file installed, which usually results from calling scrollkeeper-update during CompileScript or InstallScript. See the\nscrollkeeper package docs, starting with 'fink info scrollkeeper', for information on the correct use of that utility.", $filename);
		}

		# special checks for daemonic files
		if ($filename =~ /^$basepath\/etc\/daemons\/.+/) {
			if (not exists $control_processed->{depends_pkgs}->{daemonic}) {
				&stack_msg($msgs, "Package contains a DaemonicFile but does not depend on the package \"daemonic\"", $filename);
			}
			if (open my $daemonicfile, '<', $File::Find::name) {
				while (<$daemonicfile>) {
					if (/^\s*<executable.*?>(\S+)<\/executable>\s*$/) {
						my $executable = $1;
						if (-f ".$executable") {
							unless (-x ".$executable") {
								&stack_msg($msgs, "DaemonicFile executable in this .deb does not have execute permissions.", $executable);
							}
						} else {
							if (!-e $executable) {
								&stack_msg($msgs, "DaemonicFile executable \"$executable\" does not exist.");
								$looks_good = 0;
							} elsif (!-x $executable) {
								&stack_msg($msgs, "DaemonicFile executable \"$executable\" does not have execute permissions.");
							}
						}
					}
				}
				close $daemonicfile;
			} else {
				&stack_msg($msgs, "Couldn't read DaemonicFile $File::Find::name: $!");
			}
		}

		# check that libtool files don't link to temp locations
		if ($filename =~/\.la$/) {
			if (open my $la_file, '<', $File::Find::name) {
				while (<$la_file>) {
					if (/$pkgbuilddir/) {
						&stack_msg($msgs, "Libtool file points to fink build dir.", $filename);
						last;
					} elsif (/$pkginstdirs/) {
						&stack_msg($msgs, "Libtool file points to fink install dir.", $filename);
						last;
					}
				}
				close $la_file;
			} else {
				&stack_msg($msgs, "Couldn't read libtool file \"$filename\": $!");
			}
		}

		# check that compiled python modules files don't self-identify using temp locations
		if ($filename =~/\.py[co]$/) {
			if (open my $py_file, "strings $File::Find::name |") {
				while (<$py_file>) {
					if (/$pkgbuilddir/) {
						&stack_msg($msgs, "Compiled python module points to fink build dir.", $filename);
						last;
					} elsif (/$pkginstdirs/) {
						&stack_msg($msgs, "Compiled python module points to fink install dir.", $filename);
						last;
					}
				}
				close $py_file;
			} else {
				&stack_msg($msgs, "Couldn't read compiled python module file \"$filename\": $!");
			}
		}

		# check for privately installed copies of files provided by gettext
		if ($filename eq "$basepath/lib/charset.alias" and $deb_control->{package} !~ /^libgettext\d*/) {
			&stack_msg($msgs, "File should only exist in the \"libgettextN\" packages.", $filename);
		} elsif ($filename eq "$basepath/share/locale/charset.alias") {
			# this seems to be a common bug in pkgs using gettext
			&stack_msg($msgs, "Gettext file seems misplaced.", $filename);
		}

		# check for files in a language-versioned package whose path
		# is not language-versioned (goal: language-versioned modules
		# are orthogonal and do not conflict with each other)
		if (defined $langver_re and $filename !~ /$langver_re/ and !-d $File::Find::name) {
			&stack_msg($msgs, "File in a language-versioned package is neither versioned nor in a versioned directory.", $filename);
		}

		# Check for common programmer mistakes relating to passing -framework flags in pkg-config files
		if ($filename =~ /\.pc$/) {
			if (open my $pc_file, '<', $File::Find::name) {
				while (<$pc_file>) {
					chomp;
					if (/\s((?:-W.,|)-framework)[^,]/) {
						&stack_msg($msgs, "The $1 flag may get munged by pkg-config. See the gcc manpage for information about passing options to flags for specific compiler passes.", $filename, $_);
					}
				}
				close $pc_file;
			} else {
				&stack_msg($msgs, "Couldn't read pkg-config file \"$filename\": $!");
			}
		}

		# Check that if we have texinfo files, InfoDocs was used, and
		# that there is no table-of-contents file present (because it
		# is created by InfoDocs in PostInst)
		if ($filename =~ /^$basepath\/share\/info\/(.+)/) {
			my $infofile = $1;
			if ($infofile eq 'dir') {
				&stack_msg($msgs, "The texinfo table of contents file \"$filename\" must not be installed directly as part of the .deb");
			} elsif (not $install_info_called) {
				&stack_msg($msgs, "Texinfo file found but no InfoDocs field in package description.", $filename);
			}
		}

		# count number of files and links ("real things, not dirs") in %i
		lstat $File::Find::name;
		$dpkg_file_count++ if -f _ || -l _;

	};  # end of CODE ref block

	# check each file in the %d hierarchy according to the above-defined sub
	{
		my $curdir = getcwd();
		chdir $destdir;
		find ({wanted=>$perform_dpkg_file_checks, no_chdir=>1}, '.');
		chdir $curdir;
	}

	# dpkg hates packages that contain no files
	&stack_msg($msgs, "Package contains no files.") if not $dpkg_file_count;
	
	# handle messages generated during the File::Find loop
	{
		# when we switch to Tie::IxHash, we won't need to know the internal details of $msgs
		my @msgs_ordered = @{$msgs->[0]};
		my %msgs_details = %{$msgs->[1]};
		if (@msgs_ordered) {
			$looks_good = 0;  # we have errors in the stack!
			foreach my $msg (@msgs_ordered) {
				print "Error: $msg\n";
				foreach (@{$msgs_details{$msg}}) {
					print "\tOffending file: ", $_->[0], "\n" if defined $_->[0];
					print "\tOffending line: ", $_->[1], "\n" if defined $_->[1];
				}
			}
		}
	}

	# handle BuildDependsOnly flags set during file-by-file checks
	# Note that if the .deb was compiled with an old version of fink which
	# does not record the BuildDependsOnly field, or with an old version
	# which did not use the "Undefined" value for the BuildDependsOnly field,
	# the warning is not issued
	if ($installed_headers and $installed_dylibs) {
		if (!exists $deb_control->{builddependsonly} or $deb_control->{builddependsonly} =~ /Undefined/) {
			print "Error: Headers installed in $basepath/include, as well as a dylib, but package does not declare BuildDependsOnly to be true (or false)\n";
			$looks_good = 0;
		}
	}

	# make sure we have Depends:scrollkeeper if scrollkeeper is called in dpkg scripts
	foreach (qw/ preinst postinst prerm postrm /) {
		next if $deb_control->{package} eq "scrollkeeper"; # circular dep
		if (grep { /^\s*scrollkeeper-update/ } @{$dpkg_script->{$_}} and not exists $control_processed->{depends_pkgs}->{scrollkeeper}) {
			print "Error: Calling scrollkeeper-update in $_ requires \"Depends:scrollkeeper\"\n";
			$looks_good = 0;
		}
	}

	# scrollkeeper-update should be called from PostInstScript and PostRmScript
	foreach (qw/ preinst prerm /) {
		if (grep { /^\s*scrollkeeper-update/ } @{$dpkg_script->{$_}}) {
			print "Warning: scrollkeeper-update in $_ is a no-op\nSee scrollkeeper package docs, starting with 'fink info scrollkeeper', for information.\n";
			$looks_good = 0;
		}
	}

	# check debconf usage
	if ($deb_control->{package} ne "debconf" and !exists $control_processed->{depends_pkgs}->{debconf}) {
		foreach (qw/ preinst postinst prerm postrm /) {
			if (grep { /debconf/i } @{$dpkg_script->{$_}}) {
				print "Error: Package appears to use debconf in $_ but does not depend on the package \"debconf\"\n";
				$looks_good = 0;
			}
		}
	}

	if ($looks_good and $config->verbosity_level() >= 3) {
		print "Package looks good!\n";
	}

	return $looks_good;
}


# implements somehting like Tie::IxHash STORE, but each value-set is
# pushed onto list instead of replacing the existing value for the key
sub stack_msg {
	my $queue = shift;     # ref to list: [\@msgs, \%msgs]
	# @msgs lists order of first occurrence of each unique $message
	# %msgs is keyed by $message, value is ref to list of additional details
	my $message = shift;   # the message to store
	my @details = @_;      # additional details about this instance of the msg

	push @{$queue->[0]}, $message unless exists $queue->[1]->{$message};
	push @{$queue->[1]->{$message}}, \@details;
}


### EOF
1;
# vim: ts=4 sw=4 noet
