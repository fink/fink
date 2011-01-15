# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Command module
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

package Fink::Command;

require Exporter;
@ISA = qw(Exporter);
@EXPORT    = ();
@EXPORT_OK = qw(mv cp cat mkdir_p rm_rf rm_f touch chowname chowname_hr symlink_f du_sk);
%EXPORT_TAGS = ( ALL => [@EXPORT, @EXPORT_OK] );

use strict;
use warnings;
use Config;
use Carp;
use POSIX qw(ceil);


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
	unless( open $fh, "<$file" ) {
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

	File::Path::rmtree(\@dirs, 0, 1);

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
		next unless lstat $file;
		next if unlink($file);
		chmod(0777,$file);     # Why? A file's perm's don't affect unlink
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

Like C<chowname> but the user/group specification is a bit simpler,
since it takes user/group names instead of numbers like the the Unix
C<chown> command. Either (or both) can be omitted, in which case that
parameter is not changed. Dot is not supported as a separator.

=cut

sub chowname {
	my($owner, @files) = @_;
	my($user, $group) = split( /:/, $owner, 2 );
	
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

=item chowname_hr

  chowname_hr $user, @files;
  chowname_hr "$user:$group", @files;
  chowname_hr ":$group", @files;

Like chowname, but recurses down each item in @files. Symlinks are not
followed.

=cut

sub chowname_hr {
	my($owner, @files) = @_;
	my($user, $group) = split( /:/, $owner, 2 );
	
	my $uid = defined $user  && length $user  ? getpwnam($user)  : -1;
	my $gid = defined $group && length $group ? getgrnam($group) : -1;
	
	return if !defined $uid or !defined $gid;

	require File::Find;
	
	# chown() won't return false as long as one operation succeeds, so we
	# have to call it one at a time.
	my $nok = 0;
	my @links; # no lchown for perl
	File::Find::find(
		sub {
			if (-l $_) {
				push @links, $File::Find::name;
			} else {
				$nok ||= !CORE::chown $uid, $gid, $_;
			}
		},
		@files) if @files;
	
	# Some systems have no lchown
	if ($Config{d_lchown}) {
		while (my @xargs = splice @links, 0, 128) {
			# do 128 filenames at a time to avoid exceeding ARG_MAX
			$nok ||= system('/usr/sbin/chown', '-h', "\Q$user\E:\Q$group\E",
							@xargs);
		}
	}

	return !$nok;
}

=item symlink_f

  symlink_f $src, $dest;

Like C<ln -sf>.  Currently requires the full filename for $dest (not
just target directory.

=cut

sub symlink_f {
	my($src, $dest) = @_;
	
	rm_f $dest or return;
	return symlink($src, $dest);
}

=item du_sk

  du_sk @dirs;

Like C<du -sk>, though slower.

On success returns the disk usage of @dirs in kilobytes. This is not the
sum of file-sizes, rather the total size of the blocks used. Thus it can
change on a filesystem with support for sparse files, or an OS with a
different block size.

On failure returns "Error: <description>".

=cut

# FIXME: Can this be made faster?
sub du_sk {
	my @dirs = @_;
	my $total_size = 0;
	
	# Depends on OS. Pretty much only HP-UX, SCO and (rarely) AIX are
	# not 512 bytes.
	my $blocksize = 512;
	
	require File::Find;
	
	# Must catch warnings for this block
	my $err = "";
	use warnings;
	local $SIG{__WARN__} = sub { $err = "Error: $_[0]" if not $err };
	
	File::Find::finddepth(
		sub {
			# Use lstat first, so the -f refers to the link and not the target.
			my $file_blocks = (lstat $_)[12];
			$total_size += ($blocksize * $file_blocks) if -f _ or -d _;
		},
		@dirs) if @dirs;
	
	# du is supposed to ROUND UP
	return ( $err or ceil($total_size / 1024) );
}

=begin private

=item _expand

  my @expanded_paths = _expand(@paths);

Expands a list of filepaths like the shell would.

=end private

=cut

sub _expand {
	return grep { defined and length } map { ( defined && /[{*?]/ ) ? glob($_) : $_ } @_;
}


=back

=head1 SEE ALSO

This module is inspired by L<ExtUtils::Command>

=cut

1;
# vim: ts=4 sw=4 noet
