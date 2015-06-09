# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Validation module
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2015 The Fink Package Manager Team
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

package Fink::Validation;

use Fink::Services qw(&read_properties &read_properties_var &expand_percent &expand_percent2 &file_MD5_checksum &pkglist2lol &version_cmp);
use Fink::Config qw($config);
use Fink::PkgVersion;
use Cwd qw(getcwd);
use File::Find qw(find);
use File::Path qw(rmtree);
use File::Temp qw(tempdir);
use File::Basename qw(basename dirname);

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
		ld ldflags library_path libs
		macosx_deployment_target make mflags makeflags path
	);
# FIXME: (No)SetPATH is undocumented
# FIXME: On the other hand, (No)SetJAVA_HOME *is* documented (but unused)

# Required fields.
our @required_fields = map {lc $_}
	qw(Package Version Revision Maintainer);
our @splitoff_required_fields = map {lc $_}
	qw(Package);

# All fields that expect a boolean value
our %boolean_fields = map {$_, 1}
	(
		qw(builddependsonly essential nosourcedirectory updateconfigguess updatelibtool updatepod noperltests usemaxbuildjobs buildasnobody),
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

# Allowed values for the license field: note that there are now "new-style"
# GPL license fields which follow the string "GPL" with either "2", "3", or
# "23", optionally followed by "+".  Rather than list all the possibilities
# here, we use some regexp magic later on.
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
	 'x86_64',
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
		 'distribution',
		 'defaultscript',
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
		 'usemaxbuildjobs',
		 'buildasnobody',
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
		 'descport',
		 'infotest',
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
		 'runtimedepends',
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
		 'appbundles',
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
	 'RuntimeDepends',
	 'Conflicts',
	 'BuildConflicts',
	 'TestDepends',
	 'TestConflicts',
	 'Provides',
	 'Suggests',
	 'Recommends',
	 'Enhances',
	 'Replaces',
	 # 'Architecture' is not a "Depends"-style list, but its syntax is
	 # like a package-list, so piggy-back on those fields' parser
	 'Architecture',
	);

# Some Types may have implicit TestScript, otherwise that would be required.
our @infotest_required_fields = map {lc $_} ();

# Extra fields valid inside InfoTest
our %infotest_valid_fields = map {lc $_, 1}
	(
	 'testdepends',
	 'testconflicts',
	 'testconfigureparams',
	 'testscript',
	 'testsuitesize',
	 'testsource',
	 'testsourceextractdir',
	 'testsourcerename',
	 'testsource-md5',
	 'testsource-checksum',
	 'testtarfilesrename',
	);

