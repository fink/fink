#
# Fink::Validation module
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
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#

package Fink::Validation;

use Fink::Services qw(&read_properties &expand_percent);
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
	qw(cc cflags cpp cppflags cxx cxxflags dyld_library_path ld ldflags library_path libs macosx_deployment_target make mflags);

# Required fields.
our @required_fields =
	qw(Package Version Revision Maintainer);

# All fields that expect a boolean value
our %boolean_fields = map {$_, 1}
	(
		qw(essential nosourcedirectory updateconfigguess updatelibtool updatepod),
		map {"noset".$_} @set_vars
	);

# Obsolete fields, generate a warning
our %obsolete_fields = map {$_, 1}
	qw(comment commentport commenstow usegettext);

# Fields in which %n/%v can and should be used
our %name_version_fields = map {$_, 1}
	qw(
		 source sourcedirectory sourcerename
		 source0 source0extractdir source0rename
		 patch
		);

# Allowed values for the type field
our %allowed_type_values = map {$_, 1}
	qw(nosource bundle perl);

# Allowed values for the license field
our %allowed_license_values = map {$_, 1}
	(
	 "GPL", "LGPL", "GFDL", "LDP", "BSD",
	 "Artistic", "OSI-Approved", "Public Domain",
	 "Restrictive", "Restrictive/Distributable", "Commercial",
	 "Artistic/GPL", "GPL/GFDL", "GPL/LGPL", "LGPL/GFDL"
	);

# List of all known fields.
our %known_fields = map {$_, 1}
	(
		qw(
		 package
		 epoch
		 version
		 revision
		 type
		 maintainer
		 depends
		 builddepends
		 provides
		 conflicts
		 replaces
		 recommends
		 suggests
		 enhances
		 pre-depends
		 essential
		 builddependsonly
		 source
		 source-md5
		 custommirror
		 sourcedirectory
		 nosourcedirectory
		 sourcerename
		 updateconfigguess
		 updateconfigguessindirs
		 updatelibtool
		 updatelibtoolindirs
		 updatepomakefile
		 updatepod
		 patch
		 patchscript
		 configureparams
		 gcc
		 compilescript
		 installscript
		 shlibs
		 runtimevars
		 splitoff
		 jarfiles
		 tarfilesrename
		),
		(map {"set".$_} @set_vars),
		(map {"noset".$_} @set_vars),
		qw(
		 preinstscript
		 postinstscript
		 prermscript
		 postrmscript
		 conffiles
		 infodocs
		 docfiles
		 daemonicfile
		 daemonicname
		 description
		 descdetail
		 descusage
		 descpackaging
		 descport
		 homepage
		 license
		)
	);

END { }				# module clean-up code here (global destructor)



