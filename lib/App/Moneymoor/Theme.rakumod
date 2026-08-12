=begin pod

=head1 NAME

App::Moneymoor::Theme - the app's semantic colour palette: nineteen
required slots, the colours derived from them, and the translation into
a C<Selkie::Theme>.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Theme;
use App::Moneymoor::Themes;

my $theme = App::Moneymoor::Themes::load('tokyo-night');

# Semantic slots, named for what they mean rather than what they are:
$theme.fg-red;                  # an overspent envelope
$theme.fg-green;                # money still available
$theme.accent;                  # the palette's signature hue

# Derived, so a palette never has to keep two values in sync:
$theme.blend(0x000000, 0xFFFFFF, 0.5);   # 0x808080
my ($left, $right) = $theme.banner-gradient;

# And the whole thing as Selkie's own vocabulary, for the framework's
# widgets:
my $app = Selkie::App.new(theme => $theme.to-selkie);

=end code

=head1 DESCRIPTION

Two colour vocabularies meet here. C<Selkie::Theme> is keyed to widget
I<roles> — border, input, scrollbar, dropdown — because that is what a
framework can know about. This class is keyed to what a colour I<means>
in a budget: green is money you still have, red is money you spent that
you did not have, amber is the overspend a credit card will write off
at the period boundary (see C<docs/ui-v0.1-spec.md> §2). C<to-selkie> is
the one-way translation between them.

Every slot is C<is required>. A palette either supplies all nineteen or
fails at construction, which is the only point where a missing colour
is cheap to notice — the alternative is a theme that looks right until
the user opens the one dialog whose slot was never filled.

=head2 Derived rather than declared

Anything computable from the nineteen lives here as a method:
C<blend>, C<banner-gradient>, C<flash-colour>, and the handful of
blends C<to-selkie> makes inline. Every extra required slot would be
eleven more hand-picked hex values to keep in step across the eleven
palettes, and eleven more chances to ship one that disagrees with
itself.

=head2 Filling every Selkie slot

C<to-selkie> passes a value for B<every> C<Selkie::Theme> slot,
including the ones Selkie would default. Selkie's defaults derive from
its own palette constants, not from the slots handed in, so a defaulted
slot is how a Gruvbox app ends up with blue-grey dropdowns, toasts and
overlay titles. C<t/50-theme-completeness.rakutest> pins it: for every
slot Selkie would have defaulted, this class's value must differ from
C<Selkie::Theme.default>'s — and the palettes' contrast ratios have to
clear the WCAG floors on top of that.

=head1 SEE ALSO

=item L<App::Moneymoor::Themes> — the registry and the C<load> by name.
=item L<App::Moneymoor::View::ModalChrome> — the style bundle every
      dialog is built from, derived from one of these.

=end pod

unit class App::Moneymoor::Theme;

use Selkie::Alpha;
use Selkie::Theme;
use Selkie::Style;

has Str  $.name              is required;

# Foreground axis. -dim reads as "present but not shouting";
# -dimmer is further-down for completed rows.
has UInt $.fg-base           is required;
has UInt $.fg-dim            is required;
has UInt $.fg-dimmer         is required;
has UInt $.fg-bright         is required;

# Accent hues. Map loosely to common syntax-highlight buckets; the
# exact palette varies by theme but every theme supplies all of them.
has UInt $.fg-red            is required;   # overdue
has UInt $.fg-amber          is required;   # flagged, warnings
has UInt $.fg-green          is required;
has UInt $.fg-blue           is required;   # accent / info
has UInt $.fg-purple         is required;
has UInt $.fg-cyan           is required;

#| The palette's signature hue — the one colour a user would name if
#| asked "what colour is this theme?". Usually the same value the
#| palette already uses for C<fg-border-focused>. Drives focus accents,
#| overlay titles, selection backgrounds, chart lines and the banner
#| gradient, so it should be a saturated, foreground-weight colour.
has UInt $.accent            is required;

# Background axis.
has UInt $.bg-base           is required;
has UInt $.bg-highlight      is required;   # cursor row
#| One step up from C<bg-base>: the raised-panel background used by
#| dropdown surfaces, toasts, focused controls and legend panes. Most
#| schemes ship a canonical value for this (Catppuccin surface0,
#| Gruvbox bg1, Everforest bg1, …); where a scheme has no colour
#| between its base and its cursor-row highlight, this equals
#| C<bg-highlight>. Must never equal C<bg-base> — a surface that
#| doesn't lift off the background isn't a surface.
has UInt $.bg-surface        is required;
has UInt $.bg-banner         is required;   # top bar
has UInt $.fg-banner         is required;

# Border / chrome.
has UInt $.fg-border         is required;
has UInt $.fg-border-focused is required;

# ---------------------------------------------------------------------
# Derived colours.
#
# Anything that can be computed from the slots above lives here as a
# method rather than as another `is required` slot: every extra slot is
# eleven more hand-picked hex values to keep in sync, and eleven more
# chances to ship a palette that disagrees with itself.
# ---------------------------------------------------------------------

