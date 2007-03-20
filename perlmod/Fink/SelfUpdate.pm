# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::SelfUpdate class
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2007 The Fink Package Manager Team
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

package Fink::SelfUpdate;

use Fink::Services qw(&execute &find_subpackages);
use Fink::Bootstrap qw(&additional_packages);
use Fink::CLI qw(&print_breaking &prompt_boolean &prompt_selection print_breaking_stderr);
use Fink::Config qw($basepath $config $distribution);
use Fink::Engine;  # &aptget_update &cmd_install, but they aren't EXPORT_OK
use Fink::Package;

use POSIX qw(strftime);

use strict;
use warnings;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
	$VERSION	 = 1.00;
	@ISA		 = qw(Exporter);
	@EXPORT		 = qw();
	@EXPORT_OK	 = qw();	# eg: qw($Var1 %Hashit &func3);
	%EXPORT_TAGS = ( );		# eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

END { }				# module clean-up code here (global destructor)


=head1 NAME

Fink::SelfUpdate - download package descriptions from server

=head1 DESCRIPTION

=head2 Methods

=over 4

=item check

  Fink::SelfUpdate::check($method);

This is the main entry point for the 'fink selfupdate*' commands. The
local collection of package descriptions is updated according to one
of the following methods:

=over 4

=item "point"

A tarball of the latest Fink binary installer package collection is
downloaded from the fink website.

=item "cvs"

=item "rsync"

"cvs" or "rsync" protocols are used to syncronize with a remote
server.

=back

The optional $method parameter specifies the
selfupdate method to use:

=over 4

=item 0 (or undefined or omitted)

Use the current method

=item 1 or "cvs"

Use the cvs method

=item 2 or "rsync"

Use the rsync method

=back

The current method is specified by name in the SelfUpdateMethod field
in the F<fink.conf> preference file. If there is no current method
preference and a specific $method is not given, the user is prompted
to select a method. If a $method is given that is not the same as the
current method preference, fink.conf is updated according to $method.

=cut

sub check {
	my $method = shift;  # requested selfupdate method to use

	$method = '' if ! defined $method;

	{
		# compatibility for old calling parameters
		my %methods = (
			0 => '',
			1 => 'cvs',
			2 => 'rsync',
		);
		if (length $method and exists $methods{$method}) {
			$method = $methods{$method};
		}
	}

	# canonical form is all-lower-case
	$method = lc($method);
	my $prev_method = lc($config->param_default("SelfUpdateMethod", ''));

	# find all Fink::SelfUpdate:: subclasses, skipping the base class
	my @avail_subclasses = &find_subpackages(__PACKAGE__);
	@avail_subclasses = grep { $_ ne __PACKAGE__.'::Base' } @avail_subclasses;

	if ($method eq '') {
		# no explicit method requested

		if ($prev_method ne '') {
			# use existing default
			$method = $prev_method;
		} else {
			# no existing default so ask user

			my @choices = ();  # menu entries as ordered label=>class pairs
			my @default = ();  # default menu choice (rsync if it's avail)
			foreach my $subclass (sort @avail_subclasses) {
				push @choices, ( $subclass->desc_short() => $subclass );
				@default = ( 'value' => $subclass ) if $subclass->method_name() eq 'rsync';
			}

			my $subclass_choice = &prompt_selection(
				'Choose an update method',
				intro   => 'fink needs you to choose a SelfUpdateMethod.',
				choices => \@choices,
				default => \@default,
			);
			$method = lc($subclass_choice->method_name());
		}
	} else {
		# explicit method requested
		&print_breaking("\n Please note: the command 'fink selfupdate' "
						. "should be used for routine updating; you only "
						. "need to use a command like 'fink selfupdate-cvs' "
						. "or 'fink selfupdate-rsync' if you are changing "
						. "your update method. \n\n");

		if (length $prev_method and $method ne $prev_method) {
			# requested a method different from previously-saved default
			# better double-check that user really wants to do this
			my $answer =
				&prompt_boolean("The current selfupdate method is $prev_method. "
								. "Do you wish to change this default method "
								. "to $method?",
								default => 1
				);
			return if !$answer;
		}
	}

	# find the class that implements the method
	my ($subclass_use) = grep { $_->method_name() eq $method } @avail_subclasses;

	# sanity checks
	die "Selfupdate method '$method' is not implemented\n" unless( defined $subclass_use && length $subclass_use );
	$subclass_use->system_check() or die "Selfupdate mthod '$method' cannot be used\n";

	if ($method ne $prev_method) {
		# save new selection (explicit change or being set for first time)
		&print_breaking("fink is setting your default update method to $method\n");
		$config->set_param("SelfUpdateMethod", $method);
		$config->save();
	}

	# clear remnants of any methods other than one to be used
	foreach my $subclass (@avail_subclasses) {
		next if $subclass eq $subclass_use;
		$subclass->clear_metadata();
	}

	# Let's do this thang!
	my $update_data = $subclass_use->do_direct();
	if (defined $update_data) {
		&update_version_file($method, $update_data);
		&do_finish();
	}
}

=item do_finish

  Fink::SelfUpdate::do_finish;

