# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Notify module
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2011 The Fink Package Manager Team
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

package Fink::Notify;
use warnings;
use strict;

use Fink::Config	qw($config);
use Fink::Services	qw(&find_subpackages);

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

Fink::Notify - functions for notifying the user out-of-band

=head1 DESCRIPTION

Fink::Notify is a pluggable system for notifying users of events that
happen during package installation/removal.

=head1 SYNOPSIS

  ### a program that generates notifications

  use Fink::Notify;

  my $notifier = Fink::Notify->new('Growl');
  $notifier->notify(
    event       => 'finkPackageInstallationPassed',
    description => 'Installation of package [foo] passed!',
  );

  ### a module implementing a notifier type

  # all notifier modules must reside under the Fink::Notify namespace
  package Fink::Notify::NotifierClass;

  # all notifier modules must be subclasses of Fink::Notifier
  use Fink::Notifier;
  @ISA = qw(Fink::Notifier);

  sub new {
    my class = shift;
    return bless {}, $class;
  }

  sub about {
    my @about = ("NotifierClass", "1.1", "Short Description", "URL");
	return wantarray? @about : \@about;
  }

  sub do_notify {
    my $self = shift;
    my %args = @_;

    print "Alert: $args{event}: $event{title}\n";
    print "\t$args{description}\n" if defined $args{description};

    return 1;
  }

=head1 METHODS

=over 4

=cut

# Find the list of Notify plugins, as package names
{
	my $plugins;
	
	sub _plugins {
		$plugins = [ find_subpackages(__PACKAGE__) ] unless defined $plugins;
		return @$plugins;
	}
}

=item new([PluginType]) - get a new notifier object

Get a new notifier object, optionally specifying the notification
plugin to use.  If one is not specified, it will use the default
plugin specified in the user's fink.conf.  The returned object is
that of the specific notifier itself, not the class of the new() here.

Notifier modules must provide a new() method that returns a blessed
ref for their object.

=cut

sub new {
	my $class = shift;
	my $self = bless [], $class;

	my $plugins = shift || $config->param_default('NotifyPlugin', 'Growl');
	my @plugins = split / /, $plugins;
	
	# Deal gracefully with case problems in plugin specification
	my %fixedcase = map { lc $_ => $_ } _plugins;

	for my $plugin (@plugins) {
		my $package = $fixedcase{lc "Fink::Notify::$plugin"};
		unless ($package) {
			print STDERR "Could not find notifier '$plugin'! Please fix your "
				. "fink.conf.\n";
			next;
		}
		
		my $instance;
		eval "require $package";
		eval { $instance = $package->new };
		next unless eval { $instance->isa("Fink::Notify") };
		
		push @$self, $instance;
	}
	return $self;
}

=item events() - the list of supported events

The default events are:

=over 4

=item * finkPackageBuildPassed - build phase has completed

=item * finkPackageBuildFailed - build phase has failed

=item * finkPackageInstallationPassed - install phase has completed

=item * finkPackageInstallationFailed - install phase has failed

=item * finkPackageRemovalPassed - deactivation phase has completed

=item * finkPackageRemovalFailed - deactivation phase has failed

=item * finkDonePassed - fink is done running and is exiting

=item * finkDoneFailed - fink is done running and is exiting non-zero

=back

Notifier modules may supply an alternate list of supported events by
providing their own events() method.

Event names should follow the form [origin][EventType][Status], where:

=over 4

=item * origin

The program that generated the notification.

=item * EventType

The program's event, action, or mode leading to the notification.

=item * Status

Either "Passed" or "Failed", indicating the result of the
event, action, or mode.

=back

=cut

our @events = qw(
	finkPackageBuildPassed
	finkPackageBuildFailed
	finkPackageInstallationPassed
	finkPackageInstallationFailed
	finkPackageRemovalPassed
	finkPackageRemovalFailed
	finkDonePassed
	finkDoneFailed
);

sub events {
	my @eventlist = @events;  # return a copy so caller can't modify original
	return wantarray? @eventlist : \@eventlist;
}


=item notify(%args) - notify the user of an event (public interface)

  $notifier->notify(
    event => 'finkPackageInstallationFailed',
    title => 'Holy cow!  Something bad happened!',
    description => 'Something really bad has occurred, while installing foo.',
  );

Supported Arguments:

=over 4

=item * event

The event name to notify on: values as declared in $notifier->events().

=item * description

The plain-text description of what has occurred.

=item * title (optional)

The title of the event.

=back

This method is the public interface for requesting a notification.

=cut

sub notify {
	my $self = shift;
	my %args = @_;

	my %default_titles = (
		finkPackageBuildPassed        => 'Fink Build Passed.',
		finkPackageBuildFailed        => 'Fink Build Failed!',
		finkPackageInstallationPassed => 'Fink Installation Passed.',
		finkPackageInstallationFailed => 'Fink Installation Failed!',
		finkPackageRemovalPassed      => 'Fink Removal Passed.',
		finkPackageRemovalFailed      => 'Fink Removal Failed!',
		finkDonePassed                => 'Fink Finished Successfully.',
		finkDoneFailed                => 'Fink Finished With Failure!',
	);

	# sanity check for required params
	return undef if (not defined $args{'event'} or not defined $args{'description'});

	# try to provide default $arg{title} if none was passed
	$args{'title'} = $default_titles{$args{'event'}} unless defined $args{'title'};

	# call the notifier-specific implementation to actually notify
	$self->do_notify(%args);
}


=item about() - about the output plugin

This method returns the name and version of the output plugin
currently loaded. The return either as a list (notifier-type, version,
short description, URL)
or a ref to that list, depending on caller context.

Notifier modules must provide an about() method that returns data for
their module.

=cut

sub about { }

=item do_notify(%args) - perform a notification (notifier-specific)

Notifier modules must provide a do_notify() method that implements
their notification scheme. The %args parameters are the same as for
notify().

=cut

sub do_notify {
	my $self = shift;
	my $ok = 1;
	
	for my $plugin (@$self) {
		# Don't want to fail while notifying about failure, so be extra
		# careful.
		eval {
			$ok &&= $plugin->do_notify(@_);
		};
		$ok &&= !$@;
	}
	
	return $ok;
}

=item list_plugins() - list the available notification plugins

This method will list the available notification plugins for
Fink::Notify to use.

=cut

sub list_plugins {
	my $self = shift;
	
	my %plugins;
	foreach my $plugname ( _plugins ) {
		$plugins{$plugname}{about} = $plugname->about();
		$plugins{$plugname}{enabled} = 1 if defined $plugname->new();
	}

	my $active_plugin = Fink::Notify->new;
	my %in_use = map { $_->about->[0] => 1 } @$active_plugin;

	for my $key (sort keys %plugins) {
		my ($shortname) = $plugins{$key}{about}[0];

		my $installed = "   ";
		$installed = " ! " if ($plugins{$key}->{'enabled'});
		$installed = " * " if $in_use{$shortname};

		my @about = @{$plugins{$key}->{'about'}};
		for (0..3) {
			$about[$_] = "" if (not defined $about[$_]);
		}

		$about[2] = substr($about[2], 0, 44);
		printf("%3s %-15.15s %-11.11s %s\n", $installed, $shortname, $about[1],
			$about[2]);
		print(" " x 32, $about[3], "\n") if ($about[3] ne "");
	}
}

=back

=cut

1;

# vim: ts=4 sw=4 noet
