# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Validation module
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
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#

package Fink::Validation;

use Fink::Services qw(&read_properties &read_properties_var &expand_percent &get_arch);
use Fink::Config qw($config $basepath $buildpath);

use strict;
use warnings;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
	$VERSION	 = 1.00;
	@ISA		 = qw(Exporter);
	@EXPORT		 = qw();
	@EXPORT_OK	 = qw(&validate_info_file &validate_dpkg_file);
	%EXPORT_TAGS = ( );			# eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

# Currently, the Set* and NoSet* fields only support a limited list of variables.
our @set_vars =
	qw(
		cc cflags cpp cppflags cxx cxxflags dyld_library_path
		ld_prebind ld_prebind_allow_overlap ld_force_no_prebind
		ld_seg_addr_table ld ldflags library_path libs
		macosx_deployment_target make mflags makeflags
	);

# Required fields.
our @required_fields =
	qw(Package Version Revision Maintainer);

# All fields that expect a boolean value
our %boolean_fields = map {$_, 1}
	(
		qw(essential nosourcedirectory updateconfigguess updatelibtool updatepod noperltests),
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
		 compilescript
		 installscript
		 shlibs
		 preinstscript
		 postinstscript
		 prermscript
		 postrmscript
		 conffiles
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
	 "Restrictive", "Commercial"
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
		 'infon',  # set by handle_infon_block if InfoN: used
#  dependencies:
		 'depends',
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



END { }				# module clean-up code here (global destructor)



# Should check/verifies the following in .info files:
#	+ the filename matches %f.info
#	+ patch file (from Patch and PatchScript) is present
#	+ all required fields are present
#	+ warn if obsolete fields are encountered
#	+ warn about missing Description/Maintainer/License fields
#	+ warn about overlong Description fields
#	+ warn about Description starting with "A" or "An" or containing the package name
#	+ warn if boolean fields contain bogus values
#	+ warn if fields seem to contain the package name/version, and suggest %n/%v should be used
#		(excluded from this are fields like Description, Homepage etc.)
#	+ warn if unknown fields are encountered
#	+ warn if /sw is hardcoded in the script or set fields or patch file
#		(from Patch and PatchScript)
#	+ correspondence between source* and source*-md5 fields
#	+ if type is bundle/nosource - warn about usage of "Source" etc.
#	+ if 'fink describe' output will display poorly on vt100
#	+ Check Package/Version/Revision for disallowed characters
#
# TODO: Optionally, should sort the fields to the recommended field order
#	- better validation of splitoffs
#	- validate dependencies, e.g. "foo (> 1.0-1)" should generate an error since
#	  it uses ">" instead of ">>".
#	- correct format of Shlibs: (including misuse of %v-%r)
#	- use of %n in SplitOff:Package: (should be %N)
#	- use of SplitOff:Depends: %n (should be %N (tracker Bugs #622810)
#	- actually instantiate the Package or PkgVersion object
#	  (easier to try it than to check for some broken-ness here)
#	- run a mock build phase (catch typos in dependencies,
#	  BuildDependsOnly violations, etc.)
#	- ... other things, make suggestions ;)
#
sub validate_info_file {
	my $filename = shift;
	my ($properties, @parts);
	my ($pkgname, $pkgversion, $pkgrevision, $pkgfullname, $pkgdestdir, $pkgpatchpath, @patchfiles);
	my ($field, $value);
	my ($basepath, $expand, $buildpath);
	my ($type_hash);
	my $looks_good = 1;
	my $error_found = 0;
	my $arch = get_arch();

	if (Fink::Config::verbosity_level() == 3) {
		print "Validating package file $filename...\n";
	}
	
	#
	# Check for line endings before reading properties
	#
	open(INPUT, "<$filename"); 
	my $info_file_content = <INPUT>; 
	close INPUT;
	if ($info_file_content =~ m/\r\n/s) {
		print "Error: Info file has DOS line endings. ($filename)\n";
		$looks_good = 0;
	}
	return unless ($looks_good);
	if ($info_file_content =~ m/\r/s) {
		print "Error: Info file has Mac line endings. ($filename)\n";
		$looks_good = 0;
	}
	return unless ($looks_good);

	# read the file properties
	$properties = &read_properties($filename);
	$properties = Fink::Package->handle_infon_block($properties, $filename);
	return unless keys %$properties;
	
	# determine the base path
	$basepath = $config->param_default("basepath", "/sw");
	$buildpath = $config->param_default("buildpath", "$basepath/src");

	$pkgname = $properties->{package};

	$pkgversion = $properties->{version};
	$pkgrevision = $properties->{revision};
	$pkgfullname = "$pkgname-$pkgversion-$pkgrevision";
	$pkgdestdir = "$buildpath/root-".$pkgfullname;
	
	@parts = split(/\//, $filename);
	$filename = pop @parts;		# remove filename
	$pkgpatchpath = join("/", @parts);

	#
	# First check for critical errors
	#

	# Verify that all required fields are present
	foreach $field (@required_fields) {
		unless ($properties->{lc $field}) {
			print "Error: Required field \"$field\" missing. ($filename)\n";
			$looks_good = 0;
		}
	}
	if ($pkgname =~ /[^+-.a-z0-9]/) {
		print "Error: Package name may only contain lowercase letters, numbers,";
		print "'.', '+' and '-' ($filename)\n";
		$looks_good = 0;
	}
	if ($pkgversion =~ /[^+-.a-z0-9]/) {
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

	return unless ($looks_good);

	#
	# Now check for other mistakes
	#
	
	unless (("$pkgfullname.info" eq $filename) || ("$pkgname.info" eq $filename)) {
		print "Warning: File name should be $pkgfullname.info or $pkgname.info ($filename)\n";
		$looks_good = 0;
	}
	
	# Make sure Maintainer is in the correct format: Joe Bob <jbob@foo.com>
	$value = $properties->{maintainer};
	if ($value !~ /^[^<>@]+\s+<\S+\@\S+>$/) {
		print "Warning: Malformed value for \"maintainer\". ($filename)\n";
		$looks_good = 0;
	}

	# License should always be specified, and must be one of the allowed set
	$value = $properties->{license};
	if ($value) {
		if (not $allowed_license_values{$value}) {
			print "Warning: Unknown license \"$value\". ($filename)\n";
			$looks_good = 0;
		}
	} elsif (not (defined($properties->{type}) and $properties->{type} =~ /\bbundle\b/i)) {
		print "Warning: No license specified. ($filename)\n";
		$looks_good = 0;
	}

	# error if have a source or MD5 for type nosource
	if (exists $properties->{type} and $properties->{type} =~ /\b(nosource|bundle)\b/i) {
		if ($properties->{source}) {
			print "Error: Not using a source (type \"$1\") but \"source\" specified. ($filename)\n";
			$looks_good = 0;
		}
		if ($properties->{"source-md5"}) {
			print "Error: Not using a source (type \"$1\") but \"source-md5\" specified. ($filename)\n";
			$looks_good = 0;
		}
	}

	# error if have an MD5 for implicit type nosource (i.e., source=none)
	if (lc $properties->{source} =~ /^none$/i and $properties->{"source-md5"}) {
		print "Error: Not using a source (implicit nosource) but \"source-md5\" specified. ($filename)\n";
		$looks_good = 0;
	}

	# error if using the default source but there is no MD5
	# (not caught later b/c there is no "source")
	if (exists $properties->{type} and $properties->{type} =~ /\b(nosource|bundle)\b/i) {
	# nosource and bundle are supposed to not have source
	} elsif (not $properties->{source} and not $properties->{"source-md5"}) {
		print "Error: No MD5 checksum specified for implicitly defined \"source\". ($filename)\n";
		$looks_good = 0;
	}

	# Loop over all fields and verify them
	foreach $field (keys %$properties) {
		$value = $properties->{$field};

		# Warn if field is obsolete
		if ($obsolete_fields{$field}) {
			print "Warning: Field \"$field\" is obsolete. ($filename)\n";
			$looks_good = 0;
			next;
		}

		# Boolean field?
		if ($boolean_fields{$field} and not (lc $value) =~ /^\s*(true|yes|on|1|false|no|off|0)\s*$/) {
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
		if ($text_describe_fields{$field} and $value) {
			# no intelligent word-wrap so warn for long lines
			my $maxlinelen = 79;
			foreach my $line (split /\n/, $value) {
				if (length $line > $maxlinelen) {
					print "Warning: \"$field\" contains line(s) exceeding $maxlinelen characters. ($filename)\nThis field may be displayed with line-breaks in the middle of words.\n";
					$looks_good = 0;
					last;
				}
			}
			# warn for non-plain-text chars
			if ($value =~ /[^[:ascii:]]/) {
				print "Warning: \"$field\" contains non-standard characters. ($filename)\n";
				$looks_good = 0;
			}
		}

		# Error if there is a source without an MD5
		if ((($field eq "source" and lc $properties->{source} ne "none")
				or $field =~ m/^source([2-9]|\d\d)$/)
				and not $properties->{$field."-md5"}) {
			print "Error: No MD5 checksum specified for \"$field\". ($filename)\n";
			$looks_good = 0;
		}

		# Error if there is an MD5 without a source
 		if ($field =~ /^(source\d+)-md5$/) {
			my $sourcefield = $1;
			if (not $properties->{$sourcefield}) {
				print "Error: \"$field\" specified but no \"$sourcefield\" specified. ($filename)\n";
				$looks_good = 0;
			}
		}

		if ($field eq "files" and ($value =~ m#/[\s\r\n]# or $value =~ m#/$#)) {
			print "Warning: Field \"$field\" contains entries that end in \"/\" ($filename)\n";
			$looks_good = 0;
		}

		# Check for hardcoded /sw.
		if ($check_hardcode_fields{$field} and $value =~ /\/sw([\s\/]|$)/) {
			print "Warning: Field \"$field\" appears to contain a hardcoded /sw. ($filename)\n";
			$looks_good = 0;
			next;
		}

		# Validate splitoffs
		if ($field =~ m/^splitoff([2-9]|\d\d)?$/) {
			# Parse the splitoff properties
			my $splitoff_properties = $properties->{$field};
			my $splitoff_field = $field;
			$splitoff_properties =~ s/^\s+//gm;
			$splitoff_properties = &read_properties_var("$field of \"$filename\"", $splitoff_properties);
			# Right now, only 'Package' is a required field for a splitoff.
			foreach $field (qw(package)) {
				unless ($splitoff_properties->{lc $field}) {
					print "Error: Required field \"$field\" missing for \"$splitoff_field\". ($filename)\n";
					$looks_good = 0;
				}
			}
		
			foreach $field (keys %$splitoff_properties) {
				$value = $splitoff_properties->{$field};

				if ($field eq "files" and ($value =~ m#/[\s\r\n]# or $value =~ m#/$#)) {
					print "Warning: Field \"$field\" of \"$splitoff_field\" contains entries that end in \"/\" ($filename)\n";
					$looks_good = 0;
				}

				# Check for hardcoded /sw.
				if ($check_hardcode_fields{$field} and $value =~ /\/sw([\s\/]|$)/) {
					print "Warning: Field \"$field\" of \"$splitoff_field\" appears to contain a hardcoded /sw. ($filename)\n";
					$looks_good = 0;
					next;
				}

				# Warn if field is unknown or invalid within a splitoff
				unless ($splitoff_valid_fields{$field}) {
					if ($valid_fields{$field}) {
						print "Warning: Field \"$field\" of \"$splitoff_field\" is not valid in splitoff. ($filename)\n";
					} else {
						print "Warning: Field \"$field\" of \"$splitoff_field\" is unknown. ($filename)\n";
					}
					$looks_good = 0;
					next;
				}
			}
		}

		# Warn if field is unknown
		unless ($valid_fields{$field}
				 or $field =~ m/^splitoff([2-9]|\d\d)$/
				 or $field =~ m/^source([2-9]|\d\d)$/
				 or $field =~ m/^source([2-9]|\d\d)-md5$/
				 or $field =~ m/^source([2-9]|\d\d)extractdir$/
				 or $field =~ m/^source([2-9]|\d\d)rename$/
				 or $field =~ m/^tar([2-9]|\d\d)filesrename$/) {
			print "Warning: Field \"$field\" is unknown. ($filename)\n";
			$looks_good = 0;
			next;
		}
	}

	# Warn for missing / overlong package descriptions
	$value = $properties->{description};
	unless ($value) {
		print "Error: No package description supplied. ($filename)\n";
		$looks_good = 0;
	}
	elsif (length($value) > 60) {
		print "Error: Length of package description exceeds 60 characters. ($filename)\n";
		$looks_good = 0;
	}
	elsif (length($value) > 45 and Fink::Config::verbosity_level() == 3) {
		print "Warning: Length of package description exceeds 45 characters. ($filename)\n";
		$looks_good = 0;
	}
	
	# Check if description starts with "A" or "An", or with lowercase
	# or if it contains the package name
	if ($value) {
		if ($value =~ m/^[Aa]n? /) {
			print "Warning: Description starts with \"A\" or \"An\". ($filename)\n";
			$looks_good = 0;
		}
		elsif ($value =~ m/^[a-z]/) {
			print "Warning: Description starts with lower case. ($filename)\n";
			$looks_good = 0;
		}
		if ($value =~ /\b\Q$pkgname\E\b/i) {
			print "Warning: Description contains package name. ($filename)\n";
			$looks_good = 0;
		}
		if ($value =~ m/\.$/) {
			print "Warning: Description ends with \".\". ($filename)\n";
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
				'm' => $arch
	};

	if (defined $properties->{type}) {
		$type_hash = Fink::PkgVersion->type_hash_from_string($properties->{type},$filename);
		foreach (keys %$type_hash) {
			( $expand->{"type_pkg[$_]"} = $expand->{"type_raw[$_]"} = $type_hash->{$_} ) =~ s/\.//g;
		}
	} else {
		$type_hash = {};
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
	}

	# the contents if Patch (if any)
	$value = $properties->{patch};
	if ($value) {
		# add directory if info is not simple filename (not in $PWD)
		$value = "\%a/" .$value if $pkgpatchpath;
		unshift @patchfiles, $value;
	}

	# now check each one in turn
	foreach $value (@patchfiles) {
		$value = &expand_percent($value, $expand);
		unless (-f $value) {
			print "Error: can't find patchfile \"$value\"\n";
			$looks_good = 0;
		}
		else {
			# Check patch file
			open(INPUT, "<$value"); 
			my $patch_file_content = <INPUT>; 
			close INPUT;
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
			open(INPUT, "<$value"); 
			while (defined($patch_file_content=<INPUT>)) {
				# only check lines being added (and skip diff header line)
				next unless $patch_file_content =~ /^\+(?!\+\+ )/;
				if ($patch_file_content =~ /\/sw([\s\/]|$)/) {
					print "Warning: Patch file appears to contain a hardcoded /sw. ($value)\n";
					$looks_good = 0;
					last;
				}
			}
			close INPUT;
		}
	}
	
	if ($looks_good and Fink::Config::verbosity_level() == 3) {
		print "Package looks good!\n";
	}
}

#
# Check a given .deb file for standard compliance
#
# - usage of non-recommended directories (/sw/src, /sw/man, /sw/info, /sw/doc, /sw/libexec, /sw/lib/locale)
# - usage of other non-standard subdirs 
# - storage of a .bundle inside /sw/lib/perl5/darwin or /sw/lib/perl5/auto
# - Emacs packages
#     - installation of .elc files
#     - installing files directly in /sw/share/emacs/site-lisp
# - ideas?
#
sub validate_dpkg_file {
	my $dpkg_filename = shift;
	my @bad_dirs = ("$basepath/src/", "$basepath/man/", "$basepath/info/", "$basepath/doc/", "$basepath/libexec/", "$basepath/lib/locale/");
	my ($pid, $bad_dir);
	my $filename;
	my $looks_good = 1;

	print "Validating .deb file $dpkg_filename...\n";
	
	# Quick & Dirty solution!!!
	# This is a potential security risk, we should maybe filter $dpkg_filename...
	$pid = open(DPKG_CONTENTS, "dpkg --contents $dpkg_filename |") or die "Couldn't run dpkg: $!\n";
	while (<DPKG_CONTENTS>) {
		# process
		if (/([^\s]*)\s*([^\s]*)\s*([^\s]*)\s*([^\s]*)\s*([^\s]*)\s*\.([^\s]*)/) {
			$filename = $6;
			#print "$filename\n";
			next if $filename eq "/";
			if (not $filename =~ /^$basepath/) {
				print "Warning: File \"$filename\" installed outside of $basepath\n";
				$looks_good = 0;
			} elsif ($filename =~/^($basepath\/lib\/perl5\/auto\/.*\.bundle)/ ) {
				print "Warning: Apparent perl XS module installed directly into $basepath/lib/perl5 instead of a versioned subdirectory.\n  Offending file: $1\n";
				$looks_good = 0;
			} elsif ( $filename =~/^($basepath\/lib\/perl5\/darwin\/.*\.bundle)/ ) {
				print "Warning: Apparent perl XS module installed directly into $basepath/lib/perl5 instead of a versioned subdirectory.\n  Offending file: $1\n";
				$looks_good = 0;
			} elsif ( ($filename =~/^($basepath\/.*\.elc)$/) &&
				  (not (($dpkg_filename =~ /^emacs[0-9][0-9]/) ||
					($dpkg_filename =~ /xemacs/)))) {
				$looks_good = 0;
				print "Warning: Compiled .elc file installed. Package should install .el files, and provide a /sw/lib/emacsen-common/packages/install/<package> script that byte compiles them for each installed Emacs flavour.\n  Offending file: $1\n";
			} elsif ( ($filename =~/^($basepath\/share\/emacs\/site-lisp\/[^\/]+)$/) &&
				  (not $dpkg_filename =~ /^emacsen-common_/)) {
				$looks_good = 0;
				print "Warning: File installed directly in $basepath/share/emacs/site-lisp. Files should be installed in a package subdirectory.\n  Offending file: $1\n";
			} else {
				foreach $bad_dir (@bad_dirs) {
					# Directory from this list are not allowed to exist in the .deb.
					# The only exception is $basepath/src which may exist but must be empty
					if ($filename =~ /^$bad_dir/ and not $filename eq "$basepath/src/") {
						print "Warning: File installed into deprecated directory $bad_dir\n";
						print "					Offender is $filename\n";
						$looks_good = 0;
						last;
					}
				}
			}
		}
	}
	close(DPKG_CONTENTS) or die "Error on close: $!\n";
	
	if ($looks_good and Fink::Config::verbosity_level() == 3) {
		print "Package looks good!\n";
	}
}


### EOF
1;