# Allowed values of the TestSuiteSize field
our %allowed_testsuitesize_values = map {lc $_, 1}
	(
	 'small',
	 'medium',
	 'large',
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
#	- correct format of Shlibs: (including misuse of %v-%r, and including
#     the optional new "library architecture" entry which may be 32, 64, or
#     32-64)
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
	my ($properties, $info_level, $test_properties);
	my ($pkgname, $pkginvarname, $pkgversion, $pkgrevision, $pkgepoch, $pkgfullname, $pkgdestdir, $pkgpatchpath);
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
	$test_properties = &read_properties_var(
		"InfoTest of $filename",
		$properties->{infotest}, {remove_space => 1}) if $properties->{infotest};

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

	# make sure have InfoN (N>=4) if using Info4 features
	if ($info_level < 4) {
		# fink-0.26.1 can't even index if unknown %-exp in ConfigureParams field!
		if (exists $properties->{configureparams}) {
			if ($properties->{configureparams} =~ /\%lib/) {
				print "Error: Use of %lib expansion in ConfigureParams field requires InfoN level 4 or higher. ($filename)\n";
				return 0;
			}
		}
	}

	# figure out %-exp map for canonical Type representation
	if (defined ($type = $properties->{type})) {
		foreach my $type_atom (split(/,/, $type)) {
			my($type, $subtype);

			if ($type_atom =~ /^\s*(\S+)\s*\(.*\)\s*$/) {
				# have paren subtype, so use blank
				($type, $subtype) = ($1, '');
			} elsif ($type_atom =~ /^\s*(\S+)\s+(\S+)\s*$/) {
				# have single subtype, so use it
				($type, $subtype) = ($1, $2);
			} elsif ($type_atom =~ /^\s*(\S+)\s*$/) {
				# no subtype, so use type
				($type, $subtype) = ($1, $1);
			} else {
				# something else...give up on this atom
				print "Error interpretting Type entry \"$type_atom\". ($filename)\n";
				$looks_good = 0;
				next;
			}

			# getting here means we have a valid atom; build %-exp map
			( $expand->{"type_raw[$type]"} = $subtype );
			( $expand->{"type_pkg[$type]"} = $subtype ) =~ s/\.//g;
			( $expand->{"type_num[$type]"} = $subtype ) =~ s/[^\d]//g;
		}
	}

	$pkgname = &expand_percent($properties->{package}, $expand, $filename.' Package');

	$pkgname =~ s/-+/-/g;  # variants with Package: foo-%type_*[bar]
	$pkgname =~ s/-*$//g;  # leave extraneous hyphens

	( $pkginvarname = $properties->{package} ) =~ s/\%type_(raw|pkg|num)\[.*?\]//g;

	# right now we don't know how to deal with variants too well
	# FIXME: this is a bit suspect:
	#   Does %lib only exist for Type:lib?
	#   Why does validation depend on the machine on which it's running?
	if (defined ($type = $properties->{type}) ) {
		$type =~ s/(\S+?)\s*\(:?.*?\)/$1 ./g;  # use . for all subtype lists
		$type_hash = Fink::PkgVersion->type_hash_from_string($type,$filename);
		$expand->{"lib"} = "lib";
		if (exists $type_hash->{"-64bit"}) {
			if ($type_hash->{"-64bit"} eq "-64bit") {
				if ($config->param('Architecture') eq "powerpc" ) {
					$expand->{"lib"} = "lib/ppc64";
				} elsif ($config->param('Architecture') eq "i386" ) {
					$expand->{"lib"} = "lib/x86_64";
				} elsif ($config->param('Architecture') eq "x86_64" ) {
					print "Warning: the -64bit type may have unexpected effects under x86_64 Architecture. ($filename)\n";
					$looks_good = 0;
				} else {
					die "Your Architecture is not suitable for 64bit libraries.\n";
				}
			}
		}
	}

	$pkgversion = $properties->{version};
	$pkgversion = '' unless defined $pkgversion;
	$pkgrevision = $properties->{revision};
	$pkgrevision = '' unless defined $pkgrevision;
	$pkgepoch = $properties->{epoch};
	$pkgepoch = '' unless defined $pkgepoch;
	# TODO: If epoch has been specified, the pkgfullname should make use of it, too
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
		print "Error: Package name ' $pkgname ' is invalid. ";
		print "Package names may only contain lowercase letters, numbers,";
		print "'.', '+' and '-' ($filename)\n";
		$looks_good = 0;
	}
	if ($pkgversion =~ /[^+\-.a-z0-9]/) {
		print "Error: Version ' $pkgversion ' is invalid. ";
		print "Package versions may only contain lowercase letters, numbers,";
		print "'.', '+' and '-' ($filename)\n";
		$looks_good = 0;
	}
	if ($pkgrevision =~ /[^+.a-z0-9]/) {
		print "Error: Revision ' $pkgrevision ' is invalid. ";
		print "Package revisions may only contain lowercase letters, numbers,";
		print "'.' and '+' ($filename)\n";
		$looks_good = 0;
	}
	if ($pkgepoch !~ /^([1-9][0-9]*)?$/) {
		# Strictly speaking "0" is also a legal epoch (and in fact the default epoch
		# value), but we don't want people to add "Epoch: 0" fields to their packages,
		# so we forbid that.
		print "Error: Package epoch must be a positive integer ($filename)\n";
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
	# and may contain arch and/or distro and/or version-revision components

	$looks_good = 0 unless &_validate_info_filename($properties, $filename, $pkgname);

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
		if ($value =~ /($|,)[^,()]*,/) {
			print "Warning: Malformed license field.  All but the final item should be conditional.  ($filename)\n";
			$looks_good = 0;
		}
		$value =~ s/\(.*?\)//g;  # remove all conditionals
		$value =~ s/^\s*//;      # ...which sometimes leaves leading whitespace
		foreach (split /\s*,\s*/, $value) {
			if ($_ =~ /GPL(\/|$)/) {
				# this is an "old-style" GPL license field
				# (at some future time we will deprecate these)
			}
			$_ =~ s/GPL(23|2|3)\+?/GPL/g; #remove the "decorations" from
			                              #new-style GPL license fields
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
	my %test_source_fields = map { lc $_, 1 } grep { /^testsource(|[2-9]|[1-9]\d+)$/ } keys %$test_properties;

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
	foreach (keys(%source_fields), keys(%test_source_fields)) {
		my $source_props = /^test/i ? $test_properties : $properties;
		if (exists $source_props->{$_} and $source_props->{$_} =~ /^none$/i) {
			delete $source_fields{$_};  # keep just real ones
			if (/\d+/) {
				print "Warning: \"$_: none\" is a no-op. ($filename)\n";
				$looks_good = 0;
			}
		} else {
			my $md5_field      = $_ . "-md5";
			my $checksum_field = $_ . "-checksum";
			if (!exists $source_props->{$md5_field} and !defined $source_props->{$md5_field} and !exists $source_props->{$checksum_field} and !defined $source_props->{$checksum_field}) {
				print "Error: \"$_\" does not have a corresponding \"$md5_field\" or \"$checksum_field\" field. ($filename)\n";
				$looks_good = 0;
			}
			# fink recently changed .tar.xz source handling (now
			# auto-extracts) and maybe other .xz effects as well
			if (exists $source_props->{$_} and $source_props->{$_} =~ /\.xz$/ ) {
				$looks_good=0 unless _require_dep($properties, {build => {'fink' => '0.32'} }, 'use of a .xz source archive', $filename);
			}
		}
	}

	$expand = { 'n' => $pkgname,
				'N' => $pkgname,
				'v' => $pkgversion,
				'V' => $pkgversion,
				'r' => $pkgrevision,
				'e' => $pkgepoch,
				'f' => $pkgfullname,
				'p' => $basepath, 'P' => $basepath,
				'd' => $pkgdestdir,
				'i' => $pkgdestdir.$basepath,
#				'a' => $pkgpatchpath,
				'b' => '.',
				'm' => $config->param('Architecture'),
				%{$expand},
				'ni' => $pkginvarname,
				'Ni' => $pkginvarname
	};

	if (&validate_info_component(
			 properties => $properties,
			 filename => $filename,
			 info_level => $info_level,
			 expand => $expand,
		) == 0) {
		$looks_good = 0;
	} elsif ($properties->{infotest} and &validate_info_component(
				 properties => $test_properties,
				 filename => $filename,
				 info_level => $info_level,
				 expand => $expand,
				 is_infotest => 1,
			 ) == 0) {
		$looks_good = 0;
	}

	my $field_check = sub {
		my($field, $value, $in_infotest) = @_;

		# Warn if field is obsolete
		if ($obsolete_fields{$field}) {
			print "Warning: Field \"$field\" is obsolete. ($filename)\n";
			$looks_good = 0;
		}

		# Boolean field?
		if ($boolean_fields{$field} and not ((lc $value) =~ /^\s*(true|yes|on|1|false|no|off|0)\s*$/)) {
			print "Warning: Boolean field \"$field\" contains suspicious value \"$value\". ($filename)\n";
			$looks_good = 0;
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
		if ($field =~ /^(test)?(?:source(\d*)-checksum|source(\d*)-md5|source(\d*)rename|tar(\d*)filesrename|source(\d+)extractdir)$/) {
			my $testfield = $1 || "";
			my $sourcefield = defined $+  # corresponding Source(N) field
				? "${testfield}source$+"
				: "${testfield}source";
			if ($testfield ? (!exists $test_source_fields{$sourcefield}) : (!exists $source_fields{$sourcefield})) {
				my $msg = $field =~ /-(checksum|md5)$/
					? "Warning" # no big deal
					: "Error";  # probably means typo, giving broken behavior
					print "$msg: \"$field\" specified for non-existent \"$sourcefield\". ($filename)\n";
					$looks_good = 0;
				}
			return;
		}

		# Validate splitoffs
		if ($field eq 'splitoff1') {
			print "Warning: Field \"splitoff1\" is unknown (use \"splitoff\" for first SplitOff package). ($filename)\n";
			$looks_good = 0;
		} elsif ($field =~ m/^splitoff([2-9]|[1-9]\d+)?$/) {
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

			if (&validate_info_component(
					 properties => $splitoff_properties,
					 splitoff_field => $splitoff_field,
					 filename => $filename,
					 info_level => $info_level,
					 expand => { 'N' => $pkgname, %{$expand} },
					 builddepends => $properties->{builddepends},
				) == 0) {
				$looks_good = 0;
			}

			if (defined ($value = $splitoff_properties->{files})) {
				if ($value =~ /\/[\s\r\n]/ or $value =~ /\/$/) {
					print "Warning: Field \"files\" of \"$splitoff_field\" contains entries that end in \"/\" ($filename)\n";
					$looks_good = 0;
				}
				if ($value =~ /[?*]\W*\//) {
					print "Error: Field \"files\" of \"$splitoff_field\" contains wildcard directories ($filename)\n";
					$looks_good = 0;
				}
			}
		} # end of SplitOff field validation
	};

	# Loop over all fields and verify them
	while (my($field, $value) = each(%$properties)) {
		$field_check->($field, $value, 0);
	}
	while (my($field, $value) = each(%$test_properties)) {
		$field_check->($field, $value, 1);
	}

	if (exists $properties->{runtimevars} and defined $properties->{runtimevars}) {
		for my $line (split(/\n/, $properties->{runtimevars})) {
			# error for having %p/lib in RuntimeVars
			if ($line =~ m,^\s*(DYLD_LIBRARY_PATH:\s+($basepath|\%p)/lib/?)\s*$,) {
				print "Error: '$1' in RuntimeVars will break many shared libraries. ($filename)\n";
				$looks_good = 0;
			# error for PYTHONPATH as it is version agnostic and will break other pymods
        	} elsif ($line =~ m,^\s*PYTHONPATH:.*$,) {
				print "Error: 'PYTHONPATH' in RuntimeVars can break other Python scripts. ($filename)\n";
				$looks_good = 0;
			}
		}
	}

	my %patchfile_fields = map { lc $_, 1 } grep { /^patchfile(|[2-9]|[1-9]\d+)$/ } keys %$properties;
	my %patchfile_md5_fields = map { lc $_, 1 } grep { /^patchfile(|[2-9]|[1-9]\d+)-md5$/ } keys %$properties;

	for my $field (keys %patchfile_fields) {
		if (exists $properties->{$field}) {
			if ($pkgpatchpath eq "") {
				$expand->{$field} = $properties->{$field};
			} else {
				$expand->{$field} = $pkgpatchpath . '/' . $properties->{$field};
			}
		}
	}

	# Verify the patch file(s) exist and check some things
	# anything in PatchScript that looks like a patch file name
	# (i.e., strings matching the glob %a/*.patch)
	$value = $properties->{patchscript} || $test_properties->{patchscript};
	if ($value and $value =~ /\%a\/.*?\.patch/) {
		print "Error: %a is no longer supported. Use PatchFile, and \%\{PatchFile\} to reference the patch. ($filename)\n";
		$looks_good = 0;
	}

	# the contents if Patch (if any)
	if ($properties->{patch} || $test_properties->{patch}) {
		if (exists $properties->{patchscript}) {
			print "Error: The Patch field is no longer supported. Use PatchFile, and \%\{PatchFile\} to apply the patch explicitly in PatchScript. ($filename)\n";
		} else {
			print "Error: The Patch field is no longer supported. Use PatchFile instead. ($filename)\n";
		}
		$looks_good = 0;
	}

	# check the contents of PatchFile (if any)
	if (exists $expand->{patchfile}) {
		for my $field (keys %patchfile_fields) {
			my $pretty_field = $field;
			$pretty_field =~ s/patchfile/PatchFile/i;
			$value = "\%{$field}";
			$value = &expand_percent($value, $expand, $filename.' Patch');
			unless (-f $value) {
				print "Error: can't read $pretty_field. ($value)\n";
				$looks_good = 0;
			}
			else {
				# Check patch file
				open(INPUT, "<$value") or die "Couldn't read $pretty_field ($value): $!\n";
				my $patch_file_content = <INPUT>;
				close INPUT or die "Couldn't read $pretty_field ($value): $!\n";
				# Check for empty patch file
				if (!$patch_file_content) {
					print "Warning: $pretty_field is an empty file. ($value)\n";
					$looks_good = 0;
				}
				# Check for line endings of patch file
				elsif ($patch_file_content =~ m/\r\n/s) {
					print "Error: $pretty_field has DOS line endings. ($value)\n";
					$looks_good = 0;
				}
				elsif ($patch_file_content =~ m/\r/s) {
					print "Error: $pretty_field has Mac line endings. ($value)\n";
					$looks_good = 0;
				}
				# Check for hardcoded /sw.
				open(INPUT, "<$value") or die "Couldn't read $pretty_field ($value): $!\n";
				while (defined($patch_file_content=<INPUT>)) {
					# only check lines being added (and skip diff header line)
					next unless $patch_file_content =~ /^\+(?!\+\+ )/;
					if ($patch_file_content =~ /\/sw([\s\/]|\Z)/) {
						print "Warning: $pretty_field appears to contain a hardcoded /sw. ($value)\n";
						$looks_good = 0;
						last;
					}
				}
				close INPUT or die "Couldn't read $pretty_field ($value): $!\n";
			}
		}
	}

	# if we are using new PatchFile field, check some things about it
	for my $field (keys %patchfile_fields) {
		my $pretty_field = $field;
		$pretty_field =~ s/patchfile/PatchFile/i;

		if (not exists $patchfile_md5_fields{$field.'-md5'}) {
			print "Error: No $pretty_field-MD5 given for $pretty_field. ($filename)\n";
			$looks_good = 0;
		}

		# must declare BuildDepends on a fink that supports it
		if ($field eq "patchfile") {
# 0.24.12 came out many years ago and nothing that old likely even
# boots on any currently supported OSX
#			$looks_good = 0 unless _require_dep($properties, {build => {'fink' => '0.24.12'} }, 'use of PatchFile', $filename);
		} else {
			$looks_good = 0 unless _require_dep($properties, {build => {'fink' => '0.30.0'} }, 'use of PatchFileN', $filename);
		}

		# can't mix old and new patching styles
		if (exists $properties->{patch}) {
			print "Error: Cannot use both Patch and $pretty_field. ($filename)\n";
			$looks_good = 0;
		}

		# must have PatchFileN-MD5 field that matches file's checksum
		if (defined ($value = $properties->{"$field-md5"})) {
			my $file = &expand_percent("\%{$field}", $expand, $filename.' '.$pretty_field);
			my $file_md5 = file_MD5_checksum($file);
			if ($value ne $file_md5) {
				print "Error: $pretty_field-MD5 does not match $pretty_field checksum. ($filename)\n\tActual: $file_md5\n\tExpected: $value\n";
				$looks_good = 0;
			}
		} else {
			print "Error: No $pretty_field-MD5 given for $pretty_field. ($filename)\n";
			$looks_good = 0;
		}

		# must actually be used
		if (defined ($value = $properties->{'patchscript'})) {
			if ($value !~ /%{($pretty_field|default_script)}/) {
				print "Warning: $pretty_field does not appear to be used in PatchScript. ($filename)\n";
				$looks_good = 0;
			}
		}
	}

	for my $field (keys %patchfile_md5_fields) {
		$field =~ s/-md5$//;
		my $pretty_field = $field; $pretty_field =~ s/patchfile/PatchFile/;

		if (not exists $patchfile_fields{$field}) {
			print "Warning: No $pretty_field given for $pretty_field-MD5. ($filename)\n";
			$looks_good = 0;
		}
	}

	# Check for Type: dummy, only allowed for internal use
	if (exists $type_hash->{dummy}) {
		print "Error: Package has type \"dummy\". ($filename)\n";
		$looks_good = 0;
	}

	# instantiate the PkgVersion objects
	my @pvs = Fink::PkgVersion->pkgversions_from_info_file($full_filename, no_exclusions => 1);

	if (@pvs > 1) {
		my %names;
		foreach (map {$_->get_name()} @pvs) {
			if ($names{$_}++) {
				print "Error: Duplicate declaration of package \"$_\". ($filename)\n";
				$looks_good = 0;
			}
		}
	}

	# Warn for missing / overlong package descriptions
	if (not (defined $properties->{description} and length $properties->{description})) {
		# main package in .info must have one
		print "Error: No package description supplied. ($filename)\n";
		$looks_good = 0;
	}

	foreach my $pv (@pvs) {
		# sanity-checks for each in family (including variants and splitoffs)

		my $name = $pv->get_name();

		# misc rules for the Description field (if there is one)
		if (defined (my $desc = $pv->{description})) {
			if (length($desc) > 60 and !$pv->is_obsolete()) {
				print "Error: Description of \"$name\" exceeds 60 characters. ($filename)\n";
				$looks_good = 0;
			} elsif (Fink::Config::get_option("Pedantic")) {
				# Some pedantic checks
				if (length($desc) > 45 and !$pv->is_obsolete() ) {
					print "Warning: Description of \"$name\" exceeds 45 characters. ($filename)\n";
					$looks_good = 0;
				}
				if ($desc =~ m/^[Aa]n? /) {
					print "Warning: Description of \"$name\" starts with \"A\" or \"An\". ($filename)\n";
					$looks_good = 0;
				}
				if ($desc =~ m/^[a-z]/) {
					print "Warning: Description of \"$name\" starts with lower case. ($filename)\n";
					$looks_good = 0;
				}
				if ($desc =~ /\b\Q$name\E\b/i and !$pv->is_obsolete() ) {
					print "Warning: Description of \"$name\" contains package name. ($filename)\n";
					$looks_good = 0;
				}
				if ($desc =~ m/\.$/) {
					print "Warning: Description of \"$name\" ends with \".\". ($filename)\n";
					$looks_good = 0;
				}
				if ($desc =~ m/^\[/) {
					print "Warning: Descriptions beginning with \"[\" are only for special types of packages. ($filename)\n";
					$looks_good = 0;
				}
			}
		}

		# Language-versioned packages need the language itself
		# (otherwise mis- or fail-to-build, and not usable at
		# runtime). Require only for bottom of lang-versioned
		# dep-trees (e.g., varianted perlmods that do not depend on
		# other varianted perlmods must depend on varianted perl
		# interp). Higher parts of dep-tree thus get them indirectly.
		# Skip obsolete packages (replacement might be unified).
		if ($name =~ /-(pm|py|rb)(\d+)/) {
			my $modpkg = "-$1$2";
			my $langpkg;
			if ($1 eq 'pm') {
				$langpkg = "perl$2-core";
			} elsif ($1 eq 'py') {
				$langpkg = "python$2";
			} else {
				$langpkg = "ruby$2";
			}

			my $depends = $pv->pkglist_default('depends', '');
			unless ($depends =~ /(\A|,|\s)($langpkg|.*$modpkg)(-|\z|,|\s|\()/ || $pv->is_obsolete) {
				print "Error: language-versioned package $name needs Depends on another $modpkg (package of the same language-version) or on $langpkg (the language interpretter itself). ($filename)\n";
				$looks_good = 0;
			}
		}

		foreach my $field (sort keys %pkglist_fields) {
			next if $field eq 'architecture'; # same format but entries not same as for dpkg package specs
			foreach my $altspecs (@{&pkglist2lol($pv->pkglist_default($field, ''))}) {
				foreach my $depspec (@$altspecs) {
					$depspec =~ s/\s+//g;
					my $verspec = ($depspec =~ s/\((.*)\)//);
					if ($depspec =~ /[^+\-.a-z0-9]/) {
						print "Error: invalid character in packagename \"$depspec\" in $field of package $name. ($filename)\n";
						$looks_good = 0;
					}
					# TODO: check epoch, version, revision
				}
			}
		}
	}

	if ($looks_good and $config->verbosity_level() >= 3) {
		print "Package looks good!\n";
	}

	return $looks_good;
}

# Return a boolean indicating whether the given $filename (no dir
# hierarchy) is appropriate for the given .info $properties hash when
# used with the $canonical_pkg packagename. If not, a warning is
# issued.
sub _validate_info_filename {
	my $properties = shift;     # hashref (will not be altered)
	my $filename = shift;       # filename of .info file
	my $canonical_pkg = shift;  # already %-expanded

	my $looks_good = 1;

	# build permutations
	my @filearch = ("");
	my @filedist = ("");
	my @filesuffix = ("", "-".$properties->{version}, "-".$properties->{version}."-".$properties->{revision});
	my @ok_filenames;
	if (my $arch = $properties->{architecture}) {
		if ($arch !~ /,/) {
			# single-arch package
			$arch =~ s/\s+//g;

			push @filearch, ("-$arch");
		}
	}
	if (my $dist = $properties->{distribution}) {
		if ($dist !~ /,/) {
			# single-dist package
			$dist =~ s/\s+//g;

			push @filedist, ("-$dist");
		}
	}
	foreach my $rch (@filearch) {
		foreach my $dst (@filedist) {
			foreach my $sfx (@filesuffix) {
				push @ok_filenames, "$canonical_pkg$rch$dst$sfx.info";
			}
		}
	}

	unless (grep $filename eq $_, @ok_filenames) {
		print "Warning: Incorrect filename '$filename'. Should be one of:\n", map "\t$_\n", @ok_filenames;
		return 0;
	}
	return 1;
}


# Given a $package_hash hashref of fields, check that there is a
# dependency on a specified minimum version of some package according
# to the $required_versions hashref:
#   One or more of these mode keys controlling the type of dep:
#     "build" -- compile-time deps (BuildDepends and Depends)
#     "run" -- run-time deps (Depends and RuntimeDepends)
#   The value of each of the above keys is a hashref of the form:
#     {$pkg,$minver}
#   meaning there must be a dependency of the form: $pkg (>= $minver)
#     If $minver is not defined, no "(>= ...)" is required.
#     The actual dep in the $package_hash may be stricter (higher than
#       $minver).
# All entries in the hashrefs of all mode keys must be satisfied.
# If there is not a sufficient dependency, a warning is printed
# print warning indicating the minimum dependency requirement in
# the $filename (.info file) for $feature.
# The return value is a boolean indicating whether all dep
# requirements were satisfied.
sub _require_dep {
	my $package_hash = shift;
	my $required_versions = shift;
	my $feature = shift;
	my $filename = shift;

	my $all_ok = 1;

	if (exists $required_versions->{build}) {
		my %reqs = %{$required_versions->{build}}; # clone so we can alter it

		foreach (
			@{&pkglist2lol($package_hash->{builddepends})},
			@{&pkglist2lol($package_hash->{depends})},
		) {
			foreach my $atom (@$_) {
				$atom =~ s/^\(.*?\)\s*//;
				while ( my($pkg,$minver) = each %reqs ) {
					if (defined $minver) {
						# need to check version spec
						$atom =~ /^$pkg\s*\(\s*(>>|>=)\s*(.*?)\)\s*$/;
						delete $reqs{$pkg} if version_cmp($2, '>=', $minver);
					} elsif ($atom eq $pkg) {
						# no version spec needed, just check that dep
						# exists without version spec...
						delete $reqs{$pkg};
 					} elsif ($atom =~ /^$pkg\s*\(/) {
						# ...but any version spec still okay
						delete $reqs{$pkg};
					}
				}
			}
		}

		if (keys %reqs) {
			print "Error: $feature requires declaring a BuildDepends or Depends on:\n";
			print map { "\t$_" . ( defined $reqs{$_} ? " (>= $reqs{$_})\n" : "\n" ) } sort keys %reqs;
			$all_ok = 0;
		}
	}

	if (exists $required_versions->{run}) {
		my %reqs = %{$required_versions->{run}}; # clone so we can alter it

		foreach (
			@{&pkglist2lol($package_hash->{depends})},
			@{&pkglist2lol($package_hash->{runtimedepends})},
		) {
			foreach my $atom (@$_) {
				$atom =~ s/^\(.*?\)\s*//;
				while ( my($pkg,$minver) = each %reqs ) {
					if (defined $minver) {
						# need to check version spec
						$atom =~ /^$pkg\s*\(\s*(>>|>=)\s*(.*?)\)\s*$/;
						delete $reqs{$pkg} if version_cmp($2, '>=', $minver);
					} elsif ($atom eq $pkg) {
						# no version spec needed, just check that dep
						# exists without version spec...
						delete $reqs{$pkg};
 					} elsif ($atom =~ /^$pkg\s*\(/) {
						# ...but any version spec still okay
						delete $reqs{$pkg};
					}
				}
			}
		}

		if (keys %reqs) {
			print "Error: $feature requires declaring a Depends or RuntimeDepends on:\n";
			print map { "\t$_" . ( defined $reqs{$_} ? " (>= $reqs{$_})\n" : "\n" ) } sort keys %reqs;
			$all_ok = 0;
		}
	}

	return $all_ok;
}

# checks that are common to a parent and a splitoff package of a .info file
# returns boolean of whether everything is okay
# The following parameters are known:
#   properties        hashref (will not be altered)
#   splitoff_field    "splitoffN", or null or undef in parent
#   filename          filename of .info file being validated
#   info_level        InfoN level
#   is_infotest       boolean indicating if this is an InfoTest field
#   builddepends      BuildDepends of parent if this is not a parent field

sub validate_info_component {
	my %options;
	if (ref $_[0]) {
		# old-style positional-parameters
		@options{qw/ properties splitoff_field filename info_level is_infotest /} = @_;
	} else {
		# new-style named parameters
		%options = @_;
	}
	my $properties = $options{properties};
	my $splitoff_field = $options{splitoff_field};
	my $filename = $options{filename};
	my $info_level = $options{info_level};
	my $expand = $options{expand};
	my $is_infotest = $options{is_infotest};

	# make sure this $option is available even in parent
	$options{builddepends} = $properties->{builddepends} unless $splitoff_field;

	my (@pkg_required_fields, %pkg_valid_fields);

	my $is_splitoff = 0;
	$splitoff_field = "" unless defined $splitoff_field;
	if (defined $splitoff_field && length $splitoff_field) {
		$is_splitoff = 1;
		$splitoff_field = sprintf ' of "%s"', $splitoff_field;
		@pkg_required_fields = @splitoff_required_fields;
		%pkg_valid_fields = %splitoff_valid_fields;
	} elsif ($is_infotest) {
		@pkg_required_fields = @infotest_required_fields;
		%pkg_valid_fields = (%infotest_valid_fields, %valid_fields);
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
			my $test = "";
			$test = " from InfoTest" if $is_infotest;
			print "Error: Required field \"$field\"$splitoff_field missing${test}. ($filename)\n";
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
		# this doesn't work for unicode; is there a good way to accept unicode without just ignoring validation?
		if ($value =~ /[^[:ascii:]]/) {
			print "Warning: \"$field\"$splitoff_field contains non-ASCII characters. ($filename)\n";
			$looks_good = 0;
		}

		# Warn if field is unknown
		unless ($pkg_valid_fields{$field}) {
			unless (!$is_splitoff and
					( $field =~ m/^(test)?source([2-9]|[1-9]\d+)(|extractdir|rename|-md5|-checksum)$/
					  or $field =~ m/^patchfile([2-9]|[1-9]\d+)(|-md5)$/
					  or $field =~ m/^(test)?tar([2-9]|[1-9]\d+)filesrename$/
					  ) ) {
				my $test = "";
				$test = " inside InfoTest" if $is_infotest;
				print "Warning: Field \"$field\"$splitoff_field is unknown${test}. ($filename)\n";
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
					print "Error: Info3 or later is required for \"#\" comments in \"$field\"$splitoff_field. ($filename)\n";
					$looks_good = 0;
				}
				if ($pkglist =~ /,\s*$/) {
					print "Error: Info3 or later is required for trailing \",\" in \"$field\"$splitoff_field. ($filename)\n";
					$looks_good = 0;
				}
				if (($pkglist =~ /%V/) and ($info_level <= 3)) {
					print "Error: Info4 or later is required for percent expansion %V in \"$field\"$splitoff_field. ($filename)\n";
					$looks_good = 0;
				}
			}

			# verify only well-defined percent expansions are used.
			&expand_percent2($value, $expand,
			                  'err_action' => 'undef',
			                  'err_info'   => $filename.' '.$field );

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
					print "Warning: invalid conditional in dependency \"$atom\" in \"$field\"$splitoff_field. ($filename)\n";
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

	# Packages using RuntimeDepends must BuildDepends on a fink that supports it
	$value = $properties->{runtimedepends};
	if (defined $value) {
		$looks_good = 0 unless _require_dep(\%options, { build => {'fink' => '0.32'} }, 'use of RuntimeDepends', $filename);
	}

	# check syntax of each line of Shlibs field
	$value = $properties->{shlibs};
	if (defined $value) {
		my @shlibs = split /\n/, $value;
		my %shlibs;
		foreach (@shlibs) {
			s/^\s*(.*?)\s*$/$1/;  # strip off leading/trailing whitespace
			next unless /\S/;

			if (s/^\(.*?\)\s*//) {
				$looks_good = 0 unless _require_dep(\%options, { build => {'fink' => '0.27.2'} }, 'use of conditionals in Shlibs', $filename);
		}

			if (/^\!\s*(.*)/) {
				$looks_good = 0 unless _require_dep(\%options, { build => {'fink' => '0.28'} }, 'private-library entry in Shlibs', $filename);
				if ($1 =~ /\s/) {
					print "Warning: Malformed line in field \"shlibs\"$splitoff_field.\n  $_\n";
					$looks_good = 0;
				}
				next;
			}

			my @shlibs_parts;
			if (scalar(@shlibs_parts = split ' ', $_, 3) != 3) {
				print "Warning: Malformed line in field \"shlibs\"$splitoff_field. ($filename)\n  $_\n";
				$looks_good = 0;
				next;
			}
			if (not $shlibs_parts[0] =~ /^(\%p|@[a-z,_]*path)?\//) {
				print "Warning: Pathname \"$shlibs_parts[0]\" is not absolute and is not in \%p or a runtime path in field \"shlibs\"$splitoff_field. ($filename)\n";
				$looks_good = 0;
			}
			if ($shlibs{$shlibs_parts[0]}++) {
				print "Warning: Entry \"$shlibs_parts[0]\" is listed more than once in field \"shlibs\"$splitoff_field. ($filename)\n";
				$looks_good = 0;
			}
			if (not $shlibs_parts[1] =~ /^\d+\.\d+\.\d+$/) {
				print "Warning: Malformed compatibility_version for \"$shlibs_parts[0]\" in field \"shlibs\"$splitoff_field. ($filename)\n";
				$looks_good = 0;
			}
			my @shlib_deps = split /\s*\|\s*/, $shlibs_parts[2], -1;
			# default value of $libarch, if absent, is "32" for the
			# powerpc and i386 architectures, and "64" for x86_64
			my $libarch = "32";
			if ($config->param('Architecture') eq "x86_64" ) {
				$libarch = "64";
			}
			# strip off the end of the last @shlib_deps entry (the stuff
			# beyond the final close-paren), which should consist of digits
			# and "-" only, and use as $libarch
			if ($shlib_deps[$#shlib_deps] =~ /^(.*\))\s*([^\s\)]+)$/ ) {
				$shlib_deps[$#shlib_deps] = $1;
				$libarch = $2;
			}
			# This hack only allows one particular percent expansion in the
			# $libarch field, because this subroutine doesn't do percent
			# expansions.  OK for now, but should be fixed eventually.
			my $num_expand = {"type_num[-64bit]" => "64"};
			$libarch = &expand_percent($libarch, $num_expand, $filename.' Package');
			if (not ($libarch eq "32" or $libarch eq "64" or $libarch eq "32-64")) {
				print "Warning: Library architecture \"$libarch\" for \"$shlibs_parts[0]\" in field \"shlibs\"$splitoff_field is not one of the allowed types (32, 64, or 32-64). ($filename)\n";
				$looks_good = 0;
			}
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
			print "Warning: Library architecture is not one of the allowed types (32, 64, or 32-64)\n" unless ($libarch eq "32" or $libarch eq "64" or $libarch eq "32-64");
		}
	}

	$value = $properties->{conffiles};
	if (defined $value and $value =~ /\(.*?\)/) {
		$looks_good = 0 unless _require_dep(\%options, { build => {'fink' => '0.27.2'} }, 'use of conditionals in ConfFiles', $filename);
	}

	# Special checks when package building script uses an explicit interp

	foreach my $field (qw/patchscript compilescript installscript testscript/) {
		next unless defined ($value = $properties->{$field});
		if ($value =~ /^\s*\#!\s*(\S+)([^\n]*)/) {

			# Call with -ev or -ex so they abort if any command fails
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

			# Try to make sure subshell failure is not ignored
			if ($value =~ /^\s*\(.*\)\s*$/m) {
					print "Warning: Parenthesized subshell return code not checked in \"$field\"$splitoff_field. ($filename)\n";
					$looks_good = 0;
			}
		}
	}

	# support for new script templates
	# TODO: This field is not documented.
	if (exists $properties->{defaultscript}) {
		$value = lc $properties->{defaultscript};
		my $ds_min = {
			'autotools'   => '0.30.0',
			'makemaker'   => '0.30.0',
			'ruby'        => '0.30.0',
			'modulebuild' => '0.30.2',
		}->{$value};
		if (defined $ds_min) {
			$looks_good = 0 unless _require_dep($properties, { build => {'fink' => $ds_min} }, "use of DefaultScript:$value", $filename);
		} else {
			print "Warning: unknown DefaultScript type \"$value\". ($filename)\n";
			$looks_good = 0;
		}
	}

	return $looks_good;
}

# given a (possibly undefined) Depends field, determine if it contains
# the sentinel indicating the package with this Depends is "obsolete"
sub obsolete_via_depends {
	my $properties = shift;
	if (defined $properties->{depends}) {
		return 1 if $properties->{depends} =~ /(\A|,)\s*fink-obsolete-packages(\(|\s|,|\Z)/;
	}
	if (defined $properties->{runtimedepends}) {
		return 1 if $properties->{runtimedepends} =~ /(\A|,)\s*fink-obsolete-packages(\(|\s|,|\Z)/;
	}
	return 0;
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
	my $destdir = tempdir('fink-validate-deb-unpack.XXXXXXXXXX', DIR => File::Spec->tmpdir );

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
	my $destdir = shift;     # absolute path to %d
	my $val_prefix = shift;  # %p

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
# - BuildDependsOnly: if package stores files an include/ dir, it should
#     declare BuildDependsOnly true
# - Check presence and execute-flag on executable specified in daemonicfile
# - If a package contains a daemonicfile, it should Depends:daemonic
# - Check for symptoms of running update-scrollkeeper during package building
# - If a package has .omf sources, it should call update-scrollkeeper during Post(Inst,Rm}Script
# - If a package Post{Inst,Rm}Script calls update-scrollkeeper, it should Depends:rarian-compat
# - Only gettext should should have charset.alias
# - If a package *Script uses debconf, it should Depends:debconf
#   (TODO: should be in preinst not postinst, should be PreDepends not Depends)
# - if a pkg is a -pmXXX but installs files that are not in a XXX-specific path
# - Catch common error relating to usage of -framework flag in .pc and .la files
# - Look for symptoms of missing InfoDocs field in .info
# - Look for packages that contain no files
#
# - any other ideas?
#
sub _validate_dpkg {
	my $destdir = shift;  # %d, or its moral equivalent
	my $val_prefix = shift;

	chomp(my $otool = `which otool 2>/dev/null`);
	undef $otool unless -x $otool;
	chomp(my $otool64 = `which otool64 2>/dev/null`); # older OSX has separate tool for 64-bit
	undef $otool64 unless -x $otool64;				  # binaries (otool itself cannot handle them)
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
	my @bad_dirs = ( map "$basepath/$_/", qw( src man info doc libexec lib/locale bin/.* sbin/.* ) );
	push(@bad_dirs, ( map ".*/$_/", qw( CVS RCS \.svn \.git \.hg ) ) ); # forbid version control residues

	my @good_dirs = ( map "$basepath/$_/", qw( bin sbin include lib opt share var etc Applications Library/Frameworks Library/Python ) );
	# allow $basepath/Library/ by itself, but with nothing below it other than what we explicitly allowed already
	# (needed since we allow $basepath/Library/Frameworks)
	push(@good_dirs, "$basepath/Library/\$");
	push(@good_dirs, '/usr/X11');

	my @found_bad_dir;
	my ($installed_headers, $installed_ld_libs) = (0, 0);
	my @installed_dylibs;

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
		print "Error: could not read control file: $!\n";
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

	# read the shlibs database file
	my $deb_shlibs = {};
	{
		foreach my $debfile ('shlibs', 'private-shlibs') {
			my $filename = "$destdir/DEBIAN/$debfile";
			if (-f $filename) {
				if (open my $script, '<', $filename) {
					chomp( my @deb_shlibs_raw = <$script> );  # slurp the data file
					close $script;
					my ($entry_filename, $entry_compat, $entry_deps);
					foreach my $entry (@deb_shlibs_raw) {
						if (($entry_filename) = $entry =~ /^\s*\!\s*(\S+)\s*$/) {
							$deb_shlibs->{$entry_filename} = {
								is_private => 1,
							};
						} elsif (($entry_filename, $entry_compat, $entry_deps) = $entry =~ /^\s*(.+?)\s+(.+?)\s+(.*?)\s*$/) {
							$deb_shlibs->{$entry_filename} = {
								compatibility_version => $entry_compat,
								dependencies          => $entry_deps,
								is_private            => 0,
							};
						}
					}
				} else {
					print "Error: could not read dpkg shlibs database file ($debfile): $!\n";
					$looks_good = 0;
				}
			}
		}
	}

	# create hash where keys are names of packages listed in Depends
	$control_processed->{depends_pkgs} = {
		map { /\s*([^ \(]*)/, undef } split /[|,]/, $deb_control->{depends}
	};

	# prepare to check that -pmXXX, -pyXX, and -rbXX packages only contain
	# file in language-versioned locations: define a regex for the
	# language-versioned path component
	my $langver_re;
	if ($deb_control->{package} =~ /-(pm|py|rb)(\d+)$/) {
		$langver_re = $2;
		if ($1 eq 'pm') {
			# perl language is major.minor.teeny
			if ($langver_re =~ /^(\d)(\d)(\d)$/) {
				# -pmXYZ is perlX.Y.Z
				$langver_re = "(?:$langver_re|$1.$2.$3)";
			} elsif ($langver_re =~ /^(\d)(\d)(\d)(\d)$/) {
				# -pmWXYZ is perlW.X.YZ or perlW.XY.Z
				$langver_re = "(?:$langver_re|$1.$2.$3$4|$1.$2$3.$4)";
			} elsif ($langver_re =~ /^(\d)(\d\d)(\d\d)$/) {
				# -pmXYYZZ is perlX.YY.ZZ
				$langver_re = "(?:$langver_re|$1.$2.$3)";
			}
		} else {
			# python language is major.minor
			# ruby language is major.minor
			# numbers are all "small" (one-digit)
			$langver_re =~ /^(\d)(\d)$/;
			# -pyXY is pythonX.Y
			# -rbXY is rubyX.Y
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
	my %case_insensitive_filename = (); # keys are lc($fullpathname) for all items in .deb

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
			} elsif ($deb_control->{package} !~ /^(xfree86|xorg|mesa)/ and $deb_control->{section} !~ /x11-modular/) {
				&stack_msg($msgs, "File installed outside of $basepath", $filename);
			} else {
				if (not (($filename =~ /^\/Applications\/XDarwin.app/) || ($filename =~ /^\/usr\/X11/) || ($filename =~ /^\/private\/etc\/fonts/) )) {
					return if (($filename eq "/Applications/") || ($filename eq "/private/") || ($filename eq "/private/etc/") || ($filename eq "/usr/"));
					&stack_msg($msgs, "File installed outside of $basepath, /Applications/XDarwin.app, /private/etc/fonts, /usr/X11, and /usr/X11R6", $filename);
				}
			}
		} elsif ($filename eq "$basepath/src/") {
			# FIXME: For some reason, we allow the inclusion of $basepath/src,
			# which may exist but must be empty. The reason for this should either
			# be documented, or this hack be removed.
		} elsif (@found_bad_dir = grep { $filename =~ /^$_/ } @bad_dirs) {
			# Directories from this list are not allowed to exist in the .deb.
			&stack_msg($msgs, "File installed into deprecated directory $found_bad_dir[0]", $filename);
		} elsif (not grep { $filename =~ /^$_/ } @good_dirs) {
			# Directories from this list are the top-level dirs that may exist in the .deb.
			&stack_msg($msgs, "File installed outside of allowable subdirectories of $basepath", $filename);
		}

		# check for compiled-perl modules in unversioned place (perl5/$arch/auto or perl5/auto)
		if ($filename =~ /^$basepath\/lib\/perl5\/([^\/]+\/)?auto\/.*\.bundle/) {
			&stack_msg($msgs, "Apparent perl XS module installed directly into $basepath/lib/perl5 instead of a perl-versioned subdirectory.", $filename);
		}

		# check for compiled emacs libs
		if ($filename =~ /\.elc$/ &&
			$deb_control->{package} !~ /^emacs\d\d(|-.*)$/ &&
			$deb_control->{package} !~ /^xemacs(|-.*)$/
		   ) {
			&stack_msg($msgs, "Compiled .elc file installed. Package should install .el files, and provide a /sw/lib/emacsen-common/packages/install/<package> script that byte compiles them for each installed Emacs flavour.", $filename);
		}

		# track whether BuildDependsOnly will be needed
		if ($filename =~/\/include\// && !-d $File::Find::name) {
			$installed_headers = 1;
		}
		if ($filename =~/\.framework\/(.+)/) {
			# heuristic for Framework library suites
			if (-d $File::Find::name && !-l $File::Find::name) {
				# allow real directory (only care about real file or
				# symlink to dir ("real file" on disk) that would
				# collide among .deb)
			} else {
				my $component = $1;
				if ($component eq 'Versions/Current/' or $component !~ /^Versions\//) {
					# non-libversioned Framework files
					if (!exists $deb_control->{builddependsonly} or $deb_control->{builddependsonly} =~ /Undefined/) {
						&stack_msg($msgs, "Framework files not part of a specific library-version, but package does not declare BuildDependsOnly to be true (or false)", $filename);
					}
				}
			}
		}

		if ($filename =~ /\.(dylib|jnilib|so|bundle)$/) {
			if ($filename =~ /\.dylib$/) {
				$installed_ld_libs = 1;
			}
			if (defined $otool) {
				my $file = $destdir . $filename;
				if (not -l $file) {
					$file =~ s/\'/\\\'/gs;
					if (open(OTOOL, "$otool -hv '$file' |")) {
						while (my $line = <OTOOL>) {
							if (my ($type) = $line =~ /MH_MAGIC.*\s+DYLIB(\s+|_STUB\s+)/) {
								if ($filename !~ /\.(dylib|jnilib)$/) {
									print "Warning: $filename is a DYLIB but it does not end in .dylib or .jnilib.\n";
								}
								push(@installed_dylibs, $filename);
							} elsif ($line =~ /MH_MAGIC/) {
								if ($filename =~ /\.dylib$/) {
									print "Warning: $filename ends in .dylib but is not of filetype DYLIB according to otool.\n";
								}
							}
						}
						close (OTOOL);
					}
				}
			} elsif ($filename =~/\.(dylib|jnilib)$/) {
				print "Warning: unable to locate otool, assuming $filename is a DYLIB binary\n";
				push(@installed_dylibs, $filename);
			}
			my( $fn_name, $fn_ext ) = $filename =~ /^(.*)(\..*)/g;  # parse apart at extension
			if ( (grep { /^\Q$fn_name\E.+\Q$fn_ext\E$/ && !$deb_shlibs->{$_}->{is_private} } sort keys %$deb_shlibs) && !(exists $deb_shlibs->{$filename})) {
				&stack_msg($msgs, "Files with names less specifically versioned than ones in public Shlibs entries do not belong in this package", $filename);
			}
		}

		# make sure scrollkeeper is being used according to its documentation
		if ( $filename =~/^$basepath\/share\/omf\/.*\.omf$/ ) {
			foreach (qw/ postinst postrm /) {
				next if $_ eq "postrm" && $deb_control->{package} eq "scrollkeeper"; # circular dep
				if (not grep { /^\s*scrollkeeper-update/ } @{$dpkg_script->{$_}}) {
					&stack_msg($msgs, "Scrollkeeper source file found, but scrollkeeper-update not called in $_. See rarian-compat package docs, starting with 'fink info rarian-compat', for information.", $filename);
				}
			}
		}

		# make sure site-wide gtk icon caches are not overwritten by pkg's own
		if ( $filename =~/^$basepath\/share\/icons\/.*\/icon-theme.cache$/ ) {
			&stack_msg($msgs, "Package overwrites a sitewide icon index. Packagers must disable gtk-update-icon-cache in InstallScript and instead do it in PostInstScript and PostRmScript.", $filename);
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
			if (!-l $File::Find::name and open my $daemonicfile, '<', $File::Find::name) {
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
			} elsif (!-l _) {
				&stack_msg($msgs, "Couldn't read DaemonicFile $File::Find::name: $!");
			}
		}

		# libtool and pkg-config files don't link to temp locations
		if ($filename =~ /\.(pc|la)$/) {
			my $filetype = ($1 eq 'pc' ? 'pkg-config' : 'libtool');
			if (!-l $File::Find::name and open my $datafile, '<', $File::Find::name) {
				while (<$datafile>) {
					chomp;
					if (/$pkgbuilddir/) {
						&stack_msg($msgs, "Published compiler flag points to fink build dir.", $filename);
						last;
					} elsif (/$pkginstdirs/) {
						&stack_msg($msgs, "Published compiler flag points to fink install dir.", $filename);
						last;
					}
				}
				close $datafile;
			} elsif (!-l _) {
				&stack_msg($msgs, "Couldn't read $filetype file \"$filename\": $!");
			}
		}

		# check that compiled python modules files don't self-identify using temp locations
		if ($filename =~/\.py[co]$/) {
			if (!-l $File::Find::name and open my $py_file, '-|', 'strings', $File::Find::name) {
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
			} elsif (!-l _) {
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
		# is not language-versioned (goal: all language-versions of a
		# package are orthogonal and do not conflict with each other)
		if (defined $langver_re and $filename !~ /$langver_re/ and !-d $File::Find::name) {
			&stack_msg($msgs, "File in a language-versioned package does not have a pathname specific to that version.", $filename);
		}

		# passing -framework flag and its argument as separate words
		if ($filename =~ /\.(pc|la)$/) {
			my $filetype = ($1 eq 'pc' ? 'pkg-config' : 'libtool');
			if (!-l $File::Find::name and open my $datafile, '<', $File::Find::name) {
				while (<$datafile>) {
					chomp;
					if (/\s((?:-W.,|)-framework)[^,]/ || /\s(-Xlinker)\s/) {
						&stack_msg($msgs, "The $1 flag may get munged by $filetype. See the gcc manpage for information about passing multi-word options to flags for specific compiler passes.", $filename, $_);
					}
				}
				close $datafile;
			} elsif (!-l _) {
				&stack_msg($msgs, "Couldn't read $filetype file \"$filename\": $!");
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

		# Check for "live" perllocal.pod file. Normal perl-module
		# installation creates/updates this global file, so for a
		# package-manager environment this mechanism needs to be
		# overridden and occur at package installation-time instead.
		if ($filename =~ /^$basepath\/lib\/perl.*\/perllocal.pod$/) {
			&stack_msg($msgs, "A global perllocal.pod must not be installed directly as part of the .deb (use UpdatePOD or related mechanism)", $filename);
		}

		# count number of files and links ("real things, not dirs") in %i
		lstat $File::Find::name;
		$dpkg_file_count++ if -f _ || -l _;

		# check that there won't be collisions on case-insensitive
		# filesystems. Will only be triggered on pkgs built in
		# case-sensitive filesystems (if case-insensitive, the files
		# or dirs would have already over-written or coalesced during
		# InstallScript)
		if ($case_insensitive_filename{lc $filename}++) {
			&stack_msg($msgs, "Pathname collision on case-insensitive filesystems", $filename);
		}

		# check that gtk-doc (devhelp) documenation cross-links aren't
		# obviously incorrect local URLs
		if ($filename =~/$basepath\/share\/gtk-doc\/.+\.html$/) {
			if (!-l $File::Find::name and open my $gtkdocfile, '<', $File::Find::name) {
				my %seen_lines = (); # only print one example of each bad line
				while (<$gtkdocfile>) {
					chomp;
					if (/href\s*=\s*"(\/[^"]+)"/) { # extract target of HREF attribute
						if ($1 !~ /^$basepath\/.*/ and !$seen_lines{$_}++) { # see if it begins with fink prefix
							&stack_msg($msgs, "Bad local URL (\"$1\" does not look like a fink location).", $filename, $_);
						}
					}
				}
				close $gtkdocfile;
			} elsif (!-l _) {
				&stack_msg($msgs, "Couldn't read gtk-doc file \"$filename\": $!");
			}
		}

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
	if ($installed_headers and $installed_ld_libs) {
		if (!exists $deb_control->{builddependsonly} or $deb_control->{builddependsonly} =~ /Undefined/) {
			print "Error: Headers installed (files in an include/ directory), as well as a .dylib file, but package does not declare BuildDependsOnly to be true (or false)\n";
			$looks_good = 0;
		}
	}

	# make sure we have Depends:scrollkeeper if scrollkeeper is called in dpkg scripts
	foreach (qw/ preinst postinst prerm postrm /) {
		next if $deb_control->{package} eq "scrollkeeper"; # circular dep
		next if $deb_control->{package} eq "rarian-compat"; # circular dep (new-world scrollkeeper)
		if (grep { /^\s*scrollkeeper-update/ } @{$dpkg_script->{$_}} and not (
				exists $control_processed->{depends_pkgs}->{'rarian-compat'}
			)) {
			print "Error: Calling scrollkeeper-update in $_ requires \"Depends:rarian-compat\"\n";
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

	# check shlibs field
	if (%$deb_shlibs and not defined $otool) {
		print "Warning: Package has shlibs data but otool is not in the path; skipping parts of shlibs validation.\n";
	}
	foreach my $shlibs_file (sort keys %$deb_shlibs) {
		my ($file, $named_file);
		#discard runtime path portion of the install_name
		($named_file) = $shlibs_file =~ /^\@[a-z,_]*path\/(.*)/ ; 
		if ( $named_file ) {
			find ({wanted => sub {$file = $File::Find::name if m,$named_file,}, no_chdir=>1 }, $destdir);
		} else {
			$file = resolve_rooted_symlink($destdir, $shlibs_file);
		}
		if (not defined $file) {
			if ($deb_control->{'package'} eq 'fink') {
				# fink is a special case, it has a shlibs field that provides system-shlibs
			} elsif ($deb_shlibs->{$shlibs_file}->{'is_private'}) {
				# AKH: it appears that we've been allowing @rpath and friends for private libraries?
				if ($shlibs_file !~ /^\@/) {
					print "Warning: Shlibs field specifies private install_name '$shlibs_file', but it does not exist!\n";
				}
			} else {
				print "Error: Shlibs field specifies install_name '$shlibs_file', but it does not exist!\n";
				$looks_good = 0;
			}
		} elsif (not -f $file) {
			# shouldn't happen, resolve_rooted_symlink returns a file, or undef
		} elsif ($deb_shlibs->{$shlibs_file}->{'is_private'}) {
			# don't validate private shlibs entries
		} else {
			$file =~ s/\'/\\\'/gs;
			if (defined $otool) {
				if (open (OTOOL, "$otool -L '$file' |")) {
					<OTOOL>; # skip the first line
					my ($libname, undef, $compat_version) = <OTOOL> =~ /^\s*((\/|@[a-z,_]*path\/).+?)\s*\(compatibility version ([\d\.]+)/;
					close (OTOOL);

					if (!defined $libname or !defined $compat_version) {
						if (defined $otool64) {
							if (open (OTOOL, "$otool64 -L '$file' |")) {
								<OTOOL>; # skip the first line
								($libname, $compat_version) = <OTOOL> =~ /^\s*(\/.+?)\s*\(compatibility version ([\d\.]+)/;
								close (OTOOL);
							}
						}
					}
					if (!defined $libname or !defined $compat_version) {
						print "Error: Name '$shlibs_file' specified in Shlibs does not appear to have linker data at all\n";
						$looks_good = 0;
					} else {
						if ($shlibs_file ne $libname) {
							print "Error: Name '$shlibs_file' specified in Shlibs does not match install_name '$libname'\n";
							$looks_good = 0;
						}
						if ($deb_shlibs->{$shlibs_file}->{'compatibility_version'} ne $compat_version) {
							print "Error: Shlibs field says compatibility version for $shlibs_file is ".$deb_shlibs->{$shlibs_file}->{'compatibility_version'}.", but it is actually $compat_version.\n";
							$looks_good = 0;
						}
					}
				} else {
					print "Warning: otool -L failed on $file.\n";
				}
			}
		}
	}

	for my $dylib (@installed_dylibs) {
		next if (-l $destdir . $dylib);
		if (defined $otool) {
			my $dylib_temp = resolve_rooted_symlink($destdir, $dylib);
			if (not defined $dylib_temp) {
				print "Warning: unable to resolve symlink for $dylib.\n";
			} else {
				$dylib_temp =~ s/\'/\\\'/gs;
				if (open (OTOOL, "$otool -L '$dylib_temp' |")) {
					<OTOOL>; # skip first line
					my ($libname, $compat_version) = <OTOOL> =~ /^\s*(\S+)\s*\(compatibility version ([\d\.]+)/;
					close (OTOOL);
					if (($libname !~ /^\//) and ($libname !~ /^\@[a-z,_]*path\//)) {
						print "Error: package contains the shared library\n";
						print "          $dylib\n";
						print "       but the corresponding install_name\n";
						print "          $libname\n";
						print "       is not an absolute pathname or runtime path.\n";
						$looks_good = 0;
					} elsif (not exists $deb_shlibs->{$libname}) {
						$libname =~ s/^$basepath/%p/;
						print "Error: package contains the shared library\n";
						print "          $dylib\n";
						print "       but the corresponding install_name and compatibility_version\n";
						print "          $libname $compat_version\n";
						print "       are not listed in the Shlibs field.  See the packaging manual.\n";
						$looks_good = 0;
					}
				}
				if (open (OTOOL, "$otool -hv '$dylib_temp' |")) {
					<OTOOL>; <OTOOL>; <OTOOL>; # skip first three lines
					unless ( <OTOOL> =~ /TWOLEVEL/ ) {
						print "SERIOUS WARNING: $dylib_temp appears to have been linked using a flat namespace.\n";
						print "       If this package BuildDepends on libtool2, make sure that you use\n";
						print "          BuildDepends: libtool2 (>= 2.4.2-4).\n";
						print "       and use autoreconf to regenerate the configure script.\n";
						print "       If the package doesn't BuildDepend on libtool2, you'll need to\n";
						print "       update its build procedure to avoid passing\n";	 
						print "          -Wl,-flat_namespace\n"; 
						print "       when linking libraries.\n\n";
						print "		  If this package actually requires a flat namespace build,\n";
						print "		  then ignore this message.\n\n";
						sleep 60;
					} 
					close (OTOOL);
				}
			}
		}
	}

	if ($looks_good and $config->verbosity_level() >= 3) {
		print "Package looks good!\n";
	}

	return $looks_good;
}

sub resolve_rooted_symlink {
	my $destdir = shift;
	my $file    = shift;

	return unless (defined $destdir and defined $file);
	if (-l $destdir . $file) {
		my $link = readlink($destdir . $file);
		if ($link =~ m#^/#) {
			return resolve_rooted_symlink($destdir, $link);
		} else {
			return resolve_rooted_symlink($destdir, dirname($file) . '/' . $link);
		}
	} elsif (-e $destdir . $file) {
		return $destdir . $file;
	}

	return undef;
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

# given two filenames $file1 and $file2, check whether one is a more
# specifically versioned form of the other. That is, "libfoo.1.dylib"
# is more versioned than "libfoo.dylib" but less versioned than
# "libfoo.1.2.dylib". The return is a normal tristate comparison value
# (-1 if $file1 less specific than $file2, "0 but true" (numerically
# zero, boolean true) if same, +1 if $file1 more specific than
# $file2). Filenames are stripped of their extension ".$ext" if $ext
# is given. If the two filenames are not related in this fashion at
# all or if they both do not have the specific $ext, 0 (boolean false)
# is returned.  Filenames can be absolute paths, relative paths, or
# simple filenames, but they must be the same in this regard.
#
# Implementation: substring test rooted at beginning of the strings.
sub _filename_versioning_cmp {
	my $file1 = shift;
	my $file2 = shift;
	my $ext = shift;

	if (defined $ext) {
		$file1 =~ s/\Q.$ext\E$// || return 0;
		$file2 =~ s/\Q.$ext\E$// || return 0;
	}

	if ($file1 =~ /^\Q$file2.\E.*$/) {
		# s2 substring of s1 --> s1 more versioned
		return 1;
	} elsif ($file2 =~ /^\Q$file1.\E.*$/) {
		# s1 substring of s2 --> s1 less versioned
		return -1;
	} elsif ($file1 eq $file2) {
		# s1 and s2 are the same
		return "0 but true";
	}
	# s1 and s2 are unrelated
	return 0;
}


### EOF
1;
# vim: ts=4 sw=4 noet
