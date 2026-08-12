unit module App::Moneymoor::Theme::Nord;

use App::Moneymoor::Theme;

# Nord — Arctic, north-bluish clean design. Low-saturation throughout.
# https://www.nordtheme.com/
our sub theme(--> App::Moneymoor::Theme) is export {
    App::Moneymoor::Theme.new(
        name              => 'nord',
        bg-base           => 0x2E3440,     # polar night 0
        bg-highlight      => 0x3B4252,     # polar night 1
        bg-surface        => 0x3B4252,     # polar night 1 (raised panel = cursor row)
        bg-banner         => 0x242933,
        fg-banner         => 0x88C0D0,     # frost
        fg-base           => 0xD8DEE9,     # snow 0
        fg-dim            => 0x4C566A,     # polar night 3
        fg-dimmer         => 0x434C5E,
        fg-bright         => 0xECEFF4,     # snow 2
        fg-red            => 0xBF616A,     # aurora red
        fg-amber          => 0xEBCB8B,     # aurora yellow
        fg-green          => 0xA3BE8C,
        fg-blue           => 0x81A1C1,     # frost
        fg-purple         => 0xB48EAD,
        fg-cyan           => 0x88C0D0,
        accent            => 0x88C0D0,     # frost
        fg-border         => 0x434C5E,
        fg-border-focused => 0x88C0D0,
    );
}
