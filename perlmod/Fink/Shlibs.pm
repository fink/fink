#
# Fink::Shlibs class
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

$|++;

package Fink::Shlibs;
use Fink::Base;
use Fink::Services qw(&print_breaking &version_cmp);
use Fink::Config qw($config $basepath);
use File::Find;
use Fcntl ':mode'; # for search_comparedb

use strict;
use warnings;


BEGIN {
  use Exporter ();
  our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
  $VERSION	= 1.00;
  @ISA		= qw(Exporter Fink::Base);
  @EXPORT	= qw();
  @EXPORT_OK	= qw(&get_shlibs);
  %EXPORT_TAGS	= ( );
}
our @EXPORT_OK;

our ($have_shlibs, @shlib_list, %shlib_hash, $shlib_db_outdated,
     $shlib_db_mtime);

$have_shlibs = 0;
@shlib_list = ();
%shlib_hash = ();
$shlib_db_outdated = 1;
$shlib_db_mtime = 0;

END { }				# module clean-up code here (global destructor)


### get shlibs depends line
sub get_shlibs {
  my $self = shift;
  my @filelist = @_;
  my ($depend, @depends, %SHLIBS);
  my $depline = "";

  @depends = $self->check_files(@filelist);

  foreach $depend (@depends) {
    if (length($depend) > 1) {
      $SHLIBS{$depend} = 1;
    }
  }

  $depline = join(', ', sort keys %SHLIBS);

  return $depline;
}