#|( Componentwise blend of two C<0xRRGGBB> colours in sRGB space.
    C<$t> is the weight of C<$b>: C<0> returns C<$a> unchanged, C<1>
    returns C<$b>, C<0.5> is the midpoint. Weights outside C<0..1>
    clamp rather than extrapolating.

    This is a plain function in method clothing — it touches no
    attributes, so it can be called on the type object:

        App::Moneymoor::Theme.blend(0x000000, 0xFFFFFF, 0.5);  # 0x808080
        $theme.blend($theme.accent, $theme.bg-base, 0.6);     # muted accent

    Blending in sRGB (rather than linear light) is deliberate: the
    result has to look like a halfway step to the eye on a terminal
    that knows nothing about colour management, and terminal palettes
    are authored in sRGB. )
method blend(UInt $a, UInt $b, Rat(Real) $t --> UInt) {
    my $w = max(0, min(1, $t));
    my UInt $out = 0;
    for 16, 8, 0 -> $shift {
        my $ca = ($a +> $shift) +& 0xFF;
        my $cb = ($b +> $shift) +& 0xFF;
        my $c  = ($ca + ($cb - $ca) * $w).round;
        $c = max(0, min(255, $c));
        $out = $out +| ($c +< $shift);
    }
    $out;
}

#|( The two colour stops for the top banner, left to right: the flat
    banner background, then that background pulled 35% of the way
    toward the palette's accent. Subtle by design — the banner is
    chrome, not a focal point, and a full-strength accent stop turns
    it into one.

        my ($left, $right) = $theme.banner-gradient;

    Returned as a two-element List so callers can destructure it
    positionally; a future multi-stop gradient would grow this list
    rather than change its shape. )
method banner-gradient(--> List) {
    ($!bg-banner, self.blend($!bg-banner, $!accent, 0.35)).List;
}

#|( Colour a row flashes to when something good happens to it —
    an envelope funded, an edit saved. Green everywhere, because the
    flash is a success signal and every palette's green reads that way;
    it is a method rather than an alias so a palette that needs a
    different confirmation hue can be given one without touching call
    sites. )
method flash-colour(--> UInt) { $!fg-green }

