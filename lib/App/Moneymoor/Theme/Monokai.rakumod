unit module App::Moneymoor::Theme::Monokai;

use App::Moneymoor::Theme;

# Monokai — Wimer Hazenberg's classic high-contrast scheme. The
# pinks and greens are the giveaway.
# https://monokai.pro/
our sub theme(--> App::Moneymoor::Theme) is export {
    App::Moneymoor::Theme.new(
        name              => 'monokai',
        bg-base           => 0x272822,
        bg-highlight      => 0x3E3D32,
        bg-surface        => 0x3B3A32,     # invisibles grey, a hair under the line highlight
        bg-banner         => 0x1E1F1C,
        fg-banner         => 0xE6DB74,     # yellow
        fg-base           => 0xF8F8F2,
        fg-dim            => 0x75715E,     # comment
        fg-dimmer         => 0x59584D,
        fg-bright         => 0xFFFFFF,
        fg-red            => 0xF92672,     # pink-red
        fg-amber          => 0xFD971F,     # orange
        fg-green          => 0xA6E22E,
        fg-blue           => 0x66D9EF,     # cyan
        fg-purple         => 0xAE81FF,
        fg-cyan           => 0x66D9EF,
        accent            => 0xA6E22E,     # green
        fg-border         => 0x49483E,
        fg-border-focused => 0xA6E22E,
    );
}
