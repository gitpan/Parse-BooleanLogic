=head1 NAME

Parse::BooleanLogic - parser of boolean expressions

=head1 SYNOPSIS
    
    my $parser = new Parse::BooleanLogic;
    my $tree = $parser->as_array( string => 'x = 10' );
    $tree = $parser->as_array( string => 'x = 10 OR (x > 20 AND x < 30)' );

    $parser->parse(
        string   => 'x = 10 OR (x > 20 AND x < 30)',
        callback => {
            open_paren   => sub { ... },
            operator     => sub { ... },
            operand      => sub { ... },
            close_paren  => sub { ... },
            error        => sub { ... },
        },
    );

=head1 DESCRIPTION

This module is quite fast parser for boolean expressions. Original it's been writen for
Request Tracker for parsing SQL like expressions and it's still capable to, but
it can be used to parse other boolean logic sentences with OPERANDs joined using
binary OPERATORs and grouped and nested using parentheses (OPEN_PAREN and CLOSE_PAREN).

=cut



use strict;
use warnings;

package Parse::BooleanLogic;

our $VERSION = '0.04';

use constant OPERAND     => 1;
use constant OPERATOR    => 2;
use constant OPEN_PAREN  => 4;
use constant CLOSE_PAREN => 8;
use constant STOP        => 16;
my @tokens = qw[OPERAND OPERATOR OPEN_PAREN CLOSE_PAREN STOP];

use Regexp::Common qw(delimited);
my $re_operator    = qr{\b(?i:AND|OR)\b};
my $re_open_paren  = qr{\(};
my $re_close_paren = qr{\)};