Perform some final actions after updating the package descriptions collection:

=over 4

=item 1.

Update apt indices

=item 2.

Reread package descriptions (update local package database)

=item 3.

If a new version of the "fink" package itself is available, install
that new version.

=item 4.

If a new fink was installed, relaunch this fink session using it.
Otherwise, do some more end-of-selfupdate tasks (see L<finish>).

=back

=cut

sub do_finish {
	my $package;

	# update the apt-get database
	Fink::Engine::aptget_update()
		or &print_breaking("Running 'fink scanpackages' may fix indexing problems.");

	# forget the package info
	Fink::Package->forget_packages();

	# ...and then read it back in
	Fink::Package->require_packages();

	# update the package manager itself first if necessary (that is, if a
	# newer version is available).
	$package = Fink::PkgVersion->match_package("fink");
	if (not $package->is_installed()) {
		Fink::Engine::cmd_install("fink");
	
		# re-execute ourselves before we update the rest
		print "Re-executing fink to use the new version...\n";
		exec "$basepath/bin/fink selfupdate-finish";
	
		# the exec doesn't return, but just in case...
		die "re-executing fink failed, run 'fink selfupdate-finish' manually\n";
	} else {
		# package manager was not updated, just finish selfupdate directly
		&finish();
	}
}

=item finish

  Fink::SelfUpdate::finish;

Update all the packages that are part of fink itself or that have an
Essential or other high importance.

=cut

sub finish {
	my (@elist);

	# determine essential packages
	@elist = Fink::Package->list_essential_packages();

	# add some non-essential but important ones
    my ($package_list, $perl_is_supported) = additional_packages();

	print_breaking("WARNING! This version of Perl ($]) is not currently supported by Fink.  Updating anyway, but you may encounter problems.\n") unless $perl_is_supported;

	foreach my $important (@$package_list) {
		my $po = Fink::Package->package_by_name($important);
		if ($po && $po->is_any_installed()) {
			# only worry about "important" ones that are already installed
			push @elist, $important;
		}
	}

	# update them
	Fink::Engine::cmd_install(@elist);	

	# tell the user what has happened
	print "\n";
	&print_breaking("The core packages have been updated. ".
					"You should now update the other packages ".
					"using commands like 'fink update-all'.");
	print "\n";
}

=item update_version_file

	&update_version_file($method, $data);

Marks the %p/fink/$distribution/VERSION file with information about
the just-done selfupdate using method $method. The $data is also
stored in the VERSION file. Returns nothing useful.

=cut

sub update_version_file {
	my $method = shift;
	my $data = shift;

	my $filename = "$basepath/fink/$distribution/VERSION";
	my @lines = ();

	# read old file
	if (open my $FH, '<', $filename) {
		@lines = <$FH>;
		close $FH;
	}

	# remove ".cvs" from server file
	map s/^(\d|\.)+\.cvs$/$1/, @lines;

	# remove old selfupdate info
	@lines = grep { $_ !~ /^\s*SelfUpdate\s*:/i } @lines;

	# add new selfupdate info
	my $line = "SelfUpdate: $method\@" . time();
	$line .= " $data" if defined $data && length $data;
	push @lines, $line;

	# save new file contents atomically
	if (open my $FH, '>', "$filename.tmp") {
		print $FH @lines;
		close $FH;
	} else {
		print_breaking_stderr "WARNING: Not saving timestamp of selfupdate because could not write $filename.tmp: $!\n";
	}
}

=item last_done

	my ($last_method,$last_time, $last_data) = Fink::SelfUpdate::last_done();
	print "Last selfupdate was by $last_method";

	print ", , $age seconds ago\n";
	if ($last_time) {
		print " ", time() - $last_time, " seconds ago";
	}

Returns the method, time, and any method-specific data for the last
selfupdate that was performed.

=cut

sub last_done {
	my $filename = "$basepath/fink/$distribution/VERSION";

	if (open my $FH, '<', $filename) {
		my @lines = <$FH>;
		close $FH;

		# first look for the new-style token
		foreach my $line (@lines) {
			if ($line =~ /^\s*SelfUpdate\s*:\s*(.*)\s*$/i) {
				my $value = $1;
				if ($value =~ /^(.+?)\@(\d+)\s*(.*)/) {
					return ($1, $2, $3);
				} elsif ($line =~ /^(\S+)\s*(.*)/) {
					return ($1, 0, $2);
				} else {
					print_breaking_stderr "WARNING: Skipping malformed line \"$line\" in $filename.";
				}
			}
		}

		# next see if it's new multiline format, picking matching Dist/Arch
		# er, what *is* this format? Good thing we aren't using it yet:)

		# maybe original one-line format?
		my $line = $lines[0];
		chomp $line;
		if ($line =~ /^(.*)\.(cvs|rsync)$/) {
			return ($2, 0, $1);
		}
		return ('point', 0, $line);
	}

	# give up
	print_breaking_stderr "WARNING: could not read $filename: $!\n";
	return (undef, undef, undef);
}

=back

=cut

### EOF
1;
# vim: ts=4 sw=4 noet
