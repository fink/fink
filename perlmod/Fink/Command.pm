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

package Fink::Command;

require Exporter;
@ISA = qw(Exporter);
@EXPORT    = ();
@EXPORT_OK = qw(mv cp cat mkdir_p rm_rf rm_f touch chowname symlink_f);
%EXPORT_TAGS = ( ALL => [@EXPORT, @EXPORT_OK] );

use strict;
use warnings;
use Carp;


=head1 NAME

Fink::Command - emulate common shell commands in Perl

=head1 SYNOPSIS

  use Fink::Command ':ALL';

  mv @src, $dest;
  cp @src, $dest;
  
  my $text = cat $file;
  my @text = cat $file;

  mkdir_p @dirs;
  rm_rf @dirs;
  rm_f @files;

  touch @files;

  chowname $user, @files;

  symlink_f $src, $dest;


=head1 DESCRIPTION

Its a common tempation to write something like this:

    execute("rm -rf $dir");

Instead of relying on shell utilities, we can do this inside Perl.  This
module provides a set of Perl functions emulating common shell utilities.

=head2 Functions

No functions are exported by default, they are all optional.  You can get
all of them with

  use Fink::Command ':ALL';

Unless noted otherwise, functions set $! and return false on failure.

=over 4

=item mv

  mv $src,  $dest;
  mv @srcs, $destdir;

Like C<mv>.

=cut

sub mv {
	my @src = _expand(@_);
	my $dst = pop @src;
	
	require File::Copy;
	
	croak("Too many arguments") if @src > 1 && ! -d $dst;
	croak("Insufficient arguments") unless @src;
	
	my $nok = 0;
	foreach my $src (@src) {
		$nok ||= !File::Copy::move($src,$dst);
	}
	return !$nok;
}

=item cp

  cp $src,  $dest;
  cp @srcs, $destdir;

Like C<cp>.

=cut

sub cp {
	my @src = _expand(@_);
	my $dst = pop @src;
	
	require File::Copy;
	
	croak("Too many arguments") if (@src > 1 && ! -d $dst);
	croak("Insufficient arguments") unless @src;
	
	my $nok = 0;
	foreach my $src (@src) {
		$nok ||= !File::Copy::copy($src,$dst);
	}
	return !$nok;
}

=item cat

  my $text = cat $file;
  my @text = cat $file;

Reads a file returning all the text in one lump or as a list of lines
depending on context.

Returns undef on error, even in list context.

=cut

sub cat {
	my $file = shift;
	my $fh;
	unless( open $fh, $file ) {
		return undef;
	}
	
	local $/ = $/;
	$/ = undef unless wantarray;
	return <$fh>;
}

=item mkdir_p

  mkdir_p @dirs;

Like C<mkdir -p>.

Due to an implementation quirk, $! is not set on failure.

=for private
If this becomes a problem, reimplement without File::Path

=cut

sub mkdir_p {
	my @dirs = _expand(@_);
	require File::Path;
	
	# mkpath() has one condition where it will die. :(  The eval
	# loses the value of $!.
	my $nok = 0;
	foreach my $dir (@dirs) {
		eval { File::Path::mkpath([$dir]) };
		$nok = 1 if $@;
	}
	return !$nok;
}

=item rm_rf

  rm_rf @dirs;

Like C<rm -rf>

=cut

sub rm_rf {
	my @dirs = grep -e, _expand(@_);
	require File::Path;
	local $SIG{__WARN__} = sub {};  # rmtree is noisy on failure.  Shut up.

	File::Path::rmtree(\@dirs);

	return !scalar(grep -e, @dirs);
}

=item rm_f

  rm_f @files;

Like C<rm -f>

=cut

sub rm_f {
	my @files = _expand(@_);
	
	my $nok = 0;
	foreach my $file (@files) {
		next if unlink($file);
		chmod(0777,$file);
		next if unlink($file);
	
		$nok = 1;
	}
	
	return !$nok;
}


=item touch

  touch @files;

Like C<touch>.

=cut

sub touch {
	my $t = time;
	my @files = _expand(@_);
	
	my $nok = 0;
	foreach my $file (@files) {
		open(FILE,">>$file") or $nok = 1;
		close(FILE)          or $nok = 1;
		utime($t,$t,$file)   or $nok = 1;
	}
	
	return !$nok;
}


=item chowname

  chowname $user, @files;
  chowname "$user:$group", @files;
  chowname ":$group", @files;

Like C<chowname> but the user/group specification is a bit simpler.  Dot is not
supported as a seperator.

=cut

sub chowname {
	my($owner, @files) = @_;
	my($user, $group) = split /:/, $owner, 2;
	
	my $uid = defined $user  && length $user  ? getpwnam($user)  : -1;
	my $gid = defined $group && length $group ? getgrnam($group) : -1;
	
	return if !defined $uid or !defined $gid;
	
	# chown() won't return false as long as one operation succeeds, so we
	# have to call it one at a time.
	my $nok = 0;
	foreach my $file (@files) {
		$nok ||= !CORE::chown $uid, $gid, $file;
	}
	
	return !$nok;
}

=item symlink_f

  symlink_f $src, $dest;

Like C<ln -sf>.  Currently requires the $dest.

=cut

sub symlink_f {
	my($src, $dest) = @_;
	
	unlink $dest or return;
	return symlink($src, $dest);
}

=begin private

=item _expand

  my @expanded_paths = _expand(@paths);

Expands a list of filepaths like the shell would.

=end private

=cut

sub _expand {
	return map { /[{*?]/ ? glob($_) : $_ } @_;
}


=back

=head1 SEE ALSO

This module is inspired by L<ExtUtils::Command>

=cut

1;
