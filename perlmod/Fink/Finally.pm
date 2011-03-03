# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Finally module
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2006-2011 The Fink Package Manager Team
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

package Fink::Finally;
use base 'Fink::Base';

use warnings;
use strict;

=head1 NAME

Fink::Finally - An object that can be cleaned up safely.

=head1 DESCRIPTION

Often an object wishes to release resources when it is destroyed. However,
Perl's DESTROY has some problems which make it inappropriate to be used
directly.

A Fink::Finally object will not run in a fork (causing two runs). It will also
not run twice in normal circumstances. Finally, it ensures that $@ and $? are
not changed.

Circular references should never include a Fink::Finally object. This will cause
the object to clean up only during global destruction, when it cannot depend
on any references to exist.

=head1 SYNOPSIS

  package Fink::Finally::Subclass;
  use base 'Fink::Finally';
  sub initialize	{ ... }
  sub finalize		{ ... }

  package main;

  # Explicit cleanup
  my $explicit = Fink::Finally::Subclass->new(@args);
  $explicit->cleanup;

  # Implicit cleanup
  {
      my $implicit = Fink::Finally::Subclass->new(@args);
      # automatically cleaned up when it goes out of scope
  }

  # Preventing cleanup
  {
      my $prevent = Fink::Finally::Subclass->new(@args);
      $prevent->cancel_cleanup;
      # will not be cleaned up
  }

=cut

# Key to private storage
my $PRIV = "__" . __PACKAGE__;

=head1 EXTERNAL INTERFACE

=over 4

=item new

  my $finally = Fink::Finally::Subclass->new(...);

Construct an object which will clean up when it goes out of scope.

=item cleanup

  $finally->cleanup;

Explicitly cause this object to clean up. Clean up will not happen again when
the object leaves scope.

This method should rarely be overridden, subclasses are encouraged to
override I<&finalize> instead.

=cut

sub cleanup {
	my ($self) = @_;
	return 0 unless $self->{$PRIV}->{primed};		# Don't run twice
	return 0 if $self->{$PRIV}->{cancelled};		# Don't run if cancelled
	return 0 unless $self->{$PRIV}->{pid} == $$;	# Don't run in a fork
	
	local ($@, $?); # Preserve variables
	$self->{$PRIV}->{primed} = 0; # Don't run again
	$self->finalize();
	return 1;
}

sub DESTROY {
	$_[0]->cleanup;
}

=item cancel_cleanup

  $finally->cancel_cleanup;

Prevent this object from cleaning up.

=cut

sub cancel_cleanup {
	$_[0]->{$PRIV}->{cancelled} = 1;
}

=back

=head1 SUBCLASSING

These methods should generally not be called externally, but are useful for
subclasses to override the functionality of Fink::Finally.

=over 4

=item initialize

  sub initialize {
      my ($self) = @_;
      ...

      $self->SUPER::initialize();
  }

The Fink::Base initializer, automatically called when an object is created
with I<&new>.

Subclasses are encouraged to override this method, but they B<must> call
C<$self->SUPER::initialize()> if they intend cleanup to work. It may be
useful to call I<SUPER::initialize> at the end of I<initialize>, to ensure
that cleanup only occurs after setup.

=cut

sub initialize {
	my ($self) = @_;
	$self->SUPER::initialize();
	
	$self->{$PRIV}->{primed} = 1;
	$self->{$PRIV}->{pid} = $$;
}

=item finalize

  sub finalize {
      my ($self) = @_;
      $self->SUPER::finalize();

      ...
  }

The finalizer that performs the actual cleanup.

Subclasses should almost always override this method. The methods I<&cleanup>
and I<DESTROY> should rarely be overridden instead, overriding them may make
cleanup unsafe.

=cut

sub finalize {
	# Do nothing by default
}

=back

=head1 SIMPLE CLEANUP

A subclass Fink::Finally::Simple is provided to make safe cleanup available
when a subclass is overkill.

=over 4

=item new

  my $finally = Fink::Finally::Simple->new($code);

Create a new simple cleanup object.

The code-ref I<$code> will be called to clean up. It will be provided with
a ref to this object as its only argument.

=cut

package Fink::Finally::Simple;
use base 'Fink::Finally';

sub initialize {
	my ($self, $code) = @_;
	die "Fink::Finally::Simple initializer requires a code-ref\n"
		unless ref($code) && ref($code) eq 'CODE';
	
	$self->{_code} = $code;
	$self->SUPER::initialize();
}

sub finalize {
	my ($self) = @_;
	$self->{_code}->($self);
}

=back

=cut

1;
