=begin pod

=head1 NAME

App::Moneymoor::Widget::BannerBar - the one-row top banner: a horizontal
colour ramp, the perspective breadcrumb, and a right-aligned clock.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Widget::BannerBar;
use Selkie::Sizing;

my $banner = App::Moneymoor::Widget::BannerBar.new(
    palette => $theme,
    text    => ' App::Moneymoor',
    sizing  => Sizing.fixed(1),
);
$root.add($banner);

# The perspective subscription keeps the left text current...
$banner.set-text(' App::Moneymoor — Inbox ▸ Roof repair');

# ...and one frame callback keeps the clock current, without the
# store ever hearing about it.
install-banner-clock($app, $banner);

# A live palette swap re-reads the stops and repaints.
$banner.set-theme-colours($new-theme);

=end code

=head1 DESCRIPTION

The banner is the only chrome in Moneymoor that carries a gradient. It
paints C<App::Moneymoor::Theme.banner-gradient> — the flat banner
background on the left, that background pulled a third of the way
toward the palette's accent on the right — across its whole width, then
writes two pieces of text over it:

=item The B<left text>, whatever C<set-text> was last handed, in
      C<fg-banner> bold. Truncated with an ellipsis when it doesn't
      fit.
=item The B<clock>, C<HH:MM>, flush against the right edge, in
      C<fg-banner> blended 70% of the way toward the ramp's right stop
      so it reads as a timestamp rather than as a second headline.

=head2 Text on a gradient

C<Selkie::Gradient>'s banner idiom is "C<gradient-fill> at the top of
your own C<render>, then C<putstr> over it", and that is what happens
here — with one refinement. C<ncplane_putstr> paints the plane's
current background into every cell it writes, so a naive
fill-then-putstr leaves the text sitting in a flat rectangle of
whatever background was set last, with a visible seam where it ends.

So the text is stamped in B<runs>: the background is set to the ramp's
own value at that column and a run of characters sharing that value is
written in one call. C<banner-cell-colour> is the interpolation, and it
is deliberately notcurses's own integer formula
(C<calc_gradient_component>'s single-row case: truncating division, no
rounding), so a stamped cell is bit-identical to the one
C<gradient-fill> painted underneath it — the text really is on the
ramp, not near it. How long the runs get is the palette's business: a
ramp whose components move less than a step per column collapses whole
words into one call, and a steeper one degrades to a call per column.
Either way the cost is bounded by the banner's width and paid only on a
frame where something actually changed — which, once the perspective
settles, is once a minute.

C<banner-cell-colour> is exported so that relationship is testable
without a terminal: assert its endpoints against
C<Theme.banner-gradient>, then assert the rendered cells against it.

=head2 The clock does not go through the store

The clock is wall-clock state that nothing else in the app reads, and
dispatching it would be actively harmful: a store dispatch on a fixed
period is exactly the metronomic same-shape work pattern documented in
C<Screen::Main.!wire-time-signals> as having tripped a MoarVM
specialiser bug. So the clock is a plain frame callback
(C<install-banner-clock>) that owns a cached formatted minute and calls
C<tick-clock>, which marks the widget dirty B<only> when the string it
is handed differs from the one already showing — 59 of every 60 ticks
are a single string comparison and nothing else.

The idle-frame cost is one C<now.Int> and one integer comparison. The
detector is a second boundary rather than a minute boundary on purpose:
C<Instant> counts TAI seconds, so its I<minute> buckets sit a
leap-second offset away from wall-clock minutes and a minute-granular
gate would show the new minute up to half a minute late. Second buckets
are offset by the same constant but recur 60 times as often, so the
displayed minute is never more than a second stale, and the once-a-second
C<DateTime.now> + C<sprintf> is the only allocation on the path.

=head2 Layout

The right five columns (plus one of separation) are reserved for the
clock whether or not one has ticked yet, so the left text does not
jump the first time the clock appears. Below six columns the
reservation is dropped and the text gets the whole row; below five the
clock is not painted at all — a half-written time reads as corruption.

C<visible-text> resolves that budget and is public, plane-free and
width-parameterised: a widget that has not been laid out yet reports
zero columns, so truncating at C<set-text> time would truncate against
the wrong width and never recover on resize.

=head1 SEE ALSO

=item L<Selkie::Gradient> — the ramp primitive and its three idioms
=item L<App::Moneymoor::Theme> — C<banner-gradient> and C<blend>

