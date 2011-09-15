package Array::Find;
# ABSTRACT: Find items in array, with several options

use 5.010;
use strict;
use warnings;

use List::Util qw(shuffle);

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(find_in_array);

our %SPEC;

$SPEC{find_in_array} = {
    summary       => 'Find items in array, with several options',
    description   => <<'_',

find_in_array looks for one or more items in one or more arrays and return an
array containing all or some results (empty arrayref if no results found). You
can specify several options, like maximum number of results, maximum number of
comparisons, searching by suffix/prefix, case sensitivity, etc. Consult the list
of arguments for more details.

Currently, items are compared using the Perl's eq operator, meaning they only
work with scalars and compare things asciibetically.

_
    args          => {
        item             => ['str' => {
            summary      => 'Item to find',
            description  => <<'_',

Currently can only be scalar. See also 'items' if you want to find several items
at once.

_
            arg_pos      => 0,
        }],
        array            => ['array' => {
            summary      => 'Array to find items in',
            description  => <<'_',

See also 'arrays' if you want to find in several arrays. Array elements can be
undef and will only match undef.

_
            arg_pos      => 1,
        }],
        items            => ['array' => {
            of           => 'str',
            summary      => "Just like 'item', except several",
            description  => <<'_',

Use this to find several items at once. Elements can be undef if you want to
search for undef.

Example: find_in_array(items => ["a", "b"], array => ["b", "a", "c", "a"]) will
return result ["b", "a", "a"].

_
        }],
        arrays            => ['array' => {
            of           => 'array', # XXX ['array*'=>{of=>'str'}]
            summary      => "Just like 'array', except several",
            description  => <<'_',

Use this to find several items at once.

Example: find_in_array(item => "a", arrays => [["b", "a"], ["c", "a"]]) will
return result ["a", "a"].

_
        }],
        max_result       => ['int' => {
            summary      => "Set maximum number of results",
            description  => <<'_',

0 means unlimited (find in all elements of all arrays).

+N means find until results have N items. Example: find_in_array(item=>'a',
array=>['a', 'b', 'a', 'a'], max_result=>2) will return result ['a', 'a'].

-N is useful when looking for multiple items (see 'items' argument). It means
 find until N items to look for have been found. Example:
 find_in_array(items=>['a','b'], array=>['a', 'a', 'b', 'b'], max_results=>-2)
 will return result ['a', 'a', 'b']. As soon as 2 items to look for have been
 found it will stop.

_
        }],
        max_compare      => ['int' => {
            summary      => "Set maximum number of comparison",
            description  => <<'_',

Maximum number of elements in array(s) to look for, 0 means unlimited. Finding
will stop as soon as this limit is reached, regardless of max_result. Example:
find(item=>'a', array=>['q', 'w', 'e', 'a'], max_compare=>3) will not return
result.

_
        }],
        ci               => ['bool' => {
            default      => 0,
            summary      => "Set case insensitive",
        }],
        mode             => ['str' => {
            in           => ['exact', 'prefix', 'suffix', 'infix',
                             'prefix|infix', 'prefix|suffix',
                             'prefix|infix|suffix', 'infix|suffix',
                             'regex'],
            default      => 'exact',
            summary      => "Comparison mode",
            description  => <<'_',

Exact match is the default, will only match 'ap' with 'ap'. Prefix matching will
also match 'ap' with 'ap', 'apple', and 'apricot'. Suffix matching will match
'le' with 'le' and 'apple'. Infix will only match 'ap' with 'claps' and not with
'ap', 'clap', or 'apple'. Regex will regard item as a regex and perform a regex
match on each element of array.

See also 'word_sep' which affects prefix/suffix/infix matching.
_
        }],
        word_sep         => ['str' => {
            summary      => "Define word separator",
            arg_aliases  => {
                ws => {},
            },
            description  => <<'_',

If set, item and array element will be regarded as a separated words. This will
affect prefix/suffix/infix matching. Example, with '.' as the word separator
and 'a.b' as the item, prefix matching will 'a.b', 'a.b.', and 'a.b.c'
(but not 'a.bc'). Suffix matching will match 'a.b', '.a.b', 'c.a.b' (but
not 'ca.b'). Infix matching will match 'c.a.b.c' and won't match 'a.b',
'a.b.c', or 'c.a.b'.

_
        }],
        unique           => ['bool' => {
            summary      => "Whether to return only unique results",
            arg_aliases  => {
                u => {},
            },
            description  => <<'_',
If set to true, results will not contain duplicate items.
_
        }],
        shuffle          => ['bool' => {
            summary      => "Shuffle result",
        }],
    },
    result_naked => 1,
};
sub find_in_array {
    my %args = @_;

    # XXX schema
    my @items;
    push @items ,   $args{item}    if exists $args{item};
    push @items , @{$args{items}}  if exists $args{items};

    my @arrays;
    push @arrays,   $args{array}   if exists $args{array};
    push @arrays, @{$args{arrays}} if exists $args{arrays};

    my $ci          = $args{ci};
    my $mode        = $args{mode} // 'exact';
    my $mode_prefix = $mode =~ /prefix/;
    my $mode_infix  = $mode =~ /infix/;
    my $mode_suffix = $mode =~ /suffix/;
    my $ws          = $args{word_sep} // $args{ws};
    $ws             = undef if defined($ws) && $ws eq '';
    $ws             = lc($ws) if defined($ws) && $ci;
    my $ws_len      = defined($ws) ? length($ws) : undef;

    my $max_result  = $args{max_result};
    my $max_compare = $args{max_compare};

    my $unique      = $args{unique} // 0;

    my $num_compare;
    my %found_items; # for tracking which items have been found, for -max_result
    my @matched_els; # to avoid matching the same array element with multi items
    my @res;
    my %res;  # for unique

  FIND:
    for my $i (0..$#items) {
        my $item = $ci ? lc($items[$i]) : $items[$i];
        if ($mode eq 'regex') {
            $item = qr/$item/ if ref($item) ne 'Regexp';
            $item = $ci ? qr/$item/i : $item; # XXX turn off i if !$ci
        }
        my $item_len = defined($item) ? length($item) : undef;

        for my $ia (0..$#arrays) {
            my $array = $arrays[$ia];
            for my $iel (0..@$array-1) {

                next if $matched_els[$ia] && $matched_els[$ia][$iel];
                $num_compare++;
                my $el0 = $array->[$iel];
                my $el = $ci ? lc($el0) : $el0;
                my $match;

                if (!defined($el)) {
                    $match = !defined($item);
                } elsif (!defined($item)) {
                    $match = !defined($el);
                } elsif ($mode eq 'exact') {
                    $match = $item eq $el;
                } elsif ($mode eq 'regex') {
                    $match = $el =~ $item;
                } else {
                    my $el_len = length($el);

                    if ($mode_prefix) {
                        my $idx = index($el, $item);
                        if ($idx >= 0) {
                            if (defined($ws)) {
                                $match ||=
                                    # left side matches ^
                                    $idx == 0 &&
                                    # right side matches $ or
                                    ($item_len+$idx == $el_len ||
                                    # ws
                                    index($el, $ws, $item_len+$idx) ==
                                        $item_len+$idx);
                            } else {
                                $match ||= $idx == 0;
                            }
                        }
                    }

                    if ($mode_infix && !$match) {
                        my $idx = index($el, $item);
                        if ($idx >= 0) {
                            if (defined($ws)) {
                                $match ||=
                                    # right side matches ws
                                    index($el, $ws, $item_len+$idx) ==
                                        $item_len+$idx &&
                                    # left-side matches ws
                                    $idx >= $ws_len &&
                                       index($el, $ws, $idx-$ws_len) ==
                                           $idx-$ws_len;
                            } else {
                                $match ||= $idx > 0 && $idx < $el_len-$item_len;
                                if (!$match) {
                                    if ($idx == 0) {
                                        # a -> aab should match
                                        my $idx2 = index($el, $item, 1);
                                        $match ||= $idx2 > -1 &&
                                            $idx2 < $el_len-$item_len;
                                    } else {
                                        # a -> baa should match
                                        my $idx2 = index(substr($el, 1), $item);
                                        $match ||= $idx2 > -1 &&
                                            $idx2 < $el_len-$item_len-1;
                                    }
                                }
                            }
                        }
                    }

                    if ($mode_suffix && !$match) {
                        my $idx = rindex($el, $item);
                        if ($idx >= 0) {
                            if (defined($ws)) {
                                $match ||=
                                    # right side matches $
                                    $idx == $el_len-$item_len &&
                                    # left-side matches ^ or
                                    ($idx == 0 ||
                                    # ws
                                    $idx >= $ws_len &&
                                        index($el, $ws, $idx-$ws_len) ==
                                            $idx-$ws_len);
                            } else {
                                $match ||= $idx == $el_len-$item_len;
                            }
                        }
                    }
                }

                if ($match) {
                    unless ($unique && $res{$el}) {
                        push @res, $el0;
                    }
                    $res{$el} = 1 if $unique;
                    $matched_els[$ia] //= [];
                    $matched_els[$ia][$iel] = 1;
                }
                if (defined($max_compare) && $max_compare != 0) {
                    last FIND if $num_compare >= $max_compare;
                }
                if ($match) {
                    if (defined($max_result) && $max_result != 0) {
                        if ($max_result > 0) {
                            last FIND if @res >= $max_result;
                        } else {
                            $found_items{$i} //= 1;
                            last FIND if
                                scalar(keys %found_items) >= -$max_result;
                        }
                    }
                }

            }
        }
    }

    if ($args{shuffle}) {
        @res = shuffle(@res);
    }

    \@res;
}

