#
# Fink::Validation module
# Copyright (c) 2001 Max Horn
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#

package Fink::Validation;

use Fink::Services qw(&read_properties &expand_percent);
use Fink::Config qw($config $basepath);

use strict;
use warnings;

BEGIN {
  use Exporter ();
  our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
  $VERSION = 1.00;
  @ISA         = qw(Exporter);
  @EXPORT      = qw();
  @EXPORT_OK   = qw(&validate_info_file &validate_dpkg_file);
  %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

our @boolean_fields = qw(Essential NoSourceDirectory UpdateConfigGuess UpdateLibtool); # add NoSet* !
our @obsolete_fields = qw(Comment CommentPort CommenStow UseGettext);
our @name_version_fields = qw(Source SourceDirectory SourceN SourceNExtractDir Patch);
out @type_field_values = qw(nosource bundle perl)
our @recommended_field_order =
  qw(
    Package
    Version
    Revision
    Type
    Maintainer
    Depends
    BuildDepends
    Provides
    Conflicts
    Replaces
    Recommends
    Suggests
    Enhances
    Pre-Depends
    Essential
    Source
    SourceDirectory
    NoSourceDirectory
    Source*
    Source*ExtractDir
    UpdateConfigGuess
    UpdateConfigGuessInDirs
    UpdateLibtool
    UpdateLibtoolInDirs
    UpdatePoMakefile
    Patch
    PatchScript
    ConfigureParams
    CompileScript
    InstallScript
    Set*
    NoSet*
    PreInstScript
    PostInstScript
    PreRmScript
    PostRmScript
    ConfFiles
    InfoDocs
    DaemonicFile
    DaemonicName
    Description
    DescDetail
    DescUsage
    DescPackaging
    DescPort
    Homepage
    License
  );

END { }       # module clean-up code here (global destructor)



# Should check/verifies the following in .info files:
#   + the filename matches %f.info
#   + patch file is present
#   + all required fields are present
#   + warn if obsolete fields are encountered
#   + warn about missing Description/Maintainer fields
#   + warn about overlong Description fields
#   + warn if boolean fields contain bogus values
#   + warn if fields seem to contain the package name/version, and suggest %n/%v should be used
#     (excluded from this are fields like Description, Homepage etc.)
#
# TODO: Optionally, should sort the fields to the recommended field order
#   - warn if unknown fields are encountered
#   - error if format is violated (e.g. bad here-doc)
#   - warn if /sw is hardcoded somewhere
#   - if type is bundle/nosource - warn about usage of "Source" etc.
# ... other things, make suggestions ;)
#
sub validate_info_file {
  my $filename = shift;
  my ($properties, @parts);
  my ($pkgname, $pkgversion, $pkgrevision, $pkgfullname, $pkgdestdir, $pkgpatchpath);
  my ($field, $value);
  my ($basepath, $expand);
  my $looks_good = 1;

  print "Validating package file $filename...\n";
  
  # read the file properties
  $properties = &read_properties($filename);
  
  # determine the base path
  $basepath = $config->param("basepath");

  $pkgname = $properties->{package};
  $pkgversion = $properties->{version};
  $pkgrevision = $properties->{revision};
  $pkgfullname = "$pkgname-$pkgversion-$pkgrevision";
  $pkgdestdir = "$basepath/src/root-".$pkgfullname;
  
  @parts = split(/\//, $filename);
  $filename = pop @parts;   # remove filename
  $pkgpatchpath = join("/", @parts);

  unless ($pkgname) {
    print "Error: No package name in $filename\n";
    return;
  }
  unless ($pkgversion) {
    print "Error: No version number in $filename\n";
    return;
  }
  unless ($pkgrevision) {
    print "Error: No revision number or revision number is 0 in $filename\n";
    return;
  }
  if ($pkgname =~ /[^-.a-z0-9]/) {
    print "Error: Package name may only contain lowercase letters, numbers, '.' and '-'\n";
    return;
  }
  unless ($properties->{maintainer}) {
    print "Error: No maintainer specified in $filename\n";
    $looks_good = 0;
  }

  unless ("$pkgfullname.info" eq $filename) {
    print "Warning: File name should be $pkgfullname.info but is $filename\n";
    $looks_good = 0;
  }
  
  # Check whether any of the following fields contains the package name or version,
  # and suggest that %f/%n/%v be used instead
  foreach $field (@name_version_fields) {
    $value = $properties->{lc $field};
    if ($value) {
      if ($value =~ /$pkgfullname/) {
        print "Warning: Field \"$field\" contains full package name. Use %f instead.\n";
        $looks_good = 0;
      } else {
#       if ($value =~ /$pkgname/) {
#         print "Warning: Field \"$field\" contains package name. Use %n instead.\n";
#         $looks_good = 0;
#       }
        if ($value =~ /$pkgversion/) {
          print "Warning: Field \"$field\" contains package version. Use %v instead.\n";
          $looks_good = 0;
        }
      }
    }
  }
  
  # Check if any obsolete fields are used
  foreach $field (@obsolete_fields) {
    if ($properties->{lc $field}) {
      print "Warning: Field \"$field\" is obsolete.\n";
      $looks_good = 0;
    }
  }

  # Boolean fields
  foreach $field (@boolean_fields) {
    $value = $properties->{lc $field};
    if ($value) {
      unless ($value =~ /^\s*(true|yes|on|1|false|no|off|0)\s*$/) {
        print "Warning: Boolean field \"$field\" contains suspicious value \"$value\".\n";
        $looks_good = 0;
      }
    }
  }
  
  # Warn for missing / overlong package descriptions
  $value = $properties->{description};
  unless ($value) {
    print "Warning: No package description supplied.\n";
    $looks_good = 0;
  }
  elsif (length($value) > 45) {
    print "Warning: Length of package description exceeds 45 characters.\n";
    $looks_good = 0;
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
  
  if ($looks_good) {
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
      #print "$6\n";
      foreach $bad_dir (@bad_dirs) {
        if ($6 =~ /^$bad_dir/) {
          print "WARNING: File installed into deprecated directory $bad_dir\n";
          print "         Offender is $filename\n";
          last;
        }
      }
    }
  }
  close(DPKG_CONTENTS) or die "Error on close: $!\n";
}


### EOF
1;