=end pod

use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::App;
use Selkie::Gradient;
use Selkie::Style;
use Selkie::Widget;

use App::Moneymoor::Theme;

unit class App::Moneymoor::Widget::BannerBar does Selkie::Widget;

#|( The palette the ramp and both text colours are resolved from.

    Named C<palette> rather than C<theme> because C<Selkie::Widget>
    already composes a private C<$!theme> (a C<Selkie::Theme>, the
    cascaded widget theme) and a class cannot redeclare it. Swap it
    with C<set-theme-colours>. )
has App::Moneymoor::Theme $.palette is required;

#| The left text, as last handed to C<set-text> — untruncated. What
#| actually fits is resolved per render by C<visible-text>.
has Str $.text = '';

# Formatted clock, or '' before the first tick. Never wider than
# CLOCK-COLS on the painted path.
has Str $!clock = '';

# Colours derived from $!palette, refreshed by !capture-colours. Held
# unpacked because `render` reads them per run and `banner-gradient`
# rebuilds its right stop (a three-component blend) on every call.
has UInt $!stop-left;
has UInt $!stop-right;
has UInt $!text-fg;
has UInt $!clock-fg;
has Gradient $!gradient;

# Width of the last geometry render() actually served. -1 until the first
# render, so a widget that has never painted is never treated as clean.
has Int $!painted-width = -1;

#| Columns the clock occupies: C<HH:MM>.
my constant CLOCK-COLS = 5;

#| Columns kept blank between the left text and the clock.
my constant CLOCK-GAP = 1;

# The left text's style mask, resolved through Selkie::Style rather
# than by naming an NCSTYLE_* constant, so it tracks whatever Selkie
# means by "bold". Constant for the process; the render path only ever
# reads it.
my $BOLD-MASK = Selkie::Style.new(bold => True).styles;

#|( Componentwise interpolation between two C<0xRRGGBB> stops at column
    C<$col> of a C<$width>-column single-row ramp.

    This is notcurses's own C<calc_gradient_component>, single-row
    case: each component is interpolated with integer arithmetic and
    B<truncating> division, and a ramp one column wide is simply the
    left stop. Reimplementing it (rather than rounding, or lerping in
    floating point) is the whole point — it makes the values this
    module stamps identical to the ones C<ncplane_gradient> wrote
    underneath them. )
sub interpolate-stop(UInt $a, UInt $b, Int $col, Int $width --> UInt) {
    return $a if $width <= 1;
    my Int $x = max(0, min($width - 1, $col));
    my UInt $out = 0;
    for 16, 8, 0 -> $shift {
        my $ca = ($a +> $shift) +& 0xFF;
        my $cb = ($b +> $shift) +& 0xFF;
        my $c  = ($ca * ($width - 1 - $x) + $cb * $x) div ($width - 1);
        $out = $out +| ($c +< $shift);
    }
    $out;
}

#|( The banner's background colour at column C<$col> of a
    C<$width>-column banner painted with C<$theme>'s stops.

    C<$col> C<0> is the left stop exactly and C<$col> C<$width - 1> the
    right stop exactly; in between the value moves monotonically from
    one to the other. Columns outside the row clamp to its ends, and a
    one-column banner is the left stop (which is what notcurses does
    with a degenerate region — see C<Gradient.for-region>).

    Pure, so the banner's colour ramp can be asserted without a
    terminal:

        banner-cell-colour(0, 80, :$theme);    # $theme.banner-gradient[0]
        banner-cell-colour(79, 80, :$theme);   # $theme.banner-gradient[1] )
sub banner-cell-colour(Int $col, Int $width,
                       App::Moneymoor::Theme :$theme! --> UInt) is export {
    my ($a, $b) = $theme.banner-gradient;
    interpolate-stop($a, $b, $col, $width);
}

#|( The clock string for a moment: zero-padded local C<HH:MM>.

    Exported and defaulted rather than inlined so the format is pinned
    by a test that doesn't have to wait for a particular minute:

        banner-clock-text(DateTime.new(2026, 8, 2, 9, 5, 0));   # '09:05' )
sub banner-clock-text(DateTime $at = DateTime.now --> Str) is export {
    sprintf('%02d:%02d', $at.hour, $at.minute);
}

