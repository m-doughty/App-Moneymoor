=begin pod

=head1 NAME

App::Moneymoor::Service::Icons - glyph tiers for the budget/register UI

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Service::Icons;

my $glyphs = icons();            # unicode tier (default)
say $glyphs.cleared-uncleared;   # ○
say $glyphs.cleared-cleared;     # ◐

my $nerd = icons('nerd');
say $nerd.warn;                  # nerd-font alert glyph

my $fallback = icons('made-up'); # unknown tier -> unicode
say $fallback === icons();       # (equivalent values, unicode tier)

=end code

=head1 DESCRIPTION

Every glyph the app paints — the three cleared states, the three
account-kind markers, the transfer arrow, the overspend warning, the
group collapse/expand chevrons, the sidebar gutter bar, the move
arrow, the inflow/outflow arrows, and the budget diamond — lives on
one immutable C<App::Moneymoor::Icons> value. Two tiers ship today:

=item C<unicode> (default) — plain Unicode glyphs that render
      correctly in any UTF-8-capable terminal, no patched font
      required.
=item C<nerd> — Nerd Font codepoints, for terminals with a patched
      font installed. Opt-in via C<Config.icons>.

An unrecognised tier name falls back to C<unicode> — mirrors the
fallback semantics of C<App::Moneymoor::Themes::load> (unknown theme
names silently resolve to the default rather than raising).

B<Invariant>: every accessor on both tiers is exactly one grapheme
(C<.chars == 1>). Row composition in the budget/register tables
assumes single-column glyphs for alignment; a multi-grapheme icon
would shift every column to its right.

=head1 EXPORTS

=item C<icons(Str $tier = 'unicode' --> App::Moneymoor::Icons)> —
      look up a tier by name.

=end pod

unit class App::Moneymoor::Icons;

has Str $.cleared-uncleared  is required;
has Str $.cleared-cleared    is required;
has Str $.cleared-reconciled is required;
has Str $.account-cash       is required;
has Str $.account-credit     is required;
has Str $.account-tracking   is required;
has Str $.transfer           is required;
has Str $.warn               is required;
has Str $.group-collapsed    is required;
has Str $.group-expanded     is required;
has Str $.gutter             is required;
has Str $.move               is required;
has Str $.inflow             is required;
has Str $.outflow            is required;
has Str $.budget             is required;

my App::Moneymoor::Icons $unicode-tier = App::Moneymoor::Icons.new(
    cleared-uncleared  => '○',
    cleared-cleared    => '◐',
    cleared-reconciled => '●',
    account-cash       => '▪',
    account-credit     => '▫',
    account-tracking   => '◦',
    transfer           => '⇄',
    warn               => '‼',
    group-collapsed    => '▸',
    group-expanded     => '▾',
    gutter             => '▍',
    move               => '→',
    inflow             => '↓',
    outflow            => '↑',
    budget             => '◆',
);

# Nerd Font codepoints. Every accessor is a single glyph from the
# Nerd Fonts patched set (falls back to tofu boxes without a patched
# font installed — that's the user's opt-in cost for choosing this
# tier).
my App::Moneymoor::Icons $nerd-tier = App::Moneymoor::Icons.new(
    cleared-uncleared  => "\x[f111]",   # nf-fa-circle_o (circle-outline)
    cleared-cleared    => "\x[f042]",   # nf-fa-adjust (circle-half)
    cleared-reconciled => "\x[f023]",   # nf-fa-lock (reconciled/locked)
    account-cash       => "\x[f19c]",   # nf-fa-bank
    account-credit     => "\x[f09d]",   # nf-fa-credit_card
    account-tracking   => "\x[f201]",   # nf-fa-line_chart
    transfer           => "\x[f0ec]",   # nf-fa-exchange (swap-horizontal)
    warn               => "\x[f071]",   # nf-fa-exclamation_triangle (alert)
    group-collapsed    => "\x[f105]",   # nf-fa-angle_right (chevron-right)
    group-expanded     => "\x[f107]",   # nf-fa-angle_down (chevron-down)
    gutter             => "\x[f04b3]",  # nf-md-drag_vertical (single-width bar)
    move               => "\x[f061]",   # nf-fa-arrow_right
    inflow             => "\x[f063]",   # nf-fa-arrow_down (bold)
    outflow            => "\x[f062]",   # nf-fa-arrow_up (bold)
    budget             => "\x[f0d6]",   # nf-fa-money (wallet/diamond stand-in)
);

our sub icons(Str $tier = 'unicode' --> App::Moneymoor::Icons) is export {
    given $tier.lc {
        when 'nerd'    { $nerd-tier }
        default        { $unicode-tier }
    }
}
