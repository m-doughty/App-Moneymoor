unit module App::Moneymoor::View::HintBar;

=begin pod

=head1 NAME

App::Moneymoor::View::HintBar - the one canonical keybind-hint table,
rendered as styled C<RichText> spans that truncate a group at a time.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::View::HintBar;

# Every hint the app can show, keyed by context.
hint-contexts();                  # (budget generic login reconcile
                                   #  register reports sidebar)
hint-groups('sidebar').head;      # Enter => open

# The footer paints these straight into a Selkie::Widget::RichText.
$footer.set-content(
    hint-spans('budget', $footer.cols, theme => $main.theme,
               icons => $main.icons),
);

=end code

=head1 DESCRIPTION

The bottom line of every C<App::Moneymoor> screen is a keybind
cheat-sheet that changes with focus. C<Screen::Main> owns the footer
widget and C<Screen::Main::Subscriptions> decides which context is
active, so this module owns the one C<%HINTS> table and the one
renderer rather than letting the two hand-roll their own copies —
one flat C<fg-dim> line each, hard-truncated by the terminal edge
with no indication that anything had been cut off, is the failure
mode this exists to avoid.

This module owns all of it: one C<%HINTS> table, one renderer.

=head2 Contexts

A B<context> is a bare string key — C<'budget'>, C<'register'> — not
a style bundle and not a span list. That matters: the screens pick the
context inside a store subscription, and
L<Selkie::Store>'s change digest keys objects by C<.WHICH>, so a
selector that returned freshly-built C<Selkie::Style> or C<Span>
objects would read as "changed" on B<every> tick and re-push the whole
footer every frame. Selectors return the key; the callback builds the
spans.

=item C<generic> — no recognised focus target: the app-wide keys only.
=item C<login> — the login screen's three keys. Rendered once, at
      build time, into the fixed-width dialog's bottom line: unlike the
      main screens, C<Screen::Login> never resizes, so it neither
      subscribes to a context nor repaints on resize.
=item C<budget> — the budget tab's envelope table.
=item C<register> — the accounts tab's transaction register.
=item C<reconcile> — register focus while reconcile mode (C<Ctrl+R>)
      is active; overrides C<register> for the duration.
=item C<sidebar> — the accounts tab's account list.
=item C<reports> — the reports tab.

An unrecognised context falls back to C<generic> rather than throwing —
same fallback semantics as C<App::Moneymoor::View::EmptyState> and
C<App::Moneymoor::Themes::load>.

=head2 Truncation

Hints are dropped a B<whole group at a time>, never mid-group: half a
keybind ("Ctrl+1..0 pers") is worse than no keybind. Trailing groups
are dropped until what remains — plus the C<… ^h> tail — fits the
requested width. The tail says two things at once: "there is more" and
"Ctrl+H shows all of it". It is C<^h> rather than C<?> because C<?> is
deliberately B<not> a global bind (a payee name or memo field may
legitimately contain one — see the comment on the C<ctrl+h> bind in
C<Screen::Main::Keybinds>).

Widths narrower than a single group plus the tail degrade to the tail
alone; a width of zero or less returns no spans at all. Neither throws
— the footer is laid out by whatever the terminal happens to be, and a
one-column terminal must not take the app down.

=head2 Rendering contract

Each group renders as C<< key label >> — a key span in the palette
C<accent>, bold, then a label span in C<fg-dim> carrying the separating
space. Groups are joined by a C<·> in C<fg-dimmer>, and the tail is
C<fg-dimmer> too, so the eye lands on the keys first and the dividers
disappear.

The returned spans total B<at most> C<$width> columns
(C<$width - $reserve> when a reservation is given), so they occupy
exactly one line of a C<Selkie::Widget::RichText>. There is no leading
margin space: C<RichText>'s wrapper drops a whitespace token at column
0, so a margin span would be silently eaten — the bar starts flush
left.

=head1 EXAMPLES

=head2 Repainting a footer

Width comes from the widget, because that is what the spans have to fit
in; a screen that has not been laid out yet reports zero columns, so
callers substitute a sane default and repaint when the real width
arrives (both screens do this from an C<App.on-resize> callback):

=begin code :lang<raku>

method !repaint-hints() {
    my $w = $!hint-footer.cols > 0 ?? $!hint-footer.cols !! 80;
    $!hint-footer.set-content(
        hint-spans($!hint-context, $w, theme => $!theme, icons => self.icons),
    );
}

=end code

