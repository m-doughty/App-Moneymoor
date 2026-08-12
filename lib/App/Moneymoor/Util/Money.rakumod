=begin pod

=head1 NAME

App::Moneymoor::Util::Money - integer-pence money formatting and
parsing.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Util::Money;

say format-pence(1234);            # £12.34
say format-pence(-1234);           # -£12.34
say format-pence(0);               # £0.00
say format-pence(123456789);       # £1,234,567.89
say format-pence(500, :!symbol);   # 5.00
say format-pence(500, :plus);      # +£5.00

say parse-pence('£12.34');         # 1234
say parse-pence('12.3');           # 1230
say parse-pence('-1,234.56');      # -123456
say parse-pence('(4.20)');         # -420   (accountant negatives)

my $bad = parse-pence('twelve');
say $bad ~~ Failure;               # True
$bad.so;                           # mark handled

# One call at startup switches every format and every parse in the
# process over to the user's saved display settings:
set-money-locale(symbol => '€', decimal-mark => ',');

say format-pence(123456);          # €1.234,56
say parse-pence('1.234,56');       # 123456
say money-decimal-mark();          # ,

=end code

=head1 DESCRIPTION

Every monetary value in Moneymoor is an C<Int> number of pence.
There are no C<Rat>s and no C<Num>s in the engine, the schema, or the
gateways: a budget that has to prove C<Σ available + RTA == Σ cash>
cannot afford a representation whose addition is lossy.

This module is the only place where pence meet human-readable text.
It is deliberately tiny: no DB, no I/O, and — apart from the two
display registers below — no state.

=head2 THE LOCALE REGISTERS

Two module-level registers decide how a number I<looks> and how a
typed one is I<read back>:

=item the B<currency symbol> — C<£> (default), C<$> or C<€>. Display
      only. This is emphatically B<not> multi-currency support: all
      three behave identically and no conversion of any kind happens,
      because multi-currency turns the master invariant
      C<Σ available + RTA == Σ cash> into a per-currency sum, which is
      an engine change rather than a formatting one.
=item the B<decimal mark> — C<.> (default) or C<,>. The thousands
      group separator is always I<the other one>, so the two settings
      that a locale changes together are one setting here and cannot
      be put into a state where both roles want the same character.

C<set-money-locale> writes both, and is meant to be called B<once, at
startup>, from C<App::Moneymoor::UI.run> with the values
C<App::Moneymoor::Config> loaded (and again from the Settings dialog,
on the UI thread, when the user changes them). Everything else in the
app calls C<format-pence> / C<parse-pence> with no locale argument:
threading a locale through 37 formatting call sites would buy nothing,
because there is exactly one display locale per process and it never
varies I<within> a render.

That does mean this module is pure only I<given> the registers. They
are plain module-scoped C<my> variables with no lock: writing them
from a background thread while a render is walking the tree would be a
data race, so don't — the setter is a startup/UI-event operation, not
something to call per row.

=begin code :lang<raku>
set-money-locale(symbol => '$', decimal-mark => '.');
format-pence(123456);            # $1,234.56

set-money-locale(symbol => '€', decimal-mark => ',');
format-pence(123456);            # €1.234,56
format-pence(-5);                # -€0,05

set-money-locale;                 # back to the £ / . default
=end code

=head2 FORMATTING

C<format-pence> renders the sign I<outside> the currency symbol
(C<-£12.34>, not C<£-12.34>) which is how UK statements are written,
and always emits exactly two decimal places. Thousands separators are
on by default because budget screens are full of five-figure numbers:

=begin code :lang<raku>
format-pence(-100)                       # -£1.00
format-pence(99)                         # £0.99
format-pence(-1)                         # -£0.01
format-pence(100000, :!separators)       # £1000.00
format-pence(-2500, :!symbol)            # -25.00
format-pence(2500, :plus)                # +£25.00     (:plus is
format-pence(-2500, :plus)               # -£25.00      sign-always)
=end code

