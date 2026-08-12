unit module App::Moneymoor::Theme::TokyoNight;

use App::Moneymoor::Theme;

# Tokyo Night — Enkia's night-city-inspired palette. Cool blues,
# soft purples, moderate saturation.
# https://github.com/folke/tokyonight.nvim
our sub theme(--> App::Moneymoor::Theme) is export {
    App::Moneymoor::Theme.new(
        name              => 'tokyo-night',
        bg-base           => 0x1A1B26,     # bg
        bg-highlight      => 0x292E42,     # bg_highlight
        bg-surface        => 0x24283B,     # storm bg, one step up from night bg
        bg-banner         => 0x16161E,     # bg_dark
        fg-banner         => 0x7AA2F7,     # blue
        fg-base           => 0xC0CAF5,     # fg
        fg-dim            => 0x565F89,     # comment
        fg-dimmer         => 0x3B4261,
        fg-bright         => 0xC0CAF5,
        fg-red            => 0xF7768E,
        fg-amber          => 0xE0AF68,     # yellow
        fg-green          => 0x9ECE6A,
        fg-blue           => 0x7AA2F7,
        fg-purple         => 0xBB9AF7,
        fg-cyan           => 0x7DCFFF,
        accent            => 0x7AA2F7,     # blue
        fg-border         => 0x3B4261,
        fg-border-focused => 0x7AA2F7,
    );
}
