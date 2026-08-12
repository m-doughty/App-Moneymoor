unit module App::Moneymoor::Theme::Solarized;

use App::Moneymoor::Theme;

# Solarized Dark — Ethan Schoonover's precise, muted palette tuned
# for contrast on both light and dark terminals.
# https://ethanschoonover.com/solarized/
our sub theme(--> App::Moneymoor::Theme) is export {
    App::Moneymoor::Theme.new(
        name              => 'solarized',
        bg-base           => 0x002B36,     # base03
        bg-highlight      => 0x073642,     # base02
        bg-surface        => 0x073642,     # base02 — Solarized's only raised background
        bg-banner         => 0x073642,
        fg-banner         => 0x93A1A1,     # base1
        fg-base           => 0x839496,     # base0
        fg-dim            => 0x586E75,     # base01
        fg-dimmer         => 0x495E65,
        fg-bright         => 0x93A1A1,     # base1
        fg-red            => 0xDC322F,
        fg-amber          => 0xB58900,     # yellow
        fg-green          => 0x859900,
        fg-blue           => 0x268BD2,
        fg-purple         => 0x6C71C4,     # violet
        fg-cyan           => 0x2AA198,
        accent            => 0x268BD2,     # blue
        fg-border         => 0x586E75,
        fg-border-focused => 0x268BD2,
    );
}