#| Build a Selkie::Theme from this palette so generic Selkie widgets
#| (Border, TextInput, scrollbars, etc.) pick up the same colour
#| scheme without us rewriting them. Install via Selkie::App.new(:theme).
#|
#| Every Selkie slot is filled explicitly, including the ones Selkie
#| gives a default. Leaving them defaulted is how you end up with a
#| Gruvbox app whose Select dropdowns, toasts and overlay titles are
#| still wearing Selkie's built-in blue-grey — the defaults derive from
#| Selkie's *own* palette constants, not from the slots we pass in.
#| t/50-theme-completeness pins this: for every previously-defaulted
#| slot, our value must differ from C<Selkie::Theme.default>'s.
method to-selkie(--> Selkie::Theme) {
    Selkie::Theme.new(
        base              => Selkie::Style.new(fg => $.fg-base,   bg => $.bg-base),
        text              => Selkie::Style.new(fg => $.fg-base),
        text-dim          => Selkie::Style.new(fg => $.fg-dim),
        text-highlight    => Selkie::Style.new(fg => $.fg-bright, bg => $.bg-highlight, bold => True),
        border            => Selkie::Style.new(fg => $.fg-border),
        border-focused    => Selkie::Style.new(fg => $.fg-border-focused, bold => True),
        input             => Selkie::Style.new(fg => $.fg-base,   bg => $.bg-highlight),
        input-focused     => Selkie::Style.new(fg => $.fg-bright, bg => $.bg-highlight),
        input-placeholder => Selkie::Style.new(fg => $.fg-dim, italic => True),
        scrollbar-track   => Selkie::Style.new(fg => $.fg-dim),
        scrollbar-thumb   => Selkie::Style.new(fg => $.fg-border-focused),
        divider           => Selkie::Style.new(fg => $.fg-border),
        # TabBar's three slots. The tab strip runs in `TabPill` +
        # `FocusColor` mode (see Screen::Main), which makes all three
        # backgrounds load-bearing:
        #
        #   tab-active   the pill's fill. A pill IS its background, so
        #                this slot needs one — bg-surface, the same
        #                raised-panel step dropdowns and toasts sit on,
        #                so an unfocused-but-current tab reads as a
        #                chip lifted off the page rather than as a
        #                block of colour competing with the banner.
        #   tab-inactive bg-base, stated rather than inherited:
        #                `apply-style` only touches a channel the Style
        #                defines, so an inactive tab drawn right after
        #                the pill would otherwise keep the pill's fill.
        #   tab-focus-accent  merged onto the active tab while the bar
        #                holds the keyboard, and merge means its bg
        #                REPLACES the pill's — so it carries a full
        #                fg/bg pair and the focused pill comes out
        #                solid accent. Same pairing as `selection`:
        #                one "this is the thing you're driving" colour
        #                across the app.
        tab-active        => Selkie::Style.new(fg => $.fg-banner, bg => $.bg-surface, bold => True),
        tab-inactive      => Selkie::Style.new(fg => $.fg-dim,    bg => $.bg-base),
        tab-focus-accent  => Selkie::Style.new(fg => $.bg-base,   bg => $.accent, bold => True),

        # Controls. Focused controls and dropdown surfaces sit on
        # bg-surface so they read as lifted off the page; the dropdown
        # cursor row keeps bg-highlight so it matches every other
        # cursor row in the app.
        control-focused    => Selkie::Style.new(fg => $.fg-bright, bg => $.bg-surface, bold => True),
        selection          => Selkie::Style.new(fg => $.bg-base,   bg => $.accent),
        input-ghost        => Selkie::Style.new(fg => $.fg-dimmer, italic => True),
        dropdown           => Selkie::Style.new(fg => $.fg-base,   bg => $.bg-surface),
        dropdown-highlight => Selkie::Style.new(fg => $.fg-bright, bg => $.bg-highlight, bold => True),

        # Overlays. The backdrop is the palette's own background pulled
        # halfway to black — a flat black dim washes every theme out to
        # the same grey, and the whole point of eleven palettes is that
        # they don't converge when a modal opens.
        overlay-title     => Selkie::Style.new(fg => $.accent,    bg => $.bg-base, bold => True),
        overlay-key       => Selkie::Style.new(fg => $.fg-purple, bg => $.bg-base, bold => True),
        modal-backdrop    => Selkie::Style.new(
            fg => $.fg-dimmer,
            bg => self.blend($.bg-base, 0x000000, 0.5),
        ),

        # Framed-modal chrome (Selkie's S4 slots). A modal is a focus
        # trap — something inside it is focused essentially always — so
        # its frame takes the palette's accent rather than the resting
        # `fg-border`: it reads as the one lit-up panel on screen
        # without the frame having to react to focus at all (Selkie
        # points both the resting and focused frame slots here).
        # Title and key strip mirror overlay-title / overlay-key, which
        # is what they default to in Selkie and what the command
        # palette and help overlay already wear.
        modal-frame       => Selkie::Style.new(fg => $.accent,     bg => $.bg-base),
        modal-title       => Selkie::Style.new(fg => $.accent,     bg => $.bg-base, bold => True),
        modal-key         => Selkie::Style.new(fg => $.fg-purple,  bg => $.bg-base, bold => True),

        # The scrim is a single AlphaBlend layer, not an opacity
        # slider: notcurses alpha is a two-bit enum, so every cell the
        # scrim covers comes out as the exact 50/50 mean of this style
        # and whatever is underneath. A deeper dim therefore means a
        # *darker colour here*, never "more alpha" — see Selkie::Alpha.
        #
        # bg is the palette's own background pulled halfway to black,
        # the same value `modal-backdrop` paints opaquely, so the two
        # backdrop modes tint in the same direction; over an unmodified
        # screen it resolves to three-quarters of bg-base. fg blends the
        # text showing through toward fg-dimmer, which is what stops the
        # scrimmed screen competing with the dialog on top of it.
        modal-scrim       => Selkie::Style.new(
            fg       => $.fg-dimmer,
            bg       => self.blend($.bg-base, 0x000000, 0.5),
            fg-alpha => AlphaBlend,
            bg-alpha => AlphaBlend,
        ),

        toast             => Selkie::Style.new(fg => $.fg-banner, bg => $.bg-surface, bold => True),

        # Password-strength meter, weakest to strongest. Five bands over
        # a three-hue ramp (red → amber → green → cyan), with bold
        # separating the two amber bands and topping out the scale, so
        # neighbouring bands stay distinguishable in palettes whose
        # amber and green are close together.
        password-empty       => Selkie::Style.new(fg => $.fg-dimmer),
        password-weak        => Selkie::Style.new(fg => $.fg-red),
        password-fair        => Selkie::Style.new(fg => $.fg-amber),
        password-good        => Selkie::Style.new(fg => $.fg-amber, bold => True),
        password-strong      => Selkie::Style.new(fg => $.fg-green),
        password-very-strong => Selkie::Style.new(fg => $.fg-cyan,  bold => True),

        # Charts. Axes and labels fade to fg-dim, gridlines to the
        # border colour, and the single-series line takes the accent.
        # The bg is set explicitly on all of them: chart widgets paint
        # over the app background, and an unset bg inherits whatever
        # plane happens to be underneath.
        graph-axis        => Selkie::Style.new(fg => $.fg-dim,    bg => $.bg-base),
        graph-axis-label  => Selkie::Style.new(fg => $.fg-dim,    bg => $.bg-base),
        graph-grid        => Selkie::Style.new(fg => $.fg-border, bg => $.bg-base),
        graph-line        => Selkie::Style.new(fg => $.accent,    bg => $.bg-base),
        graph-fill        => Selkie::Style.new(
            fg => self.blend($.accent, $.bg-base, 0.6),
            bg => $.bg-base,
        ),
        graph-legend-bg   => Selkie::Style.new(bg => $.bg-surface),
    );
}

# Registry / loader lives in App::Moneymoor::Themes (plural) to avoid a
# circular `use` with the palette modules, which themselves
# construct App::Moneymoor::Theme instances.
