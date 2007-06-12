
=head1 NAME

Parse::BooleanLogic - parser of boolean expressions

=head1 SYNOPSIS
    
    my $parser = new Parse::BooleanLogic;
    my $tree = $parser->as_array( string => 'x = 10' );
    $tree = $parser->as_array( string => 'x = 10 OR (x > 20 AND x < 30)' );

    $parser->parse(
        string   => 'x = 10 OR (x > 20 AND x < 30)',
        callback => {
            open_paren      => sub { ... },
            binary_operator => sub { ... },
            condition       => sub { ... },
            close_paren     => sub { ... },
            error           => sub { ... },
        },
    );

=head1 DESCRIPTION

This module is quite fast parser for boolean expressions. Original it's been writen for
Request Tracker for parsing SQL like expressions and it's still capable to, but
it can be used to parse other boolean logic sentences with conditions
(LEFT_OPERAND OPERATOR RIGHT_OPERAND) joined with binary operators (BINARY_OPERATOR) and
grouped and nested using parentheses (OPEN_PAREN and CLOSE_PAREN).

=head1 METHODS

=head2 as_array

Takes a string and parses it into perl structure, where parentheses reparesented using
array references, conditions are hash references with three pairs: left, operator and
right, when binary operators are simple scalars. So string C<x = 10 OR (x > 20 AND x < 30)>
is parsed into the following structure:

    [
        { left => 'x', operator => '=', right => 10 },
        'OR',
        [
            { left => 'x', operator => '>', right => 20 },
            'AND',
            { left => 'x', operator => '<', right => 30 },
        ]
    ]

=head2 parse

Takes named arguments: string and callback. Where the first one is scalar with
expression, the latter is a reference to hash with callbacks: open_paren, binary_operator
condition, close_paren and error. Callback for errors is optional and parser dies if
it's omitted. Each callback is called when parser finds corresponding element in the
string. In all cases except of condition the current match is passed as argument into
the callback. Into callback for conditions three arguments are passed: left operand,
operator and right operand.

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
    $callback{'close_paren'}     = sub { $node = pop @pnodes };

    # push binary operators as is and conditions as hash references
    $callback{'binary_operator'} = sub { push @$node, $_[0] };
    $callback{'condition'}       = sub { push @$node, { l => $_[0], op => $_[1], r => $_[2] } };

    # run parser
    $parser->parse( string => $string, callback => \%callback );

    return $tree;

Using this method you can build other representations of an expression.

=cut

use strict;
use warnings;

package Parse::BooleanLogic;

our $VERSION = '0.01';

use constant LEFT            => 1;
use constant RIGHT           => 2;
use constant OPERATOR        => 4;
use constant BINARY_OPERATOR => 8;
use constant OPEN_PAREN      => 16;
use constant CLOSE_PAREN     => 32;
my @tokens = qw[LEFT RIGHT OPERATOR BINARY_OPERATOR OPEN_PAREN CLOSE_PAREN];

