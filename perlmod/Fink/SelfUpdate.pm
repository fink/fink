# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::SelfUpdate class
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
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110, USA.
#

package Fink::SelfUpdate;

use Fink::Services qw(&find_subpackages &get_options);
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

=item cmd_selfupdate

	cmd_selfupdate(@ARGV);

Main entry point for command-line interface to selfupdate. Pass the
command-line parameter list after removing "fink selfupdate" or
whatever moral equivalent.

=cut

sub cmd_selfupdate {
	my @cmdline = @_;

	my( $su_method, $do_finish, $do_list );

	get_options('selfupdate', [
					[ 'method|m=s'     => \$su_method,   "Method to use."              ],
					[ 'list-methods|l' => \$do_list,     "List all available methods." ],
					[ 'finish|f'       => \$do_finish,   "Do the post-update tasks."   ],
				], \@cmdline, helpformat => <<HELPFORMAT);
%intro{[options]}
%all{}
If no options are given, selfupdate is performed according to the
current default update method.

HELPFORMAT

	if ($do_list ) {
		Fink::SelfUpdate->list_plugins();
	} elsif ($do_finish) {
		print "--method specifier ignored for --finish\n" if defined $su_method;
		&do_finish;
	} else {
		&check($su_method);
	}
}

=item check

  Fink::SelfUpdate::check($method);

This is the main entry point for the actual updating of the local
collection of package descriptions.

The optional $method parameter specifies the selfupdate method to
use. If no $method is specified (0 or undef), the default method is
used. It can be a text string naming the method, or a legacy API of
numerical values for some specific methods:

=over 4

=item 0

Use the current default method

=item 1

Use the "cvs" method

=item 2

