#
# Fink::Config class
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

package Fink::Config;
use Fink::Base;

use Fink::Services;

use strict;
use warnings;

BEGIN {
  use Exporter ();
  our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
  $VERSION = 1.00;
  @ISA         = qw(Exporter Fink::Base);
  @EXPORT      = qw();
  @EXPORT_OK   = qw($config $basepath $libpath $debarch);
  %EXPORT_TAGS = ( );   # eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

our ($config, $basepath, $libpath, $debarch);
$debarch = "darwin-powerpc";

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

  $self->SUPER::initialize();

  $config = $self;
  $basepath = $self->param("Basepath");
  $libpath = "$basepath/lib/fink";

  $self->{_queue} = [];
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

  $self->{lc $key} = $value;
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
    $values{lc $key} = $self->{lc $key};
    $values{lc $key} =~ s/\n/\n /gs;
  }

  $skip_cont = 0;
  open(IN,$path) or die "can't open configuration: $!";
  open(OUT,">$path.tmp") or die "can't write temporary file: $!";
  while (<IN>) {
    chomp;
    unless (/^\s*\#/) {
      if (/^([0-9A-Za-z_.\-]+)\:\s*(\S.*)$/) {
	if (exists $queue{lc $1}) {
	  next unless defined $queue{lc $1};
	  $_ = $queue{lc $1}.": ".$values{lc $1};
	  $queue{lc $1} = undef;
	  $skip_cont = 1;
	} else {
	  $skip_cont = 0;
	}
      } elsif (/^\s+(\S.*)$/) {
	next if $skip_cont;
      }
    }
    print OUT "$_\n";
  }
  close(IN);
  foreach $key (sort keys %queue) {
    next unless defined $queue{$key};
    print OUT $queue{$key}.": ".$values{$key}."\n";
  }
  close(OUT);

  unlink $path;
  rename "$path.tmp", $path;

  $self->{_queue} = [];
}

### EOF
1;