=head2 Reserving room on the right

C<:reserve> subtracts columns before any fitting is done, for a
right-aligned segment the caller paints itself (a clock, a sync
indicator). The hint groups simply behave as though the terminal were
that much narrower:

=begin code :lang<raku>

my @spans = hint-spans('budget', 100, :$theme, reserve => 12);
@spans».text.join.chars;      # <= 88

=end code

=head2 Inspecting the table

C<hint-groups> is the table itself, so a test (or a future help
overlay) can assert against the pairs rather than parsing a rendered
string:

=begin code :lang<raku>

for hint-contexts() -> $ctx {
    for hint-groups($ctx) -> $group {
        say "$ctx: {$group.key} = {$group.value}";
    }
}

=end code

=head1 EXPORTS

=item C<hint-contexts(--> List)> — every context key, sorted.
=item C<hint-groups(Str $context --> List)> — that context's ordered
      C<< key => label >> pairs, falling back to C<generic>.
=item C<hint-spans(Str $context, Int $width, :$theme!, :$icons,
      :$reserve --> List)> — the C<Selkie::Widget::RichText::Span>s to
      paint.

=head1 SEE ALSO

=item L<App::Moneymoor::Screen::Main::Subscriptions> — routes focus to a
      context key (C<hint-for-focus>).
=item L<App::Moneymoor::View::ModalChrome> — the modals' equivalent
      canonical style bundle.

=end pod

use Selkie::Style;
use Selkie::Widget::RichText::Span;

use App::Moneymoor::Theme;
use App::Moneymoor::Service::Icons;

# The canonical hint table. Ordered by importance-to-the-user, because
# truncation eats from the tail: the keys a beginner needs most sit
# leftmost and survive the narrowest useful terminal.
#
# Every pair here is checked against a real binding in
# `Screen::Main::Keybinds` (or a Selkie default — Tab / Shift+Tab / Esc /
# Ctrl+Q are framework-level, see Selkie::App.!register-default-keybinds).
# Bindings that exist but aren't advertised here are a deliberate omission
# for line-length reasons, not an oversight: in the budget context, `h`
# (hide envelope), `u` (toggle show-hidden) and `Enter` (fold a group /
# assign to an envelope, which `a` already advertises); in the register
# context, `Enter` as an alias for `e`.
#
# t/69 checks the other direction — that every key this table DOES
# advertise for the budget context is a key Screen::Budget or
# Screen::Main::Keybinds actually binds.
my %HINTS =
    # No recognised focus target — the keys that work everywhere.
    generic => (
        'Tab'       => 'focus',
        'Ctrl+G'    => 'diagnostics',
        'Ctrl+Q'    => 'quit',
    ),
    # Login screen. Three keys is the whole of it: the dialog is
    # fixed-width, so nothing here is ever truncated.
    login => (
        'Enter'     => 'unlock',
        'Ctrl+N'    => 'new budget',
        'Tab'       => 'switch',
    ),
    # Budget tab — the envelope table.
    budget => (
        'a'         => 'assign',
        'm'         => 'move',
        'f'         => 'fund',
        'x'         => 'explain',
        'n/g'       => 'new',
        'e'         => 'edit',
        'd'         => 'delete',
        '[ ]'       => 'period',
        'i'         => 'detail',
        'Ctrl+H'    => 'help',
    ),
    # Accounts tab — the transaction register.
    register => (
        'n'         => 'new',
        'e'         => 'edit',
        'c'         => 'cleared',
        't'         => 'transfer',
        'Ctrl+R'    => 'reconcile',
        'd'         => 'delete',
        'Ctrl+H'    => 'help',
    ),
    # Register focus while reconcile mode is active — overrides
    # `register` for the duration.
    reconcile => (
        'c'         => 'cleared',
        'Enter'     => 'finish',
        'Esc'       => 'exit',
        'Ctrl+H'    => 'help',
    ),
    # Accounts tab — the account list.
    sidebar => (
        'Enter'     => 'open',
        'n'         => 'new account',
        'e'         => 'edit',
        'c'         => 'close',
        'Ctrl+H'    => 'help',
    ),
    # Reports tab.
    reports => (
        'b'         => 'by group',
        '[ ]'       => 'period',
        'Ctrl+H'    => 'help',
    );

# Separator between two groups, and the "there is more, press Ctrl+H"
# tail. TAIL-LEAD is the single space that divides the tail from the
# last surviving group; it is not emitted when the tail stands alone.
my constant SEP-TEXT  = ' · ';
my constant TAIL-TEXT = '… ^h';
my constant TAIL-LEAD = ' ';

