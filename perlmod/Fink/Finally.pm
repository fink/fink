# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Finally module
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2006 The Fink Package Manager Team
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

package Fink::Finally;
use base 'Fink::Base';

use warnings;
use strict;

=head1 NAME

Fink::Finally - Run cleanup code unconditionally.

=head1 DESCRIPTION

Usually cleanup code runs explicitly, but sometimes exceptions can cause it
to be bypassed. Fink::Finally allows such code to be executed even if an
exception occurs.

=head1 SYNOPSIS

  use Fink::Finally;

  # $fin runs even if an exception is thrown
  my $fin = Fink::Finally->new(sub { ... });

  function_which_might_die();

  $fin->run;

=head1 METHODS

=over 4

=item new

  my $fin = Fink::Finally->new(sub { ... });

Create a finalizer to run the given cleanup code.

The code will run either when C<$finally->run> is called, or when I<$fin> goes
out of scope. The return value of the code is not accessible, since the caller
may not get a chance to explictly call I<&run>.

=cut

sub initialize {
	my ($self, $code) = @_;
	$self->SUPER::initialize;
	
	die "A Finally needs some code to run!\n"
		unless defined $code && ref($code) eq 'CODE';
	$self->{_code} = $code;
	$self->{_pid} = $$;
	$self->{_primed} = 1; # ready to go
}

=item run

  $fin->run;

Explicitly run the cleanup code in this finalizer.

If called multiple times, only the first will actually do anything.

=cut

sub run {
	my ($self) = @_;
	delete $self->{_primed}
		if $self->{_primed} && $$ != $self->{_pid}; # Don't run in forks
	return unless $self->{_primed};
	
	# Preserve exit status
	my $status = $?;
	
	&{$self->{_code}}();
	delete $self->{_primed};
	
	$? = $status;
}

sub DESTROY {
	$_[0]->run;
}

=item cancel

  $fin->cancel;

Do not allow this finalizer to run.

=cut

sub cancel {
	my ($self) = @_;
	delete $self->{_primed};
}

=back

=cut

1;
