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
use Fink::Services qw(&print_breaking);
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

#  $self->require_shlibs();

  @depends = $self->check_files(@filelist);

  foreach $depend (@depends) {
    $SHLIBS{$depend} = 1;
  }

  $depline = join(', ', sort keys %SHLIBS);

  return $depline;
}

### check the files for depends
sub check_files {
  my $self = shift;
  my @files = @_;
  my ($file, @depends, $deb, $vers);

  # get a list of linked files to the pkg files
  foreach $file (@files) {
    chomp($file);
    open(OTOOL, "otool -L $file 2>/dev/null |") or die "can't run otool: $!\n";
      # need to drop all links to system libs and the first two lines
      while (<OTOOL>) {
        chomp();
        next if ("$_" =~ /\:/);                 # Nuke first line and errors
        if ($_ =~ /compatibility version ([.0-9]+)/) {
          $vers = $1;
        }
        $_ =~ s/\ \(.*$//;                      # Nuke the end
        $_ =~ s/^[\s|\t]+//;
        $_ =~ s/[\s|\t]+$//;
        $deb = "";
        if (length($_) > 1) {
          $deb = $self->get_shlib($_);
          if (length($deb) > 1) {
            push(@depends, $deb);
          } else {
            push(@depends, "$_ (>= $vers)");
          }
        }
      }
    close (OTOOL);
  }

  return @depends;
}

### get package name
sub get_shlib {
  my $self = shift;
  my $lib = shift;
  my ($dep, $shlib);

  $dep = "";

  foreach $shlib (keys %shlib_hash) {
    if ("$shlib" eq "$lib") {
      $dep = $shlib_hash{$shlib}->{packages};
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
          $line =~ s/^[\s|\t]+//;
          $line =~ s/[\s|\t]+$//;
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

  $shlib_hash{$shlibname}->{compat} = $compat;
  $shlib_hash{$shlibname}->{packages} = $package;
}

### EOF
1;
