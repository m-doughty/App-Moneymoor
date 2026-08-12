unit module App::Moneymoor::Theme::Kanagawa;

use App::Moneymoor::Theme;

# Kanagawa — rebelot's port of the colours from Hokusai's "The
# Great Wave off Kanagawa". Deep blues + gold.
# https://github.com/rebelot/kanagawa.nvim
our sub theme(--> App::Moneymoor::Theme) is export {
    App::Moneymoor::Theme.new(
        name              => 'kanagawa',
        bg-base           => 0x1F1F28,     # sumiInk
        bg-highlight      => 0x2A2A37,     # sumiInk 4
        bg-surface        => 0x2A2A37,     # sumiInk 4 — nothing sits between it and sumiInk 3
        bg-banner         => 0x16161D,     # sumiInk 0
        fg-banner         => 0xE6C384,     # boatYellow2
        fg-base           => 0xDCD7BA,     # fujiWhite
        fg-dim            => 0x727169,     # fujiGray
        fg-dimmer         => 0x54546D,     # sumiInk 7
        fg-bright         => 0xDCD7BA,
        fg-red            => 0xE82424,     # samuraiRed
        fg-amber          => 0xE6C384,     # boatYellow2
        fg-green          => 0x98BB6C,     # springGreen
        fg-blue           => 0x7E9CD8,     # crystalBlue
        fg-purple         => 0x957FB8,     # oniViolet
        fg-cyan           => 0x7AA89F,     # waveAqua1
        accent            => 0x7E9CD8,     # crystalBlue
        fg-border         => 0x363646,     # sumiInk 6
        fg-border-focused => 0x7E9CD8,
    );
}