#| Every context key the table defines, sorted for stable iteration.
our sub hint-contexts(--> List) is export { %HINTS.keys.sort.List }

#|( The ordered C<< key => label >> pairs for C<$context>, or
    C<generic>'s if the context is unknown / undefined — the footer is
    never worth an exception. )
our sub hint-groups(Str $context --> List) is export {
    # `//` would be wrong here: an empty-string context is *defined*,
    # so it has to be tested for emptiness before the table lookup.
    my $groups = ($context // '').chars ?? %HINTS{$context} !! Nil;
    ($groups // %HINTS<generic>).list.List;
}

# Columns one group occupies once rendered: key, one space, label. A
# label-less group (none ship today, but the renderer tolerates one)
# costs just the key.
sub group-cols($group --> Int) {
    my $label = ($group.value // '').Str;
    $group.key.chars + ($label.chars ?? 1 + $label.chars !! 0);
}

# Spans for the first $n groups, separators included, no tail.
sub group-spans(@groups, Int $n, $key-style, $label-style, $sep-style --> List) {
    my @out;
    for ^$n -> $i {
        @out.push(Selkie::Widget::RichText::Span.new(
            text => SEP-TEXT, style => $sep-style,
        )) if $i > 0;
        my $group = @groups[$i];
        @out.push(Selkie::Widget::RichText::Span.new(
            text => $group.key, style => $key-style,
        ));
        my $label = ($group.value // '').Str;
        @out.push(Selkie::Widget::RichText::Span.new(
            text => " $label", style => $label-style,
        )) if $label.chars;
    }
    @out.List;
}

#|( Render C<$context>'s hints into at most C<$width> columns (less
    C<:reserve>) as C<Selkie::Widget::RichText::Span>s.

    Groups are dropped from the end until the remainder plus a C<… ^h>
    tail fits; the tail appears if and only if something was dropped.
    Too narrow for even one group ⇒ the tail alone; no columns at all
    (C<$width - $reserve E<lt>= 0>) ⇒ an empty list. Never throws.

        hint-spans('budget', 120, :$theme)».text.join;
        # 'a assign · m move · x explain · n/g new · e edit · …'

    C<:icons> takes the active C<App::Moneymoor::Icons> tier. No hint
    names a glyph today, so it changes nothing — it is on the signature
    so every call site passes the tier the same way it does to
    C<empty-state-for> and the row builders in C<View::BudgetRow> /
    C<View::RegisterRow>, and a glyph-bearing hint can be added later
    without touching the screens that call this. )
our sub hint-spans(
    Str $context,
    Int $width,
    App::Moneymoor::Theme :$theme!,
    :$icons = icons(),
    Int :$reserve = 0,
    --> List
) is export {
    my Int $avail = $width - ($reserve max 0);
    return () unless $avail > 0;

    my $key-style   = Selkie::Style.new(fg => $theme.accent, bold => True);
    my $label-style = Selkie::Style.new(fg => $theme.fg-dim);
    my $sep-style   = Selkie::Style.new(fg => $theme.fg-dimmer);

    my @groups = hint-groups($context);

    # Everything fits: no tail, nothing was hidden.
    my Int $full = @groups.map(&group-cols).sum
                 + (SEP-TEXT.chars * ((@groups.elems - 1) max 0));
    if @groups.elems && $full <= $avail {
        return group-spans(@groups, @groups.elems,
                           $key-style, $label-style, $sep-style);
    }

    # Otherwise: the longest whole-group prefix that leaves room for
    # the tail.
    my Int $tail-cols = TAIL-LEAD.chars + TAIL-TEXT.chars;
    my Int $kept = 0;
    my Int $used = 0;
    for @groups.kv -> $i, $group {
        my Int $with-group = $used
            + ($i > 0 ?? SEP-TEXT.chars !! 0) + group-cols($group);
        last if $with-group + $tail-cols > $avail;
        $used = $with-group;
        $kept = $i + 1;
    }

    return (Selkie::Widget::RichText::Span.new(
        text => TAIL-TEXT, style => $sep-style,
    ),) unless $kept;

    (
        |group-spans(@groups, $kept, $key-style, $label-style, $sep-style),
        Selkie::Widget::RichText::Span.new(
            text => TAIL-LEAD ~ TAIL-TEXT, style => $sep-style,
        ),
    );
}
