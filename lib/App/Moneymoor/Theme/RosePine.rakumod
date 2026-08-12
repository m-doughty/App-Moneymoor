unit module App::Moneymoor::Theme::RosePine;

use App::Moneymoor::Theme;

# Rose Pine — "all natural pine, faux fur and a bit of soho vibes
# for the classy minimalist".
# https://rosepinetheme.com/
our sub theme(--> App::Moneymoor::Theme) is export {
    App::Moneymoor::Theme.new(
        name              => 'rose-pine',
        bg-base           => 0x191724,     # base
        bg-highlight      => 0x26233A,     # overlay
        bg-surface        => 0x1F1D2E,     # surface
        bg-banner         => 0x1F1D2E,     # surface
        fg-banner         => 0xEBBCBA,     # rose
        fg-base           => 0xE0DEF4,     # text
        fg-dim            => 0x6E6A86,     # muted
        fg-dimmer         => 0x524F67,
        fg-bright         => 0xE0DEF4,
        fg-red            => 0xEB6F92,     # love
        fg-amber          => 0xF6C177,     # gold
        fg-green          => 0x9CCFD8,     # foam (no real green)
        fg-blue           => 0x31748F,     # pine
        fg-purple         => 0xC4A7E7,     # iris
        fg-cyan           => 0x9CCFD8,     # foam
        accent            => 0xC4A7E7,     # iris
        fg-border         => 0x26233A,
        fg-border-focused => 0xC4A7E7,
    );
}