#|( The frame callback that keeps C<$bar>'s clock current: a closure
    over the last second it looked at, so an idle frame costs one
    C<now.Int> and one integer comparison, and only a second boundary
    reaches for the wall clock at all.

    Nothing on this path touches the store — see the Pod's "The clock
    does not go through the store" — and nothing it does is
    conditional on a render: C<tick-clock> decides whether the banner
    is worth repainting.

    C<:clock> is the moment source, and exists so the gate can be
    driven in a test without waiting on a particular minute:

        my &tick = banner-clock-ticker($bar, clock => { '09:05' });
        tick();                # the banner now reads 09:05

    Returned rather than registered so C<install-banner-clock> can use
    its first call as the seed: one code path paints the clock, not
    two. )
sub banner-clock-ticker(App::Moneymoor::Widget::BannerBar:D $bar,
                        :&clock = &banner-clock-text --> Callable) is export {
    my Int $last-second = -1;
    -> {
        my Int $second = now.Int;
        if $second != $last-second {
            $last-second = $second;
            $bar.tick-clock(clock());
        }
    }
}

#|( Wire C<$bar>'s clock to C<$app>'s frame loop, painting the current
    time immediately so the banner is never briefly clockless.

    Call it once per banner. Both screens own one and each wires its
    own; the callback for an off-screen banner keeps running, which is
    what makes the clock already right the moment the user switches to
    it. )
sub install-banner-clock(Selkie::App:D $app,
                         App::Moneymoor::Widget::BannerBar:D $bar --> Nil) is export {
    my &tick = banner-clock-ticker($bar);
    tick();
    $app.on-frame: &tick;
    Nil
}

submethod TWEAK() {
    self!capture-colours;
}

#|( Re-read the ramp stops and text colours from C<$theme> and repaint.

    The live-theme-swap entry point: C<Screen::Main.!rebuild-captured-
    styles> and C<Screen::ReviewMode.apply-theme-live> call this for the
    same reason they rebuild every other captured C<Selkie::Style> —
    Selkie's C<set-theme> cascade reaches C<self.theme>, and none of
    these colours come from there. )
method set-theme-colours(App::Moneymoor::Theme:D $theme) {
    $!palette = $theme;
    self!capture-colours;
    self.mark-dirty;
}

method !capture-colours(--> Nil) {
    ($!stop-left, $!stop-right) = $!palette.banner-gradient;
    $!text-fg  = $!palette.fg-banner;
    # 70% of the way to the ramp's right stop: present, legible against
    # the ramp, and quiet enough that the eye reads the breadcrumb
    # first.
    $!clock-fg = $!palette.blend($!palette.fg-banner, $!stop-right, 0.7);
    $!gradient = Gradient.horizontal($!stop-left, $!stop-right);
    Nil
}

#|( Replace the left text. The C<main-top-bar> / C<review-top-bar>
    store subscriptions call this with the perspective breadcrumb, and
    only when the string they compute actually changes — but a
    no-op repaint is skipped here too, so a caller that pushes
    unconditionally costs a string comparison rather than a frame. )
method set-text(Str:D $t) {
    return if $t eq $!text;
    $!text = $t;
    self.mark-dirty;
}

#|( Show C<$hhmm> as the clock, marking the banner dirty B<only> if
    that isn't already what it shows.

    The whole clock design rests on this: the frame callback can call
    it as often as it likes, and an unchanged minute costs one string
    comparison and does not schedule a render. )
method tick-clock(Str:D $hhmm) {
    return if $hhmm eq $!clock;
    $!clock = $hhmm;
    self.mark-dirty;
}

#| The clock string currently painted, or C<''> before the first tick.
method clock(--> Str) { $!clock }

#|( Columns the left text may occupy in a C<$width>-column banner: the
    row less the clock and its separating gap, and the whole row when
    the banner is too narrow to carry a clock at all (below that point
    the reservation would eat columns for something that is never
    painted). )
method text-budget(Int $width --> Int) {
    return 0 if $width <= 0;
    return $width if $width < CLOCK-COLS;
    max(0, $width - CLOCK-COLS - CLOCK-GAP);
}

#|( The left text as it would be painted in a C<$width>-column banner:
    truncated to C<text-budget> with a trailing C<…> when it doesn't
    fit.

    Width-parameterised and public because the truncation cannot happen
    in C<set-text>: a widget that has not been laid out yet reports zero
    columns, so text set before the first layout pass would be
    truncated to nothing and stay that way. )
