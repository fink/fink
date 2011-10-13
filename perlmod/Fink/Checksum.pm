# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Checksum module
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2005-2011 The Fink Package Manager Team
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
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110, USA.
#

package Fink::Checksum;

use Fink::Config qw($config);
use Fink::Services qw(&find_subpackages);

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
	$VERSION         = 1.00;
	@ISA             = qw(Exporter);
	@EXPORT          = qw();
	%EXPORT_TAGS = ( );                     # eg: TAG => [ qw!name1 name2! ],

	# your exported package globals go here,
	# as well as any optionally exported functions
	@EXPORT_OK       = qw();
}

END { }                         # module clean-up code here (global destructor)

=head1 NAME

Fink::Checksum - generate checksums of files

=head1 DESCRIPTION

Fink::Checksum is a pluggable system for computing checksums of various
file types.

=head1 SYNOPSIS

  use Fink::Checksum;

  my $checksum = Fink::Checksum->new('MD5');
  my $md5 = $checksum->get_checksum($filename);


  ### a module implementing a checksum type

  # all checksum modules must reside under the Fink::Checksum namespace
  package Fink::Checksum::ChecksumClass;

  # all checksum modules must be subclasses of Fink::Checksum
  use Fink::Checksum;
  @ISA = qw(Fink::Checksum);

  sub new {
    my class = shift;
    return bless {}, $class;
  }

  sub about {
    my @about = ("ChecksumClass", "1.1", "Short Description", "dep-package");
	return wantarray? @about : \@about;
  }

  sub get_checksum {
    my $class = shift;
    my $filename = shift;
    my $output = `run-some-command`;
    if ($output =~ /(some-matching-regex)/) {
      return $1;
    } else {
      die "could not get checksum for $filename\n";
    }
  }

=head1 METHODS

=over 4

=item new(B<PluginType>) - get a new checksum object

Get a new checksum object, specifying the checksum method to use.

Checksum modules must provide a new() method that returns a blessed
ref for their object.

=cut

sub new {
	my $class = shift;

	my $plugin = shift || "MD5";

	my $self;

	if ($plugin) {
		eval "require Fink::Checksum::$plugin";
		eval "\$self = Fink::Checksum::$plugin->new()";
	}

	if ($@) {
		die "unable to load checksum plugin ($plugin): $@\n";
	} elsif (! eval { $self->isa("Fink::Checksum") }) {
		die "unknown checksum plugin: $plugin\n";
	}

	return $self;
}

=item get_checksum($filename) - get the checksum for a file

Get the checksum for a given file, based on the Fink::Checksum::B<OBJ>
object which represents a given algorithm.

This method cannot be used directly from a Fink::Checksum object,
it is designed to be overridden in the subclass.

=cut

sub get_checksum {
	die "no checksum module loaded\n";
}

=item $class->get_all_checksums($filename) - get all possible checksums for a file

This class method returns a ref to a hash of algorithm=>checksum pairs
for all available algorithms for the given $filename.

=cut

sub get_all_checksums {
	my $class = shift;
	my $filename = shift;

	my %checksums;

	foreach my $algorithm ( find_subpackages($class) ) {
		$algorithm =~ s/${class}:://;
		eval {
			my $plugin = Fink::Checksum->new($algorithm);
			$checksums{$algorithm} = $plugin->get_checksum($filename) if defined $plugin;
		};
	}

	return \%checksums;
}

=item $class->validate($filename, $checksum, [$algorithm]) - validate a file

Returns a boolean indicating whether the $checksum for file $filename
is correctw hen using $algorithm.

If $checksum is specified in the format used in the Source-Checksum
field (ie, the MD5(string) format), then $algorithm will be detected
automatically.

=cut

sub validate {
	my $class     = shift;
	my $filename  = shift;
	my $checksum  = shift;
	my $algorithm = shift;

	($algorithm, $checksum) = $class->parse_checksum($checksum, $algorithm);

	#print "validating $algorithm($checksum) for $filename\n";
	my $plugin = Fink::Checksum->new($algorithm);
	my $file_checksum = $plugin->get_checksum($filename);

	if ($file_checksum eq $checksum) {
		return 1;
	}
	return undef;
}

=item $class->parse_checksum($checksum, [$algorithm]) - tease apart different syntaxes

This class method returns a (algorithm=>checksum) pair. If the passed
$checksum has the form of ALGORITHM(CHECKSUM), the ALGORITHM and
CHECKSUM components are returned separately. If the passed $checksum
is just a checksum string, $algorithm is used as the algorithm. If the
algorithm is not contained in the passed $checksum and no $algorithm
is passed, "MD5" is returned as the algorithm.

=cut

sub parse_checksum {
	my $class = shift;
	my $checksum = shift;
	my $algorithm = shift || 'MD5';

	if (defined $checksum and $checksum =~ /^\s*(\w+)\((\w+)\)\s*$/) {
		# first try to pull apart ALGORITHM(CHECKSUM)
		($algorithm, $checksum) = ($1, $2);
	}

	return ($algorithm=>$checksum);
}

=item list_plugins() - list the available checksum plugins

This method will list the available checksum plugins for
Fink::Checksum to use.

=cut

sub list_plugins {
	my $self = shift;
	
	my %plugins;
	foreach my $plugname ( find_subpackages(__PACKAGE__) ) {
		$plugins{$plugname}{about} = $plugname->about();
		eval {
			$plugins{$plugname}{enabled} = 1 if defined $plugname->new();
		};
	}

	for my $key (sort keys %plugins) {
		my ($shortname) = $key =~ /^.*\:\:([^\:]*)$/;

		my $installed = "";
		$installed = " i " if ($plugins{$key}->{'enabled'});

		my @about = @{$plugins{$key}->{'about'}};
		for (0..3) {
			$about[$_] = "" if (not defined $about[$_]);
		}

		$about[2] = substr($about[2], 0, 44);
		printf("%3s %-15.15s %-11.11s %s\n", $installed, $shortname, $about[1], $about[2]);
	}
}

=back

=cut

1;
