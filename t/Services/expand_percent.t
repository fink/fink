#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';

require_ok('Fink::Services');

my $map = { 'f' => 'm',
	    'F' => '%f',
	    'r' => 'st',
	    'l' => '%F',
	    '%' => '%%'
	};

# basic stuff

is( Fink::Services::expand_percent( 'Fink for life', undef ),
    'Fink for life',
    'undef map'
    );

eval { Fink::Services::expand_percent( 'Fink for li%r', undef ) };
like( $@,
      qr/unknown.*expansion/i,
      'undef map but try to use expansion'
      );

is( Fink::Services::expand_percent( 'Give 110%%, son', undef ),
    'Give 110%, son',
    'undef map but need percent expansion'
    );

is( Fink::Services::expand_percent( 'Fink for life', $map ),
    'Fink for life',
    'No expansions needed'
    );

is( Fink::Services::expand_percent( 'Fink %fo%r li%fe', $map ),
    'Fink most lime',
    'One pass'
    );

is( Fink::Services::expand_percent( '%Fink %fo%r li%fe', $map ),
    'mink most lime',
    'Two passes'
    );

eval { Fink::Services::expand_percent( '%Fink %fo%r %li%fe', $map ) };
like( $@,
      qr/too deep/i,
      'Three passes is too deep recursion'
      );

eval { Fink::Services::expand_percent( 'F%ink for life', $map ) };
like( $@,
      qr/unknown.*expansion/i,
      'Unknown percent char',
      );

# protected percent signs

is( Fink::Services::expand_percent( 'Give 110%%, son', $map ),
    'Give 110%, son',
    'Simple %%'
    );

is( Fink::Services::expand_percent( 'woo %%%% woo', $map ),
    'woo %% woo',
    'Do not recurse on it'
    );

is( Fink::Services::expand_percent( 'printf(%%s)', $map ),
    'printf(%s)',
    '%% takes precedence over overlapping legal expansion'
    );

is( Fink::Services::expand_percent( 'hash %%%rreets', $map ),
    'hash %streets',
    'Actual expansion following %%'
    );

# long keys
is( Fink::Services::expand_percent( 'M%iss%iss%ippi', {qw/iss ith ipp iss/} ),
    'Mithithissi',
    'Long keys'
    );

# braces
is( Fink::Services::expand_percent( 'po%{ta}%{t}o', {qw/ta n t ch/} ),
    'poncho',
    'Braces'
  );
