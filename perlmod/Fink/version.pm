# This file is based on version from version-0.7203 from CPAN, which
# declares:
#
# This module can be distributed under the same terms as Perl.
# Copyright (C) 2004,2005,2006,2007 John Peacock
#
# For the changes by Fink:
# Copyright (C) 2007-2011 The Fink Package Manager Team.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# It was converted to Fink::version and further modified for use by
# Fink. You can read about these changes in the accompanying ChangeLog
# files and by browsing the CVS repository.

=head1 NAME

Fink::version - Perl extension for Version Objects

=head1 SYNOPSIS

This module is a clone of the L<version> module and its perl-only
back-end implementation. See documentation for those modules.

=cut

package Fink::version;

use 5.005_04;
use strict;

use vars qw(@ISA $VERSION $CLASS *qv);

$VERSION = 0.7203;

$CLASS = 'Fink::version';

eval "use Fink::version::vxs $VERSION";
if ( $@ ) { # don't have the XS version installed
    eval "use Fink::version::vpp $VERSION"; # don't tempt fate
    die "$@" if ( $@ );
    push @ISA, "Fink::version::vpp";
    *Fink::version::qv = \&Fink::version::vpp::qv;
}
else { # use XS module
    push @ISA, "Fink::version::vxs";
    *Fink::version::qv = \&Fink::version::vxs::qv;
}

# Preloaded methods go here.
sub import {
    my ($class) = shift;
    my $callpkg = caller();
    no strict 'refs';
    
    *{$callpkg."::qv"} = 
	    sub {return bless Fink::version::qv(shift), $class }
	unless defined(&{"$callpkg\::qv"});

#    if (@_) { # must have initialization on the use line
#	if ( defined $_[2] ) { # CVS style
#	    $_[0] = Fink::version::qv($_[2]);
#	}
#	else {
#	    $_[0] = Fink::version->new($_[1]);
#	}
#    }
}

1;