C<:plus> exists for "assigned" columns where a UI wants an explicit
sign on positive movement; it never adds a C<+> to zero.

C<:!symbol> drops only the symbol; the decimal mark and the group
separator are the locale's either way, because a column header that
says "£" does not stop the number under it being a number.

=head2 PARSING

C<parse-pence> is forgiving about the shapes a human types and strict
about everything else. Accepted:

=item an optional leading or trailing sign (C<-5>, C<5->  is I<not>
      accepted; C<-> must lead)
=item an optional currency symbol before or after the sign — B<any> of
      C<£>, C<$>, C<€>, whatever the locale's symbol is. Input is
      where a user pastes a figure from somewhere else; refusing a
      C<$> because the display is set to C<£> would reject a string
      that has exactly one possible meaning
=item underscore thousands separators, and the locale's group
      separator, where they really are separating groups
      (C<1,234.56> and C<1_234.56> under a C<.> decimal mark,
      C<1.234,56> and C<1_234,56> under a C<,> one)
=item zero, one or two decimal digits after the locale's decimal mark
      (C<12>, C<12.3>, C<12.34>)
=item surrounding whitespace
=item parentheses for negatives (C<(12.34)> is C<-1234>), the
      accounting convention CSV exports still emit

Rejected — returning a C<Failure> rather than throwing, so callers can
test the result and give the user a message:

=item empty / whitespace-only input
=item three or more decimal digits (C<12.345>): silently rounding a
      user's typed precision is how budgets drift
=item anything with a character outside the accepted set
=item a bare decimal mark, or a value with more than one
=item a misplaced separator — trailing (C<'12,34,'>), doubled, or up
      against the decimal mark. Stripping those silently would read
      C<'12,34,'> as £1,234.00.
=item both a leading C<-> and parentheses

=head3 Strict grouping, and the wrong-locale typo

The group separator is accepted B<only> in exact groups of three:
C<\d ** 1..3 [ <sep> \d ** 3 ]+>. C<'1,50'> under a C<.> decimal mark
is therefore an error, not £150.00 and not £1.50.

That strictness is the whole point. The one mistake a user of this
setting will actually make is typing the other locale's number —
C<1,50> when the app is in C<.> mode, C<1.50> when it is in C<,> mode
— and both of those are I<plausible> under a lax reading, at 100x the
intended value. Refusing them turns a silent £150 assignment into a
message. For the same reason three digits after the decimal mark is
never re-read as a group: C<'1,000'> in C<,>-decimal mode fails with
an error that points at the group separator it should have used
(C<'1.000'>), rather than quietly deciding the user meant a thousand.

Round-tripping is exact in both directions, in either locale:
C<parse-pence(format-pence($p)) == $p> for every C<Int> C<$p>, and
C<format-pence(parse-pence($s))> re-renders any accepted string in
canonical form.

=head1 SUBROUTINES

=item C<format-pence(Int:D $pence, Bool :$symbol = True,
      Bool :$separators = True, Bool :$plus = False --> Str)>
=item C<parse-pence(Str:D $text --> Int)> — C<Failure> on malformed
      input.
=item C<set-money-locale(Str:D :$symbol = '£',
      Str:D :$decimal-mark = '.')> — set both display registers.
      B<Throws> (rather than failing) on a symbol outside C<£ $ €> or
      a mark outside C<. ,>: a bad locale is a programming error at a
      call site that has already validated its input, not user input
      to be reported. Called with no arguments it restores the
      defaults, which is what a test wants in a C<LEAVE>.
=item C<pence-symbol(--> Str)> — the currency symbol currently in
      force.
=item C<money-decimal-mark(--> Str)> — the decimal mark currently in
      force. The group separator is the other of C<.> / C<,>.
=item C<money-symbols(--> List)> / C<money-decimal-marks(--> List)> —
      the accepted values, in the order a settings picker should list
      them. Exported so C<Config> can validate a hand-edited file and
      the Settings dialog can build its C<Select> without either
      keeping a second copy of the whitelist.