my $re_tokens      = qr{(?:$re_operator|$re_open_paren|$re_close_paren)};
my $re_delim       = qr{$RE{delimited}{-delim=>qq{\'\"}}};
my $re_operand     = qr{(?:$re_delim|(?!$re_tokens|["']).+?(?=$re_tokens|["']|\Z))+};

=head1 METHODS

=head2 new

Very simple constructor, returns a new object. Now takes no options and most
methods can be executed as class methods too, however there are plans to
change it and using this lightweight constructor is recommended.

=cut

sub new {
    my $proto = shift;
    return bless {@_}, ref($proto) || $proto;
}


=head2 Parsing expressions

=head3 as_array $string [ %options ]

Takes a string and parses it into perl structure, where parentheses represented using
array references, operands are hash references with one key/value pair: operand,
when binary operators are simple scalars. So string C<x = 10 OR (x > 20 AND x < 30)>
is parsed into the following structure:

    [
        { operand => 'x = 10' },
        'OR',
        [
            { operand => 'x > 20' },
            'AND',
            { operand => 'x < 30' },
        ]
    ]

Aditional options:

=over 4

=item operand_cb - custom operands handler

=item error_cb - custom errors handler

=back

=cut

{ # static variables

my ($tree, $node, @pnodes);
my %callback;
$callback{'open_paren'} = sub {
    push @pnodes, $node;
    push @{ $pnodes[-1] }, $node = []
};
$callback{'close_paren'}     = sub { $node = pop @pnodes };
$callback{'operator'} = sub { push @$node, $_[0] };
$callback{'operand'} = sub { push @$node, { operand => $_[0] } };

sub as_array {
    my $self = shift;
    my $string = shift;
    my %arg = (@_);

    $node = $tree = [];
    @pnodes = ();

    unless ( $arg{'operand_cb'} || $arg{'error_cb'} ) {
        $self->parse(string => $string, callback => \%callback);
        return $tree;
    }

    my %cb = %callback;
    if ( $arg{'operand_cb'} ) {
        $cb{'operand'} = sub { push @$node, $arg{'operand_cb'}->( $_[0] ) };
    }
    $cb{'error'} = $arg{'error_cb'} if $arg{'error_cb'};
    $self->parse(string => $string, callback => \%cb);
    return $tree;
} }

=head3 parse

Takes named arguments: string and callback. Where the first one is scalar with
expression, the latter is a reference to hash with callbacks: open_paren, operator
operand, close_paren and error. Callback for errors is optional and parser dies if
it's omitted. Each callback is called when parser finds corresponding element in the
string. In all cases the current match is passed as argument into the callback.

Here is simple example based on L</as_array> method:

    # result tree and the current group
    my ($tree, $node);
    $tree = $node = [];

    # stack with nested groups, outer most in the bottom, inner on the top
    my @pnodes = ();

    my %callback;
    # on open_paren put the current group on top of the stack,
    # create new empty group and at the same time put it into
    # the end of previous one
    $callback{'open_paren'} = sub {
        push @pnodes, $node;
        push @{ $pnodes[-1] }, $node = []
    };

    # on close_paren just switch to previous group by taking it
    # from the top of the stack
    $callback{'close_paren'} = sub { $node = pop @pnodes };

    # push binary operators as is and operands as hash references
    $callback{'operator'} = sub { push @$node, $_[0] };
    $callback{'operand'}  = sub { push @$node, { operand => $_[0] } };

    # run parser
    $parser->parse( string => $string, callback => \%callback );

    return $tree;

Using this method you can build other representations of an expression.

=cut

sub parse {
    my $self = shift;
    my %args = (
        string => '',
        callback => {},
        @_
    );
    my ($string, $cb) = @args{qw(string callback)};
    $string = '' unless defined $string;

    # States
    my $want = OPERAND | OPEN_PAREN | STOP;
    my $last = 0;
    my $depth = 0;

    while (1) {
        # State Machine
        if ( ($want & OPERAND    ) && $string =~ /\G\s*($re_operand)/iogc ) {
            my $m = $1;
            $m=~ s/\s+$//;
            $cb->{'operand'}->( $m );
            $last = OPERAND;
            $want = OPERATOR;
            $want |= $depth? CLOSE_PAREN : STOP;
        }
        elsif ( ($want & OPERATOR   ) && $string =~ /\G\s*($re_operator)/iogc ) {
            $cb->{'operator'}->( $1 );
            $last = OPERATOR;
            $want = OPERAND | OPEN_PAREN;
        }
        elsif ( ($want & OPEN_PAREN ) && $string =~ /\G\s*($re_open_paren)/iogc ) {
            $cb->{'open_paren'}->( $1 );
            $depth++;
            $last = OPEN_PAREN;
            $want = OPERAND | OPEN_PAREN;
        }
        elsif ( ($want & CLOSE_PAREN) && $string =~ /\G\s*($re_close_paren)/iogc ) {
            $cb->{'close_paren'}->( $1 );
            $depth--;
            $last = CLOSE_PAREN;
            $want = OPERATOR;
            $want |= $depth? CLOSE_PAREN : STOP;
        }
        elsif ( ($want & STOP) && $string =~ /\G\s*$/igc ) {
            $last = STOP;
            last;
        }
        else {
            last;
        }
    }

    if (!$last || !($want & $last)) {
        my $tmp = substr( $string, 0, pos($string) );
        $tmp .= '>>>here<<<'. substr($string, pos($string));
        my $msg = "Incomplete or incorrect expression, expecting a ". $self->bitmask_to_string($want) ." in '$tmp'";
        $cb->{'error'}? $cb->{'error'}->($msg): die $msg;
        return;
    }

    if ( $depth ) {
        my $msg = "Incomplete query, $depth paren(s) isn't closed in '$string'";
        $cb->{'error'}? $cb->{'error'}->($msg): die $msg;
        return;
    }
}

sub bitmask_to_string {
    my $self = shift;
    my $mask = shift;

    my @res;
    for( my $i = 0; $i < @tokens; $i++ ) {
        next unless $mask & (1<<$i);
        push @res, $tokens[$i];
    }

    my $tmp = join ', ', splice @res, 0, -1;
    unshift @res, $tmp if $tmp;
    return join ' or ', @res;
}

=head2 Tree modifications

Several functions taking a tree of boolean expressions as returned by
L<as_array> method and changing it using a callback.

=head3 filter $tree $callback

Filters a tree using provided callback. The callback is called for each operand
in the tree and operand is left when it returns true value.

Boolean operators (AND/OR) are skipped according to parens and left first rule,
for example:

    X OR Y AND Z -> X AND Z
    X OR (Y AND Z) -> X OR Z
    X OR Y AND Z -> Y AND Z
    X OR (Y AND Z) -> Y AND Z
    X OR Y AND Z -> X OR Y
    X OR (Y AND Z) -> X OR Y

Returns new sub-tree. Original tree is not changed, but operands in new tree
still refer to the same hashes in original.

=cut

sub filter {
    my ($self, $tree, $cb, $inner) = @_;

    my $skip_next = 0;

    my @res;
    foreach my $entry ( @$tree ) {
        $skip_next-- and next if $skip_next > 0;

        if ( ref $entry eq 'ARRAY' ) {
            my $tmp = $self->filter( $entry, $cb, 1 );
            if ( !$tmp || (ref $tmp eq 'ARRAY' && !@$tmp) ) {
                pop @res;
                $skip_next++ unless @res;
            } else {
                push @res, $tmp;
            }
        } elsif ( ref $entry eq 'HASH' ) {
            if ( $cb->( $entry ) ) {
                push @res, $entry;
            } else {
                pop @res;
                $skip_next++ unless @res;
            }
        } else {
            push @res, $entry;
        }
    }
    return $res[0] if @res == 1 && ($inner || ref $res[0] eq 'ARRAY');
    return \@res;
}

=head3 solve $tree $callback

Solves a boolean expression using provided callback. Callback is called
for operands and should return a boolean value.

Functions matrixes:

    A B AND OR
    0 0 0   0
    0 1 0   1
    1 0 0   1
    1 1 1   1

Whole branches of the tree can be skipped when result is obvious, for example:

    1 OR  (...)
    0 AND (...)

Returns result of the expression.

See also L</fsolve>.

=cut

sub solve {
    my ($self, $tree, $cb) = @_;

    my ($res, $ea, $skip_next) = (0, 'OR', 0);
    foreach my $entry ( @$tree ) {
        $skip_next-- and next if $skip_next > 0;
        unless ( ref $entry ) {
            $ea = $entry;
            $skip_next++ if ($res && $ea eq 'OR') || (!$res && $ea eq 'AND');
            next;
        }

        my $cur;
        if ( ref $entry eq 'ARRAY' ) {
            $cur = $self->solve( $entry, $cb );
        } else {
            $cur = $cb->( $entry );
        }
        if ( $ea eq 'OR' ) {
            $res ||= $cur;
        } else {
            $res &&= $cur;
        }
    }
    return $res;
}

=head3 fsolve $tree $callback

Does in filter+solve in one go. Callback can return undef to filter out an operand,
and a defined boolean value to be used in solve.

Returns boolean result of the equation or undef if all operands have been filtered.

See also L</filter> and L</solve>.

=cut

sub fsolve {
    my ($self, $tree, $cb) = @_;

    my ($res, $ea, $skip_next) = (undef, 'OR', 0);
    foreach my $entry ( @$tree ) {
        $skip_next-- and next if $skip_next > 0;
        unless ( ref $entry ) {
            $ea = $entry;
            $skip_next++ if ($res && $ea eq 'OR') || (!$res && $ea eq 'AND');
            next;
        }

        my $cur;
        if ( ref $entry eq 'ARRAY' ) {
            $cur = $self->fsolve( $entry, $cb );
        } else {
            $cur = $cb->( $entry );
        }
        if ( defined $cur ) {
            $res ||= 0;
            if ( $ea eq 'OR' ) {
                $res ||= $cur;
            } else {
                $res &&= $cur;
            }
        } else {
            $skip_next++ unless defined $res;
        }
    }
    return $res;
}

1;

=head1 AUTHORS

Ruslan Zakirov E<lt>ruz@cpan.orgE<gt>, Robert Spier E<lt>rspier@pobox.comE<gt>

=head1 COPYRIGHT

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
