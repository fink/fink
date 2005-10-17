# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Chekcsum module
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2005 The Fink Package Manager Team
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
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA      02111-1307, USA.
#

package Fink::Checksum;

use Fink::Config qw($config);
use Fink::Services qw(&find_subpackages);
use UNIVERSAL qw(isa);

BEGIN {
        use Exporter ();
        our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
        $VERSION         = ( qw$Revision$ )[-1];
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

  ### a module implementing a notifier type

  # all notifier modules must reside under the Fink::Checksum namespace
  package Fink::Checksum::ChecksumClass;

  # all notifier modules must be subclasses of Fink::Checksum
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
    my $output = $class->get_output('/some/command', $filename);
    if ($output =~ /(some-matching-regex)/) {
      return $1;
    } else {
      die "could not get checksum for $filename\n";
    }
  }

=head1 METHODS

=over 4

=item new(E<PluginType>) - get a new checksum object

Get a new checksum object, specifying the checksum method to use.

Checksum modules must provide a new() method that returns a blessed
ref for their object.

=cut

sub new {
	my $class = shift;

	my $plugin = shift || die "no checksum plugin type specified!\n";

	my $self;

	eval "require Fink::Checksum::$plugin";
	eval "\$self = Fink::Checksum::$plugin->new()";

	unless (isa $self, "Fink::Checksum") {
		die "unable to load '$plugin' checksum module\n";
	}

	return $self;
}

sub get_checksum {
	die "no checksum module loaded\n";
}

sub get_output {
	my $class = shift;

	my ($return, $pid);
	my @command = @_;

	$pid = open(COMMAND, "@command |") or die "Couldn't run @command: $!\n";
	{
		local $/ = undef;
		$return = <COMMAND>;
	}
	close(COMMAND) or die "Error on closing pipe @command: $!\n";

	return $return;
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
		$plugins{$plugname}{enabled} = 1 if defined $plugname->new();
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
		print(" " x 32, $about[3], "\n") if ($about[3] ne "");
	}
}

=back

=cut

1;