=head1 SEE ALSO

=item L<App::Moneymoor::Config> — persists C<currency> and
      C<decimal_mark>.
=item L<App::Moneymoor::UI> — calls C<set-money-locale> once, right
      after the config loads, so the first frame is already in the
      user's locale.

=end pod

unit module App::Moneymoor::Util::Money;

#|( The symbols Moneymoor will render, in picker order. Purely a
    glyph choice: nothing in the engine knows a currency, and nothing
    converts between these. Multi-currency is explicitly out of scope
    — it changes the master invariant from a single sum into a
    per-currency sum, which is an engine change, not a formatting
    one. )
my constant MONEY-SYMBOLS = ('£', '$', '€');

#| The decimal marks, in picker order. The group separator is always
#| the other member of this pair, so there is no configuration in
#| which the two roles collide.
my constant DECIMAL-MARKS = ('.', ',');

# The display registers. See the LOCALE REGISTERS section of the Pod:
# set once at startup (and on a Settings save), read everywhere.
my Str $current-symbol   = MONEY-SYMBOLS[0];
my Str $current-decimal  = DECIMAL-MARKS[0];
my Str $current-group    = DECIMAL-MARKS[1];

our sub money-symbols(--> List)       is export { MONEY-SYMBOLS }
our sub money-decimal-marks(--> List) is export { DECIMAL-MARKS }

#|( Point every C<format-pence> and every C<parse-pence> in the
    process at a display locale. Defaults restore the C<£> / C<.>
    original, which is what a test's C<LEAVE> wants.

    Throws on an unknown symbol or mark rather than failing quietly:
    every caller (the config loader, the Settings dialog) validates
    against C<money-symbols> / C<money-decimal-marks> first, so
    reaching here with something else is a bug in the caller, and a
    silently-ignored locale would show up as a rendering mystery three
    screens away. )
our sub set-money-locale(
    Str:D :$symbol       = MONEY-SYMBOLS[0],
    Str:D :$decimal-mark = DECIMAL-MARKS[0],
    --> Nil
) is export {
    die "Unsupported currency symbol '$symbol' (expected one of "
            ~ MONEY-SYMBOLS.join(' ') ~ ')'
        unless MONEY-SYMBOLS.grep($symbol);
    die "Unsupported decimal mark '$decimal-mark' (expected one of "
            ~ DECIMAL-MARKS.join(' ') ~ ')'
        unless DECIMAL-MARKS.grep($decimal-mark);

    $current-symbol  = $symbol;
    $current-decimal = $decimal-mark;
    # Derived, never set independently: the separator a locale groups
    # with is by definition the character it does not point with.
    $current-group   = $decimal-mark eq DECIMAL-MARKS[0]
        ?? DECIMAL-MARKS[1] !! DECIMAL-MARKS[0];
    Nil
}

our sub pence-symbol(--> Str)       is export { $current-symbol  }
our sub money-decimal-mark(--> Str) is export { $current-decimal }

#| Group the integer part in threes: 1234567 -> "1,234,567" (or
#| "1.234.567"). Works on the absolute-value digit string, so the sign
#| never lands inside a group.
my sub group-digits(Str:D $digits --> Str) {
    return $digits if $digits.chars <= 3;
    my @out;
    my $rest = $digits;
    while $rest.chars > 3 {
        @out.unshift($rest.substr(*-3));
        $rest = $rest.substr(0, *-3);
    }
    @out.unshift($rest);
    @out.join($current-group);
}