1;
__END__

=head1 SYNOPSIS

 use Array::Find qw(find_in_array);
 use Data::Dump;

 dd find_in_array(
     items      => [qw/a x/],
     array      => [qw/a b d a y x/],
     max_result => 2,
 ); # ['a', 'a']

 # return unique results
 dd find_in_array(
     items      => [qw/a x/],
     array      => [qw/a b d a y x/],
     max_result => 2,
 ); # ['a', 'x']

 # find by prefix (or suffix, with/without word separator), in multiple arrays
 dd find_in_array(
     item       => 'a.b',
     mode       => 'prefix',
     word_sep   => '.',
     arrays     => [
         [qw/a a.b. a.b a.bb/],
         [qw/a.b.c b.c.d/],
     ],
 ); # ['a.b.', 'a.b', 'a.b.c']


=head1 DESCRIPTION

This module provides one subroutine: C<find_in_array> to find items in array.

This module uses L<Sub::Spec> framework, which means you can switch from named
arguments to positional, apply execution time limits, run the subroutine from
the command line, etc. Refer to Sub::Spec documentation for more details.


=head1 FUNCTIONS

None of the functions are exported by default, but they are exportable.


=head1 SEE ALSO

L<List::Util>, L<List::MoreUtils>

L<Sub::Spec>

=cut

