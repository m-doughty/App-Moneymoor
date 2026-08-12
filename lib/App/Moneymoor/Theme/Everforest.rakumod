unit module App::Moneymoor::Theme::Everforest;

use App::Moneymoor::Theme;

# Everforest (Dark / Medium) — sainnhe's warm, soft, forest-green
# palette. Easier on the eyes than high-contrast dark themes.
# https://github.com/sainnhe/everforest
our sub theme(--> App::Moneymoor::Theme) is export {
    App::Moneymoor::Theme.new(
        name              => 'everforest',
        bg-base           => 0x2D353B,     # bg0
        bg-highlight      => 0x3D484D,     # bg2
        bg-surface        => 0x343F44,     # bg1
        bg-banner         => 0x232A2E,     # bg_dim
        fg-banner         => 0xA7C080,     # green
        fg-base           => 0xD3C6AA,     # fg
        fg-dim            => 0x859289,     # grey1
        fg-dimmer         => 0x7A8478,     # grey0
        fg-bright         => 0xE6E2CC,
        fg-red            => 0xE67E80,
        fg-amber          => 0xDBBC7F,     # yellow
        fg-green          => 0xA7C080,
        fg-blue           => 0x7FBBB3,     # aqua
        fg-purple         => 0xD699B6,
        fg-cyan           => 0x83C092,     # soft green-cyan
        accent            => 0xA7C080,     # green
        fg-border         => 0x4F585E,
        fg-border-focused => 0xA7C080,
    );
}