Use the "rsync" method

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

	my @avail_subclasses = &Fink::SelfUpdate::_plugins;

	if ($method eq '') {
		# no explicit method requested

		if ($prev_method ne '') {
			# use existing default
			$method = $prev_method;
		} else {
			# no existing default so ask user

			if (!@avail_subclasses) {
				print_breaking_stderr("ERROR: No selfupdate methods implemented. Giving up.\n");
				return;
			}

			my @choices = ();  # menu entries as ordered label=>class pairs
			my @default = ();  # default menu choice (rsync if it's avail)
			foreach my $subclass (@avail_subclasses) {
				push @choices, ( $subclass->description() => $subclass );
				@default = ( 'value' => $subclass ) if &class2methodname($subclass) eq 'rsync';
			}

			my $subclass_choice = &prompt_selection(
				'Choose an update method',
				intro   => 'fink needs you to choose a SelfUpdateMethod.',
				choices => \@choices,
				default => \@default,
			);
			$method = &class2methodname($subclass_choice);
		}
	} else {
		# explicit method requested
		&print_breaking("\nPlease note: the simple command 'fink selfupdate' "
						. "should be used for routine updating; you only "
						. "need to use a command like 'fink selfupdate-cvs' "
						. "or 'fink selfupdate --method=rsync' if you are changing "
						. "your update method. \n\n");

		if (length $prev_method and $method ne $prev_method) {
			# requested a method different from previously-saved default
			# better double-check that user really wants to do this

			if ($method eq 'point') {
				# "point" updater (inject.pl) doesn't appear to remove
				# .info that are not in the tarball, so files added by
				# other selfupdate methods that supply different
				# packages or newer versions would remain and
				# contaminate the point dist.
				&print_breaking("\nWARNING: Fink does not presently support changing to SelfUpdateMethod \"point\" from any other method\n;");
				return;
			}
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
	my ($subclass_use) = grep { &class2methodname($_) eq $method } @avail_subclasses;

	# sanity checks
	die "Selfupdate method '$method' is not implemented\n" unless( defined $subclass_use && length $subclass_use );
	$subclass_use->system_check() or die "Selfupdate method '$method' cannot be used\n";

	if ($method ne $prev_method) {
		# clear remnants of any methods other than one to be used
		foreach my $subclass (@avail_subclasses) {
			next if $subclass eq $subclass_use;
			$subclass->clear_metadata();
		}

		# save new selection (explicit change or being set for first time)
		&print_breaking("fink is setting your default update method to $method\n");
		$config->set_param("SelfUpdateMethod", $method);
		$config->save();
	}

	# Let's do this thang!
	$subclass_use->do_direct() && &do_finish;
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

	# Make sure using the special tree for 10.4 systems need to do
	# this now (and re-selfupdate using it) because other Essential
	# packages may have been updated beyond that tree and don't want
	# "newer" packages to leak back into it. We are currently running
	# the "new" fink, but hopefully it will remain compatible with
	# 10.4's dpkg and other core things and won't matter if user has
	# the new one even if it's not in 10.4's distro.
	if ($config->param('distribution') eq '10.4'
		&& $config->has_param('SelfUpdateMethod') ne '10.4'
		&& $config->has_param('SelfUpdateMethod') ne 'point'
		&& 0					# XXX REMOVE THIS TO ACTIVATE
	) {
		print_breaking <<EOMSG;
You appear to be on OS X 10.4. This version of the operating system is
no longer supported by the fink project. To maintain usability, you
must use a special selfupdate method that contains the last collection
of packges expected to work well on 10.4. Now running 'fink selfupdate
--method=10.4' to try to do that for you...
EOMSG
		exec "$basepath/bin/fink selfupdate --method=10.4";
		die "re-executing fink failed, run 'fink selfupdate --method=10.4' manually\n";
	}

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

	my $updatepackages = 0;

	# add UpdatePackages, if any
	if (defined($config->param("UpdatePackages"))) {
		$updatepackages = 1;
		my @ulist = split(/\s*,\s*/, $config->param("UpdatePackages"));
		push (@elist, @ulist);
	}

	# update them
	Fink::Engine::cmd_install(@elist);	

	# remove the list of UpdatePackages
	if ($updatepackages) {
		$config->set_param("UpdatePackages", "");
		$config->save();
	}


	# tell the user what has happened
	print "\n";
	&print_breaking("The core packages have been updated. ".
					"You should now update the other packages ".
					"using commands like 'fink update-all'.");
	print "\n";
}

=item last_done

	my ($last_method,$last_time, $last_data) = Fink::SelfUpdate::last_done();
	print "Last selfupdate was by $last_method";

	print ", , $age seconds ago\n";
	if ($last_time) {
		print " ", time() - $last_time, " seconds ago";
	}

Returns the method, time, and any method-specific data for the last
selfupdate that was performed for the active distribution.

=cut

sub last_done {
	my $file_old = "$basepath/fink/$distribution/VERSION";
	my $filename = "$file_old.selfupdate";

	if (open my $FH, '<', $filename) {
		my @lines = <$FH>;
		close $FH;

		# new-style tokenized file
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
		print_breaking_stderr "WARNING: No valid data found in $filename, falling back to old-style $file_old file.";
	}

	if (open my $FH, '<', $file_old) {
		my @lines = <$FH>;
		close $FH;

		# see if it's new multiline format, picking matching Dist/Arch
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
	print_breaking_stderr "WARNING: could not read $file_old: $!\n";
	return (undef, undef, undef);
}

=item class2methodname

	my $name = Fink::SelfUpdate::class2methodname('Fink::SelfUpdate::CVS');
	# gives 'cvs'

Given a class, strips all leading namespaces and converts to
lower-case. This is considered as the SelfUpdateMethod implemented by
the class.

=cut

sub class2methodname {
	my $class = shift;

	$class = ref($class) if ref($class);  # find class if called as object
	$class =~ s/.*:://;  # just the subclass

	return lc($class);
}

=item _plugins

	my $plugin_classes = Fink::SelfUpdate::_plugins;

Returns a ref to a list of subclasses (by namespace) of the present
class that are subclasses (by inheritance) of the Base subclass.
Guaranteed that there is only one class with a given lowest-level name
(case-insentively). The returned list is sorted by that lowest-level
name.

=cut

{
	my $plugins;  # cache the results

	sub _plugins {
		if (!defined $plugins) {
			my $base_class = __PACKAGE__ . '::Base';
			my %plugins = ();
			foreach my $class (sort(find_subpackages(__PACKAGE__))) {
				next if $class eq $base_class;  # skip base class (dummy method)

				# lazy solution: require ISA relationship on base, so can
				# know that all standard API are available
				eval "require $class";
				next unless $class->isa($base_class);

				# name is the unique token, so eliminate dups
				my $name = &class2methodname($class);
				if (exists $plugins{$name}) {
					# skip dups
					print_breaking_stderr("WARNING: $name already supplied by $plugins{$name}; skipping $class\n");
					next;
				}
				$plugins{$name} = $class;
			}
			$plugins = [ map $plugins{$_}, sort keys %plugins ];
		}
		return @$plugins;
	}
}

=item list_plugins

	Fink::SelfUpdate::list_plugins;

Prints a list of the available plugins for selfupdate-methods and their status:

=over 4

=item +  Method is usable

=item -  Method is not usable

=item i  Method is current default

=back

=cut

sub list_plugins {
	my $class = shift;  # class method because the other pluggable things are

	my $default_method = lc($config->param_default("SelfUpdateMethod", ''));

	foreach my $plugclass ( &_plugins ) {
		my ($shortname) = $plugclass =~ /^.*\:\:([^\:]*)$/;

		my $flags = 
			( $plugclass->system_check() ? '+' : '-' ) .
			( lc($shortname) eq $default_method ? 'i' : ' ' );

		my $plugversion = $plugclass->VERSION;
		$plugversion = '?' unless defined $plugversion;

		printf " %2s %-15.15s %-11.11s %s\n", $flags, $shortname, $plugversion, $plugclass->description();
	}
}

=back

=cut

### EOF
1;
# vim: ts=4 sw=4 noet