# Should check/verifies the following in .info files:
#		+ the filename matches %f.info
#		+ patch file is present
#		+ all required fields are present
#		+ warn if obsolete fields are encountered
#		+ warn about missing Description/Maintainer/License fields
#		+ warn about overlong Description fields
#		+ warn about Description starting with "A" or "An" or containing the package name
#		+ warn if boolean fields contain bogus values
#		+ warn if fields seem to contain the package name/version, and suggest %n/%v should be used
#			(excluded from this are fields like Description, Homepage etc.)
#		+ warn if unknown fields are encountered
#
# TODO: Optionally, should sort the fields to the recommended field order
#		- error if format is violated (e.g. bad here-doc)
#		- warn if /sw is hardcoded somewhere
#		- if type is bundle/nosource - warn about usage of "Source" etc.
# ... other things, make suggestions ;)
#
sub validate_info_file {
	my $filename = shift;
	my ($properties, @parts);
	my ($pkgname, $pkgversion, $pkgrevision, $pkgfullname, $pkgdestdir, $pkgpatchpath);
	my ($field, $value);
	my ($basepath, $expand, $buildpath);
	my $looks_good = 1;
	my $error_found = 0;

	if (Fink::Config::verbosity_level() == 3) {
		print "Validating package file $filename...\n";
	}
	
	# read the file properties
	$properties = &read_properties($filename);
	
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
	return unless ($looks_good);
	
	#
	# Now check for other mistakes
	#
	
	unless ("$pkgfullname.info" eq $filename) {
		print "Warning: File name should be $pkgfullname.info ($filename)\n";
		$looks_good = 0;
	}
	
	# License should always be specified, and must be one of the allowed set
	$value = $properties->{license};
	if ($value) {
		if (not $allowed_license_values{$value}) {
			print "Warning: Unknown license \"$value\". ($filename)\n";
			$looks_good = 0;
		}
	} elsif (not (defined($properties->{type}) and $properties->{type} eq "bundle")) {
		print "Warning: No license specified. ($filename)\n";
		$looks_good = 0;
	}

	# Check value of type field
	$value = lc $properties->{type};
	if ($value and not $allowed_type_values{$value}) {
		print "Error: Unknown value \"$value\"in field \"Type\". ($filename)\n";
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
			 if ($value =~ /\Q$pkgfullname\E/) {
				 print "Warning: Field \"$field\" contains full package name. Use %f instead. ($filename)\n";
				 $looks_good = 0;
			 } elsif ($value =~ /\Q$pkgversion\E/) {
				 print "Warning: Field \"$field\" contains package version. Use %v instead. ($filename)\n";
				 $looks_good = 0;
			 }
		}

		# Error if there is a source without a MD5
		if (($field eq "source" or $field =~ m/^source([2-9]|\d\d)$/)
				and not $properties->{$field."-md5"}) {
			print "Error: No MD5 checksum specified for \"$field\". ($filename)\n";
			$looks_good = 0;
		}
		
		# Warn if field is unknown
		unless ($known_fields{$field}
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
		if ($value =~ /\b\Q$pkgname\E\b/) {
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
				'b' => '.'
	};
	
	# Verify the patch file exists, if specified
	$value = $properties->{patch};
	if ($value) {
		$value = &expand_percent($value, $expand);
		if ($pkgpatchpath) {
			$value = $pkgpatchpath . "/" .$value;
		}
		unless (-f $value) {
			print "Error: can't find patchfile \"$value\"\n";
			$looks_good = 0;
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
# - ideas?
#
sub validate_dpkg_file {
	my $filename = shift;
	my @bad_dirs = ("$basepath/src/", "$basepath/man/", "$basepath/info/", "$basepath/doc/", "$basepath/libexec/", "$basepath/lib/locale/");
	my ($pid, $bad_dir);
	
	print "Validating .deb file $filename...\n";
	
	# Quick & Dirty solution!!!
	# This is a potential security risk, we should maybe filter $filename...
	$pid = open(DPKG_CONTENTS, "dpkg --contents $filename |") or die "Couldn't run dpkg: $!\n";
	while (<DPKG_CONTENTS>) {
		# process
		if (/([^\s]*)\s*([^\s]*)\s*([^\s]*)\s*([^\s]*)\s*([^\s]*)\s*\.([^\s]*)/) {
			$filename = $6;
			#print "$filename\n";
			next if $filename eq "/";
			if (not $filename =~ /^$basepath/) {
						print "Warning: File \"$filename\" installed outside of $basepath\n";
			} else {
				foreach $bad_dir (@bad_dirs) {
					# Directory from this list are not allowed to exist in the .deb.
					# The only exception is $basepath/src which may exist but must be empty
					if ($filename =~ /^$bad_dir/ and not $filename eq "$basepath/src/") {
						print "Warning: File installed into deprecated directory $bad_dir\n";
						print "					Offender is $filename\n";
						last;
					}
				}
			}
		}
	}
	close(DPKG_CONTENTS) or die "Error on close: $!\n";
}


### EOF
1;