method visible-text(Int $width --> Str) {
    my Int $budget = self.text-budget($width);
    return '' if $budget <= 0;
    return $!text if $!text.chars <= $budget;
    $budget == 1 ?? '…' !! $!text.substr(0, $budget - 1) ~ '…';
}

#|( Record that C<render> met a geometry it cannot paint, and answer whether
    the frame may still be reported as served.

    Only once the same unpaintable geometry has been seen before. The first
    encounter must leave the widget dirty: zero dimensions occur transiently
    during a resize, and Selkie's post-resize C<mark-all-dirty> cascade has
    already run by the time C<render> is called — so clearing the flag here
    marks the banner clean having painted nothing, and nothing marks it dirty
    again. The bar then keeps its pre-resize layout until some unrelated
    change happens to touch it.

    Answering True on the repeat is what stops a genuinely collapsed banner
    staying dirty forever and forcing a composite every frame: it costs one
    extra frame, then settles.

    Split out from C<render> so it can be exercised without a terminal — no
    test in this distribution initialises notcurses. )
method note-unpaintable-geometry(Int $w --> Bool) {
    my Bool $already-served = $!painted-width == $w;
    $!painted-width = $w;
    $already-served;
}

method render() {
    return without self.plane;
    my Int $w = self.cols.Int;
    # Zero dimensions happen transiently mid-resize, before the first
    # layout pass, and for a banner in a collapsed parent.
    #
    # Nothing to paint — but only report the frame served once we have
    # actually served THIS geometry. Clearing unconditionally meant a
    # transient zero during a resize marked the banner clean having painted
    # nothing at all: Selkie's post-resize mark-all-dirty cascade had already
    # run, so nothing marked it dirty a second time and the bar kept the
    # pre-resize layout until some unrelated change touched it.
    #
    # The `$!painted-width == $w` guard is what keeps a genuinely collapsed
    # banner from staying dirty forever and forcing a composite every frame:
    # it stays dirty for exactly one more frame, then settles.
    if $w <= 0 || self.rows == 0 {
        self.clear-dirty if self.note-unpaintable-geometry($w);
        return;
    }

    # Destructive, and deliberately so: it doubles as the erase.
    gradient-fill(self.plane, $!gradient, rows => 1, cols => $w);

    my Str $label = self.visible-text($w);
    self!stamp-over-ramp(0, $label, $!text-fg, $BOLD-MASK)
        if $label.chars > 0;

    # A clock that would have to be cut short isn't painted; the
    # reserved columns simply stay ramp.
    if $!clock.chars > 0 && $w >= CLOCK-COLS {
        my Str $c = $!clock.chars > CLOCK-COLS
            ?? $!clock.substr(0, CLOCK-COLS)
            !! $!clock;
        self!stamp-over-ramp($w - $c.chars, $c, $!clock-fg, 0);
    }

    $!painted-width = $w;
    self.clear-dirty;
}

#|( Write C<$s> at column C<$x0> in C<$fg> / C<$styles>, giving every
    cell the ramp's own background so the glyphs sit B<on> the gradient
    rather than in a flat block over it (see the Pod).

    Emitted as runs of columns sharing an interpolated colour, so a
    gentle ramp costs a couple of native calls per word rather than per
    column. )
method !stamp-over-ramp(Int $x0, Str $s, UInt $fg, UInt $styles --> Nil) {
    my Int $w   = self.cols.Int;
    my Int $len = min($s.chars, $w - $x0);
    return if $len <= 0 || $x0 < 0;

    ncplane_set_styles(self.plane, $styles);
    ncplane_set_fg_rgb(self.plane, $fg);

    my Int  $start = 0;
    my UInt $run   = interpolate-stop($!stop-left, $!stop-right, $x0, $w);
    for 1 ..^ $len -> $i {
        my UInt $bg = interpolate-stop($!stop-left, $!stop-right, $x0 + $i, $w);
        next if $bg == $run;
        self!stamp($x0 + $start, $s.substr($start, $i - $start), $run);
        $start = $i;
        $run   = $bg;
    }
    self!stamp($x0 + $start, $s.substr($start, $len - $start), $run);
    Nil
}

method !stamp(Int $x, Str $s, UInt $bg --> Nil) {
    ncplane_set_bg_rgb(self.plane, $bg);
    ncplane_putstr_yx(self.plane, 0, $x, $s);
    Nil
}
