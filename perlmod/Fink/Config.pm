#
# Fink::Config class
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
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#

package Fink::Config;
use Fink::Base;
use Fink::Services;

use POSIX qw(uname);

use strict;
use warnings;

BEGIN {
  use Exporter ();
  our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
  $VERSION = 1.00;
  @ISA         = qw(Exporter Fink::Base);
  @EXPORT      = qw();
  @EXPORT_OK   = qw($config $basepath $libpath $debarch $darwin_version $macosx_version $distribution
                    &get_option &set_options &verbosity_level $buildpath);
  %EXPORT_TAGS = ( );   # eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

our ($config, $basepath, $libpath, $debarch, $darwin_version, $macosx_version, $distribution, $buildpath);
$debarch = "darwin-powerpc";

my %globals = ();

END { }       # module clean-up code here (global destructor)


### construct from path

sub new_with_path {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $path = shift;
  my ($properties);

  my $self = {};
  bless($self, $class);

  $properties = Fink::Services::read_properties($path);

  my ($key, $value);
  while (($key, $value) = each %$properties) {
    $self->{$key} = $value
      unless substr($key,0,1) eq "_";
  }

  $self->{_path} = $path;

  $self->initialize();

  return $self;
}

### self-initialization

sub initialize {
  my $self = shift;
  my ($dummy);

  $self->SUPER::initialize();

  $config = $self;
  $basepath = $self->param("Basepath");
  die "Basepath not set in config file \"".$self->{_path}."\"!\n"
    unless (defined $basepath and $basepath);

  $buildpath = $config->param_default("Buildpath", "$basepath/src");

  $libpath = "$basepath/lib/fink";
  $distribution = $self->param("Distribution");

  $self->{_queue} = [];

  # determine the kernel version
  ($dummy,$dummy,$darwin_version) = uname();

  # Now the Mac OS X version
  $macosx_version = 0;
  if (-x "/usr/bin/sw_vers") {
	$dummy = open(SW_VERS, "/usr/bin/sw_vers |") or die "Couldn't determine system version: $!\n";
	while (<SW_VERS>) {
	  chomp;
	  if (/(ProductVersion\:)\s*([^\s]*)/) {
		$macosx_version = $2;
		last;
	  }
	}
  }
}


### get path

sub get_path {
  my $self = shift;

  return $self->{_path};
}

### get list of trees

sub get_treelist {
  my $self = shift;

  return split(/\s+/, $self->param_default("Trees", "local/main stable/main stable/bootstrap"));
}

### set parameter

sub set_param {
  my $self = shift;
  my $key = shift;
  my $value = shift;

  if (not defined($value) or $value eq "") {
    delete $self->{lc $key};
  } else {
    $self->{lc $key} = $value;
  }
  push @{$self->{_queue}}, $key;
}

### save changes

sub save {
  my $self = shift;
  my $path = $self->{_path};
  my ($key, $skip_cont, %queue, %values);

  %queue = ();
  %values = ();
  foreach $key (@{$self->{_queue}}) {
    $queue{lc $key} = $key;
    if (exists $self->{lc $key} and defined($self->{lc $key})) {
      $values{lc $key} = $self->{lc $key};
    } else {
      $values{lc $key} = "";
    }
    $values{lc $key} =~ s/\n/\n /gs;
  }

  $skip_cont = 0;
  open(IN,$path) or die "can't open configuration: $!";
  open(OUT,">$path.tmp") or die "can't write temporary file: $!";
  while (<IN>) {
    chomp;
    unless (/^\s*\#/) {   # leave comments alone
      if (/^([0-9A-Za-z_.\-]+)\:.*$/) {
	if (exists $queue{lc $1}) {
	  # skip continuation lines
	  $skip_cont = 1;
	  # make sure we only write it once
	  next unless defined($queue{lc $1});
	  $key = $queue{lc $1};
	  $queue{lc $1} = undef;
	  # write nothing for empty values
	  next if $values{lc $1} eq "";
	  # else write the new setting
	  $_ = $key.": ".$values{lc $1};
	} else {
	  # keep this setting and its continuation lines
	  $skip_cont = 0;
	}
      } elsif (/^\s+(\S.*)$/) {
	# it's a continuation line
	next if $skip_cont;
      }
    }
    print OUT "$_\n";
  }
  close(IN);
  foreach $key (sort keys %queue) {
    # get the keys we have not seen yet
    next unless defined $queue{$key};
    # write nothing for empty values
    next if $values{$key} eq "";
    # add the setting at the end of the file
    print OUT $queue{$key}.": ".$values{$key}."\n";
  }
  close(OUT);

  # put the temporary file in place
  unlink $path;
  rename "$path.tmp", $path;

  $self->{_queue} = [];
}

### inject run-time options

sub set_options {
  my $hashref = shift;

  my ($key, $value);
  while (($key, $value) = each %$hashref) {
    $globals{lc $key} = $value;
  }
}

### retrieve a run-time option

sub get_option {
  my $option = shift;
  my $default = shift || 0;

  if (exists $globals{lc $option}) {
    return $globals{lc $option};
  }
  return $default;
}

### determine the current verbosity level. This is affected by the
### --verbose and --quiet command line options as well as by the
### "Verbose" setting in fink.conf

sub verbosity_level {
  my ($verbosity, $verblevel);

  $verblevel = $config->param_default("Verbose", 3);
  $verbosity = get_option("verbosity");

  if ($verbosity != -1 && ($verbosity == 3 || $verblevel eq "3" || $verblevel eq "true" || $verblevel eq "high")) {
    ### Sets Verbose mode to Full
    $verbosity = 3;
  } elsif ($verbosity != -1 && $verblevel eq "2" || $verblevel eq "medium") {
    ### Sets Verbose mode to download and tarballs
    $verbosity = 2;
  } elsif ($verbosity != -1 && $verblevel eq "1" || $verblevel eq "low") {
    ### Sets Verbose mode to download
    $verbosity = 1;
  } else {
    ### Sets Verbose mode to none
    $verbosity = 0;
  }
  return $verbosity;
}


### EOF
1;