### check the files for depends
sub check_files {
  my $self = shift;
  my @files = @_;
  my ($file, @depends, $deb, $currentlib);

  # get a list of linked files to the pkg files
  foreach $file (@files) {
    chomp($file);
    open(OTOOL, "otool -L $file 2>/dev/null |") or die "can't run otool: $!\n";
      # need to drop all links to system libs and the first two lines
      while (<OTOOL>) {
        chomp();
        next if ("$_" =~ /\:/);                 # Nuke first line and errors
        $_ =~ s/\ \(.*$//;                      # Nuke the end
        $_ =~ s/^\s*//;
        $_ =~ s/\s*$//;
        ### This should drop any depends on it's self
        foreach $currentlib (@files) {
          if ($currentlib eq $_) {
            $_ = "";
          }
        }
        $deb = "";
        if (length($_) > 1) {
          $deb = $self->get_shlib($_);
          push(@depends, $deb);
        }
      }
    close (OTOOL);
  }

  print "DEBUG: before deduplication: ", join(', ', @depends), "\n";

  # this next bit does some really strange voodoo, I will try to
  # explain how it works.

  # first, there is a hash that contains a list of <package>,<operator>
  # tuples -- we use this for determining if a package is mentioned
  # multiple times.  We need to consider <package>,<operator> as a
  # unique key rather than just the package name because of cases like:
  #
  #   Depends: macosx (>= 10.1), macosx (<< 10.4)

  my $depvers = {};

  # next, there is an array that keeps a cooked version of the input
  # dependency list, with "<package> (<operator> <version>)" transformed
  # into "<package>,<operator>" -- this retains the order, as well as
  # any combinations of foo|bar|baz and so on, for the purposes of
  # recreating it later.

  my @newdeps;

  # so, first we go through each depend, turn it into an object that
  # contains versioning information and such, and then fills in the
  # $depvers hash and @newdeps array.

  for my $dep (@depends) {
    my @depobj = get_depobj($dep);
    my $name;

    # get_depobj() returns multiple entries when the source depend
    # is a foo|bar|baz style dependency (ie alternates)
    # for each one of these we want to strip it down to a
    # @newdeps-style value, and pump each of the individual deps
    # into the $depvers hash, then recreating the |'s with the
    # @newdeps values instead of the original package spec.

    if (@depobj > 1) {
      my @depnames;
      for my $obj (@depobj) {
        push(@depnames, $obj->{tuplename});
      }
      $name = join('|', @depnames);
      undef @depnames;
      for my $obj (@depobj) {
        $depvers = update_version_hash($depvers, $obj);
      }
    } else {
      $name = $depobj[0]->{tuplename};
      $depvers = update_version_hash($depvers, $depobj[0]);
    }

    # this will skip putting something into @newdeps if it's
    # already there (it has to match the <package>,<operator>
    # tuple exactly, not just the package name, to be
    # considered a duplicate)

    if (not grep($_ eq $name, @newdeps)) {
      push(@newdeps, $name);
    }
  }

  @depends = ();

  # now, we parse through the cooked data, and generate a new
  # dependency list, with duplicates removed because of the
  # skip above, and any matching version comparisons for a given
  # package should all be in parity

  for my $depspec (@newdeps) {
    if ($depspec =~ /\|/) {

      # if it's a multiple, we chop it up and transform each
      # part into it's "real" comparison, and then put it back
      # together and stick it on the new @depends

      my @splitdeps = split(/\|/, $depspec);

      for my $index (0..$#splitdeps) {

        if (defined $depvers->{$splitdeps[$index]}->{operator}) {
          # operator is defined if there was a version comparison
          $splitdeps[$index] = $depvers->{$splitdeps[$index]}->{name} . ' (' . $depvers->{$splitdeps[$index]}->{operator} . ' ' . $depvers->{$splitdeps[$index]}->{version} . ')';
        } else {
          $splitdeps[$index] = $depvers->{$splitdeps[$index]}->{name};
        }
      }
      push(@depends, join(' | ', @splitdeps));
    } else {

      # otherwise we just transform the single entry and push
      # it on the depends array

      if (defined $depvers->{$depspec}->{operator}) {
        # operator is defined if there was a version comparison
        push(@depends, $depvers->{$depspec}->{name} . ' (' . $depvers->{$depspec}->{operator} . ' ' . $depvers->{$depspec}->{version} . ')');
      } else {
        push(@depends, $depvers->{$depspec}->{name});
      }
    }
  }

  print "DEBUG: after deduplication: ", join(', ', @depends), "\n";
  return @depends;
}

### this is a scary subroutine to update the name,operator cache
### for handling duplicates -- it's just plain evil.  EVIL.  EEEEVIIIILLLL.
sub update_version_hash {
  my $hash   = shift;
  my $depobj = shift;

  if (exists $hash->{$depobj->{tuplename}}) {

    # if the name,operator pair exists in the dep cache hash
    if ($depobj->{operator} =~ /^==?$/ and
        $depobj->{version} ne $hash->{$depobj->{tuplename}}->{version}) {

      # can't have 2 different versions in an == comparison for the
      # same dependency (ie, Depends: macosx = 10.2-1, macosx = 10.3-1)

      warn "this package depends on ", $depobj->{name}, " = ", $depobj->{version}, " *and* ",
        $depobj->{name}, " = ", $hash->{$depobj->{tuplename}}->{version}, "!!!\n";

    } elsif (version_cmp($depobj->{version}, $depobj->{operator}, $hash->{$depobj->{tuplename}}->{version})) {

      # according to the operator, this new dependency is more "specific"
      $hash->{$depobj->{tuplename}} = $depobj;

    }

  } elsif (not defined $depobj->{operator}) {

    # $depobj contains an unversioned dependency, we have to
    # check if there's a more specific comparison already in
    # the dep cache

    my @matches = grep(/^$depobj->{name}\,/, keys %{$hash});

    if (@matches > 0) {

      # $depobj has no version dep, but a versioned dependency
      # already exists in the object cache -- take the first match
      # and use it instead of $depobj
      $hash->{$depobj->{tuplename}} = $hash->{$matches[0]};

      if (@matches > 1) {
        warn "more than one version comparison exists for ", $depobj->{name}, "!!!\n",
          "taking ", $hash->{$matches[0]}->{tuplename}, "\n";
      }

    } else {

      # $depobj isn't in the cache (versioned or not), just
      # put what we have in
      $hash->{$depobj->{tuplename}} = $depobj;

    }

  } elsif (grep(/^$depobj->{name}$/, keys %{$hash})) {

    # $depobj has a versioned dep, but an unversioned dependency
    # already exists in the object cache -- we need to update the
    # previous one

    $hash->{$depobj->{tuplename}} = $depobj;
    $hash->{$depobj->{name}}      = $depobj;

  } else {

    # if the tuple doesn't exist, we add it
    $hash->{$depobj->{tuplename}} = $depobj;

  }

  return $hash;
}

# get a dependency "object" (just a data structure with dep info)
sub get_depobj {
  my $depdef = shift;
  my @return;

  # this seems weird, but splitting when there isn't a "|" will
  # just give a 1-entry array, so it works even in the case there's
  # no multiple comparison (ie, "foo|bar")

  for my $dep (split(/\s*\|\s*/, $depdef)) {
    $dep =~ s/[\r\n\s]+/ /;
    $dep =~ s/^\s+//;
    $dep =~ s/\s+$//;
    my $depobj;
    if (my ($name, $operator, $version) = $dep =~ /^\s*(.+?)\s+\(([\<\>\=]+)\s+(\S+)\)\s*$/) {
      $depobj->{name}      = $name;
      $depobj->{operator}  = $operator;
      $depobj->{version}   = $version;
      $depobj->{tuplename} = $name . ',' . $operator;
    } else {
      $depobj->{name}      = $dep;
      $depobj->{operator}  = undef;
      $depobj->{version}   = '0-0';
      $depobj->{tuplename} = $dep;
    }
    push(@return, $depobj);
  }

  return @return;
}

### get package name
sub get_shlib {
  my $self = shift;
  my $lib = shift;
  my ($dep, $shlib, $count, $pkgnum, $vernum);

  $dep = "";

  foreach $shlib (keys %shlib_hash) {
    if ("$shlib" eq "$lib") {
      if ($shlib_hash{$shlib}->{total} > 1) {
        for ($count = 1; $count <= $shlib_hash{$shlib}->{total}; $count++) {
          $pkgnum = "package".$count;
          $vernum = "version".$count;
          $dep .= $shlib_hash{$shlib}->{$pkgnum}." (".$shlib_hash{$shlib}->{$vernum}.")";
          if ($count != $shlib_hash{$shlib}->{total}) {
            $dep .= " |";
          }
        }
      } else {
        $dep = $shlib_hash{$shlib}->{package1}." (".$shlib_hash{$shlib}->{version1}.")";
      }
    }
  }

  return $dep;
}

### make sure shlibs are available
sub require_shlibs {
  my $self = shift;

  if (!$have_shlibs) {
    $self->get_all_shlibs();
  }
}

### forget about all shlibs
sub forget_shlibs {
  my $self = shift;

  $have_shlibs = 0;
  @shlib_list = ();
  %shlib_hash = ();
  $shlib_db_outdated = 1;
}

### read list of shlibs, either from cache or files
sub get_all_shlibs {
  my $self= shift;
  my $time = time;
  my ($shlibname);
  my $db = "shlibs.db";

  $self->forget_shlibs();
	
  # If we have the Storable perl module, try to use the package index
  if (-e "$basepath/var/db/$db") {
    eval {
      require Storable; 

      # We assume the DB is up-to-date unless proven otherwise
      $shlib_db_outdated = 0;
		
      # Unless the NoAutoIndex option is set, check whether we should regenerate
      # the index based on its modification date.
      if (not $config->param_boolean("NoAutoIndex")) {
        $shlib_db_mtime = (stat("$basepath/var/db/$db"))[9];

        if (((lstat("$basepath/etc/fink.conf"))[9] > $shlib_db_mtime)
            or ((stat("$basepath/etc/fink.conf"))[9] > $shlib_db_mtime)) {
          $shlib_db_outdated = 1;
        } else {
          $shlib_db_outdated =
            &search_comparedb( "$basepath/var/lib/dpkg/info" );
        }
      }
			
      # If the index is not outdated, we can use it, and thus safe a lot of time
      if (not $shlib_db_outdated) {
        %shlib_hash = %{Storable::retrieve("$basepath/var/db/$db")};
      }
    }
  }
	
  # Regenerate the DB if it is outdated
  if ($shlib_db_outdated) {
    $self->update_shlib_db();
  }

  $have_shlibs = 1;

  my ($shlibtmp);
  foreach $shlibtmp (keys %shlib_hash) {
    push @shlib_list, $shlib_hash{$shlibtmp};
  }

  print "Information about ".($#shlib_list+1)." shlibs read in ",
    (time - $time), " seconds.\n\n";
}

### scan for info files and compare to $db_mtime
sub search_comparedb {
  my $path = shift;
  my (@files, $file, $fullpath, @stats);

  opendir(DIR, $path) || die "can't opendir $path: $!";
    @files = grep { !/^[\.#]/ } readdir(DIR);
  closedir DIR;

  foreach $file (@files) {
    $fullpath = "$path/$file"; 

    if (-d $fullpath) {
      next if $file eq "CVS";
      return 1 if (&search_comparedb($fullpath));
    } else {
      next if !(substr($file, length($file)-7) eq ".shlibs");
      @stats = stat($fullpath);
      return 1 if ($stats[9] > $shlib_db_mtime);
    }
  }
	
  return 0;
}

### read shlibs and update the database, if needed and we are root
sub update_shlib_db {
  my $self = shift;
  my ($dir);
  my $db = "shlibs.db";

  # read data from descriptions
  print "Reading shlib info...\n";
  $dir = "$basepath/var/lib/dpkg/info";
  $self->scan($dir);

  eval {
    require Storable; 
    if ($> == 0) {
      print "Updating shlib index... ";
      unless (-d "$basepath/var/db") {
        mkdir("$basepath/var/db", 0755) ||
          die "Error: Could not create directory $basepath/var/db";
      }
      Storable::store (\%shlib_hash, "$basepath/var/db/$db");
      print "done.\n";
    } else {
      &print_breaking( "\nFink has detected that your shlib cache is out" .
        " of date and needs an update, but does not have privileges to" .
         " modify it. Please re-run fink as root," .
	" for example with a \"sudo fink-depends index\" command.\n" );
    }
  };
  $shlib_db_outdated = 0;
}

### scan for shlibs
sub scan {
  my $self = shift;
  my $directory = shift;
  my (@filelist, $wanted);
  my ($filename, $shlibname, $compat, $package, $line, @lines);

  return if not -d $directory;

  # search for .shlibs files
  @filelist = ();
  $wanted =
    sub {
      if (-f and not /^[\.#]/ and /\.shlibs$/) {
        push @filelist, $File::Find::fullname;
      }
    };
  find({ wanted => $wanted, follow => 1, no_chdir => 1 }, $directory);

  foreach $filename (@filelist) {
    open(SHLIB, $filename) or die "can't open $filename: $!\n";
      while(<SHLIB>) {
        @lines = split(/\n/, $_);
        foreach $line (@lines) {
          chomp($line);
          $line =~ s/^\s*//;
          $line =~ s/\s*$//;
          if ($line =~ /^(.+) ([.0-9]+) (.*)$/) {
            $shlibname = $1;
            $compat = $2;
            $package = $3;

            unless ($shlibname) {
              print "No lib name in $filename\n";
              next;
            }
            unless ($compat) {
              print "No lib compatability version for $shlibname\n";
              next;
            }
            unless ($package) {
              print "No owner package(s) for $shlibname\n";
              next;
            }

            $self->inject_shlib($shlibname, $compat, $package);
          }
        }
      }
    close(SHLIB);
  }
}

### create the hash
sub inject_shlib {
  my $self = shift;
  my $shlibname = shift;
  my $compat = shift;
  my $package = shift;
  my (@packages, $pkg, $counter, $pkgnum, $vernum);

  $shlib_hash{$shlibname}->{compat} = $compat;
  if ($package =~ /\|/) {
    @packages = split(/\|/, $package);
    $counter = 0;
    foreach $pkg (@packages) {
      print "DEBUG: $pkg\n";
      $counter++;
      if ($pkg =~ /(.+) \((.+)\)/) {
        $pkgnum = "package".$counter;
        $vernum = "version".$counter;;
        $shlib_hash{$shlibname}->{$pkgnum} = $1;
        $shlib_hash{$shlibname}->{$vernum} = $2;
      }
      $shlib_hash{$shlibname}->{total} = $counter;
    }
  } else {
    if ($package =~ /(.+) \((.+)\)/) {
      $shlib_hash{$shlibname}->{package1} = $1;
      $shlib_hash{$shlibname}->{version1} = $2;
      $shlib_hash{$shlibname}->{total} = 1;
    }
  }
}

### EOF
1;
