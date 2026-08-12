unit module App::Moneymoor::Theme::Catppuccin;

use App::Moneymoor::Theme;

# Catppuccin Mocha — soft pastels on a cool dark base.
# https://github.com/catppuccin/catppuccin
our sub theme(--> App::Moneymoor::Theme) is export {
    App::Moneymoor::Theme.new(
        name              => 'catppuccin',
        bg-base           => 0x1E1E2E,     # base
        bg-highlight      => 0x313244,     # surface0
        bg-surface        => 0x313244,     # surface0 (Mocha's raised panel = its cursor row)
        bg-banner         => 0x181825,     # mantle
        fg-banner         => 0xB4BEFE,     # lavender
        fg-base           => 0xCDD6F4,     # text
        fg-dim            => 0x9399B2,     # subtext0
        fg-dimmer         => 0x6C7086,     # overlay0
        fg-bright         => 0xCDD6F4,
        fg-red            => 0xF38BA8,
        fg-amber          => 0xF9E2AF,     # yellow
        fg-green          => 0xA6E3A1,
        fg-blue           => 0x89B4FA,
        fg-purple         => 0xCBA6F7,     # mauve
        fg-cyan           => 0x94E2D5,     # teal
        accent            => 0xCBA6F7,     # mauve — the palette's signature
        fg-border         => 0x45475A,     # surface1
        fg-border-focused => 0xCBA6F7,
    );
}
