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
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA	 02111-1307, USA.
#

package Fink::Config;
use Fink::Base;
use Fink::Services;


use strict;
use warnings;

require Exporter;

our @ISA	 = qw(Exporter Fink::Base);
our @EXPORT_OK	 = qw($config $basepath $libpath $debarch $buildpath
                      $distribution
                      get_option set_options verbosity_level
                     );
our $VERSION	 = 1.00;


our ($config, $basepath, $libpath, $distribution, $buildpath);
my $_arch = Fink::Services::get_arch();
our $debarch = "darwin-$_arch";

my %options = ();



=head1 NAME

Fink::Config - Read/write the fink configuration

=head1 SYNOPSIS

  use Fink::Config;
  my $config = Fink::Config->new_with_path($config_file);

  my $value = $config->param($key);
  $config->set_param($key, $value);
  $config->save;

=head1 DESCRIPTION

A class representing the fink configuration file as well as any command
line options.

Fink::Config inherits from Fink::Base.


=head2 Constructors

=over 4

=item new

=item new_from_properties

Inherited from Fink::Base.

=item new_with_path

  my $config = Fink::Config->new_with_path($config_file);

Reads a fink.conf file into a new Fink::Config object and initializes
Fink::Config globals from it.

=cut

sub new_with_path {
	my($proto, $path) = @_;
	my $class = ref($proto) || $proto;

	my $properties = Fink::Services::read_properties($path);
	my $self = $class->new_from_properties($properties);
	$self->{_path} = $path;

	return $self;
}


=begin private

=item initialize

  $self->initialize;

Initialize Fink::Config globals.  To be called from any constructors.

=end private

=cut

sub initialize {
	my $self = shift;

	$self->SUPER::initialize();

	$config = $self;
	$basepath = $self->param("Basepath");
	die "Basepath not set in config file \"".$self->{_path}."\"!\n"
		unless (defined $basepath and $basepath);

	$buildpath = $self->param_default("Buildpath", "$basepath/src");

	$libpath = "$basepath/lib/fink";
	$distribution = $self->param("Distribution");
	if (not defined $distribution or ($distribution =~ /^\s*$/)) {
		die "Distribution not set in config file \"".$self->{_path}."\"!\n";
	}

	$self->{_queue} = [];
}

=back

=head2 Configuration queries

=over 4

=item get_path

  my $path = $config->get_path;

Returns the path to the configuration file which $config represents.

=cut

sub get_path {
	my $self = shift;

	return $self->{_path};
}


=item get_treelist

  my @trees = $config->get_treelist;

Returns the Trees config value split into a handy list.

=cut

sub get_treelist {
	my $self = shift;

	return grep !m{^(/|.*\.\./)},
               split /\s+/, 
                 $self->param_default("Trees", 
                         "local/main stable/main stable/bootstrap"
                 );
}

=item param

=item param_default

=item param_boolean

=item has_param

=item set_param

Inherited from Fink::Base.

=cut

sub set_param {
    my $self = shift;
    my $key  = shift;
    $self->SUPER::set_param($key, @_);
    push @{$self->{_queue}}, $key;
}

=item save

  $config->save;

Saves any changes made with set_param() to the config file.

=cut

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
		unless (/^\s*\#/) {		# leave comments alone
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

=back

=head2 Exported Functions

These functions are exported only on request

=over 4

=item set_options

  set_options({ key1 => val1, key2 => val2, ...});

Sets global configuration options, mostly used for command line options.

=cut

sub set_options {
	my $hashref = shift;

	my ($key, $value);
	while (($key, $value) = each %$hashref) {
		$options{lc $key} = $value;
	}
}

=item get_option

  my $value = get_option($key);
  my $value = get_option($key, $default_value);

Gets a global configuration option.  If the $key was never set,
$default_value is returned.

=cut

sub get_option {
	my $option = shift;
	my $default = shift || 0;

	if (exists $options{lc $option}) {
		return $options{lc $option};
	}
	return $default;
}

=item verbosity_level

  my $level = verbosity_level;

Determine the current verbosity level. This is affected by the
--verbose and --quiet command line options as well as by the "Verbose"
setting in fink.conf.

=cut

sub verbosity_level {
	my $verblevel = $config->param_default("Verbose", 1);
	my $verbosity = get_option("verbosity");

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

=back

=head1 SEE ALSO

L<Fink::Base>

=cut

1;
