unit module App::Moneymoor::Theme::Gruvbox;

use App::Moneymoor::Theme;

# Gruvbox Dark — Pavel Pertsev's warm retro palette.
# https://github.com/morhetz/gruvbox
our sub theme(--> App::Moneymoor::Theme) is export {
    App::Moneymoor::Theme.new(
        name              => 'gruvbox',
        bg-base           => 0x282828,     # bg0
        bg-highlight      => 0x3C3836,     # bg1
        bg-surface        => 0x3C3836,     # bg1 (the raised panel = the cursor row)
        bg-banner         => 0x1D2021,     # bg0_h (hard)
        fg-banner         => 0xFABD2F,     # yellow
        fg-base           => 0xEBDBB2,     # fg
        fg-dim            => 0xA89984,     # gray
        fg-dimmer         => 0x7C6F64,     # bg4
        fg-bright         => 0xFBF1C7,     # fg0
        fg-red            => 0xFB4934,
        fg-amber          => 0xFABD2F,
        fg-green          => 0xB8BB26,
        fg-blue           => 0x83A598,
        fg-purple         => 0xD3869B,
        fg-cyan           => 0x8EC07C,
        accent            => 0xFABD2F,     # yellow
        fg-border         => 0x504945,     # bg2
        fg-border-focused => 0xFABD2F,     # yellow
    );
}