our sub format-pence(
    Int:D $pence,
    Bool :$symbol      = True,
    Bool :$separators  = True,
    Bool :$plus        = False,
    --> Str
) is export {
    # abs() before the split so -1 renders as -£0.01 rather than
    # -£0.-1: integer division and modulo round towards -Inf in Raku,
    # which is correct for maths and wrong for typography.
    my Int $abs   = $pence.abs;
    my Int $whole = $abs div 100;
    my Int $part  = $abs mod 100;

    my Str $int-part = $separators ?? group-digits($whole.Str) !! $whole.Str;
    my Str $sign = do {
        if    $pence < 0 { '-' }
        elsif $plus && $pence > 0 { '+' }
        else  { '' }
    };

    $sign ~ ($symbol ?? $current-symbol !! '') ~ $int-part
          ~ $current-decimal ~ $part.fmt('%02d');
}

our sub parse-pence(Str:D $text --> Int) is export {
    my Str $s = $text.trim;
    return fail "Cannot parse empty money value" if $s eq '';

    # Accounting negatives: "(12.34)". Strip the parens and remember
    # the sign; a leading '-' as well is a contradiction, not a
    # double negative.
    my Bool $paren = False;
    if $s.starts-with('(') && $s.ends-with(')') {
        $paren = True;
        $s = $s.substr(1, *-1).trim;
    } elsif $s.contains('(') || $s.contains(')') {
        return fail "Malformed money value '$text' (unbalanced parentheses)";
    }

    my Bool $neg = False;
    if $s.starts-with('-') {
        return fail "Malformed money value '$text' (both '-' and parentheses)"
            if $paren;
        $neg = True;
        $s = $s.substr(1).trim;
    } elsif $s.starts-with('+') {
        $s = $s.substr(1).trim;
    }
    $neg = True if $paren;

    # Currency symbol may sit either side of the sign; by now the sign
    # is gone, so a leading symbol is all that is left to strip. Every
    # symbol is accepted regardless of the display setting — see the
    # PARSING section: a pasted '$12.34' has one meaning.
    for MONEY-SYMBOLS.list -> $sym {
        if $s.starts-with($sym) {
            $s = $s.substr($sym.chars).trim;
            last;
        }
    }

    # Thousands separators are noise once the number is anchored — but
    # only where they are actually separating something. A trailing or
    # doubled separator is a typo, and stripping it silently would turn
    # '12,34,' into £1,234.00.
    #
    # A Str interpolated into a regex matches literally, so the locale
    # characters need no escaping even when the mark is '.'.
    return fail "Malformed money value '$text' (misplaced '_')"
        if $s ~~ / ^ '_' | '_' $ | '__' | '_' $current-decimal
                  | $current-decimal '_' /;
    $s = $s.subst('_', '', :g);

    if $s.contains($current-group) {
        return fail "Malformed money value '$text' "
                ~ "(misplaced '$current-group')"
            unless $s ~~ / ^ \d ** 1..3 [ $current-group \d ** 3 ]+
                             [ $current-decimal \d ** 1..2 ]? $ /;
        $s = $s.subst($current-group, '', :g);
    }

    unless $s ~~ / ^ (\d+) [ $current-decimal (\d ** 1..2) ]? $ / {
        # The one malformed shape worth a specific message: exactly
        # three digits after the decimal mark is what typing the other
        # locale's grouping looks like ('1,000' in ,-decimal mode), and
        # it is 100x the value the user meant.
        if $s ~~ / ^ \d+ $current-decimal \d ** 3 $ / {
            return fail "Malformed money value '$text' (three digits "
                ~ "after the decimal mark '$current-decimal'; thousands "
                ~ "are grouped with '$current-group' — did you mean '"
                ~ $s.subst($current-decimal, $current-group) ~ "'?)";
        }
        return fail "Malformed money value '$text'";
    }

    my Int $whole = +$0;
    my Int $part  = do with $1 {
        # ".5" means 50 pence, ".05" means 5 — pad on the right.
        my Str $d = ~$_;
        +($d.chars == 1 ?? $d ~ '0' !! $d);
    } else {
        0
    };

    my Int $pence = $whole * 100 + $part;
    $neg ?? -$pence !! $pence;
}
