
use strict;
use warnings;

use Test::More tests => 4;
use Test::Deep;

use_ok 'Parse::BooleanLogic';

my $parser = new Parse::BooleanLogic;
cmp_deeply
    $parser->as_array('x = 10'),
    [{left => 'x', operator => '=', right => 10}],
    'x = 10'
;

cmp_deeply
    $parser->as_array('(x = 10)'),
    [[{left => 'x', operator => '=', right => 10}]],
    'x = 10'
;

cmp_deeply
    $parser->as_array('(x = 10) OR y = "Y"'),
    [
        [{ left => 'x', operator => '=', right => 10 }],
        'OR',
        { left => 'y', operator => '=', right => 'Y' }
    ],
    'x = 10'
;