use Regexp::Common qw(delimited);
my $re_delim           = qr[$RE{delimited}{-delim=>qq{\'\"}}];

my $re_left            = qr[[{}\w\.]+|$re_delim];
my $re_right           = qr[\d+|NULL|$re_delim];
my $re_operator        = qr[[!><]?=|[><]|(?i:IS(?: NOT)?)|(?i:(?:NOT )?LIKE)];
my $re_binary_operator = qr[(?i:AND|OR)];
my $re_open_paren      = qr[\(];
my $re_close_paren     = qr[\)];

sub new {
    my $proto = shift;
    return bless {}, ref($proto) || $proto;
}

{ # static variables

my ($tree, $node, @pnodes);
my %callback;
$callback{'open_paren'} = sub {
    push @pnodes, $node;
    push @{ $pnodes[-1] }, $node = []
};
$callback{'close_paren'}     = sub { $node = pop @pnodes };
$callback{'binary_operator'} = sub { push @$node, $_[0] };
$callback{'condition'} = sub {
    push @$node, { left => $_[0], operator => $_[1], right => $_[2] }
};

sub as_array {
    my $self = shift;
    my $string = shift;

    $node = $tree = [];
    @pnodes = ();

    $self->parse(string => $string, callback => \%callback);

    return $tree;
} }

sub parse {
    my $self = shift;
    my %args = (
        string => '',
        callback => {},
        @_
    );
    my ($string, $cb) = @args{qw(string callback)};
    $string = '' unless defined $string;

    my $want = LEFT | OPEN_PAREN;
    my $last = 0;

    my $depth = 0;
    my ($key, $op, $value) = ("", "", "");

    # order of matches in the RE is important.. op should come early,
    # because it has spaces in it.    otherwise "NOT LIKE" might be parsed
    # as a keyword or value.

    while ( $string =~ /(
                        $re_binary_operator
                        |$re_operator
                        |$re_left
                        |$re_right
                        |$re_open_paren
                        |$re_close_paren
                       )/iogx )
    {
        my $match = $1;

        # Highest priority is last
        my $current = 0;
        $current = LEFT            if ($want & LEFT)            && $match =~ /^$re_left$/io;
        $current = RIGHT           if ($want & RIGHT)           && $match =~ /^$re_right$/io;
        $current = OPERATOR        if ($want & OPERATOR)        && $match =~ /^$re_operator$/io;
        $current = BINARY_OPERATOR if ($want & BINARY_OPERATOR) && $match =~ /^$re_binary_operator$/io;
        $current = OPEN_PAREN      if ($want & OPEN_PAREN)      && $match =~ /^$re_open_paren$/io;
        $current = CLOSE_PAREN     if ($want & CLOSE_PAREN)     && $match =~ /^$re_close_paren$/io;

        unless ($current && $want & $current) {
            my $tmp = substr($string, 0, pos($string)- length($match));
            $tmp .= '>'. $match .'<--here'. substr($string, pos($string));
            my $msg = "Wrong expression, expecting a ". $self->bitmask_to_string($want) ." in '$tmp'";
            $cb->{'error'}? $cb->{'error'}->($msg): die $msg;
            return;
        }

        # State Machine:
        if ( $current & OPEN_PAREN ) {
            $cb->{'open_paren'}->( $match );
            $depth++;
            $want = LEFT | OPEN_PAREN;
        }
        elsif ( $current & CLOSE_PAREN ) {
            $cb->{'close_paren'}->( $match );
            $depth--;
            $want = BINARY_OPERATOR;
            $want |= CLOSE_PAREN if $depth;
        }
        elsif ( $current & BINARY_OPERATOR ) {
            $cb->{'binary_operator'}->( $match );
            $want = LEFT | OPEN_PAREN;
        }
        elsif ( $current & LEFT ) {
            $key = $match;
            $want = OPERATOR;
        }
        elsif ( $current & OPERATOR ) {
            $op = $match;
            $want = RIGHT;
        }
        elsif ( $current & RIGHT ) {
            $value = $match;

            # Remove surrounding quotes and unescape escaped
            # characters from $key, $match
            for ( $key, $value ) {
                if ( /^$re_delim$/o ) {
                    substr($_,0,1) = "";
                    substr($_,-1,1) = "";
                }
                s!\\(.)!$1!g;
            }

            $cb->{'condition'}->( $key, $op, $value );

            ($key,$op,$value) = ("","","");
            $want = BINARY_OPERATOR;
            $want |= CLOSE_PAREN if $depth;
        }

        $last = $current;
    }

    unless ( !$last || $last & (CLOSE_PAREN | RIGHT) ) {
        my $msg = "Incomplete query, last element ("
            . $self->bitmask_to_string($last)
            . ") is not CLOSE_PAREN or RIGHT in '$string'";
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

1;

=head1 AUTHORS

Ruslan Zakirov E<lt>ruz@cpan.orgE<gt>, Robert Spier E<lt>rspier@pobox.comE<gt>

=head1 COPYRIGHT

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
