unit module App::Moneymoor::Theme::Dracula;

use App::Moneymoor::Theme;

# Dracula — Zeno Rocha's dark theme with saturated pink / purple
# accents. https://draculatheme.com/contribute
our sub theme(--> App::Moneymoor::Theme) is export {
    App::Moneymoor::Theme.new(
        name              => 'dracula',
        bg-base           => 0x282A36,     # background
        bg-highlight      => 0x44475A,     # current-line
        bg-surface        => 0x343746,     # bg-light (one step up from background)
        bg-banner         => 0x21222C,
        fg-banner         => 0xFF79C6,     # pink
        fg-base           => 0xF8F8F2,     # foreground
        fg-dim            => 0x6272A4,     # comment
        fg-dimmer         => 0x4B527D,
        fg-bright         => 0xFFFFFF,
        fg-red            => 0xFF5555,
        fg-amber          => 0xF1FA8C,     # yellow
        fg-green          => 0x50FA7B,
        fg-blue           => 0x8BE9FD,     # cyan — Dracula's "blue" is really cyan
        fg-purple         => 0xBD93F9,
        fg-cyan           => 0x8BE9FD,
        accent            => 0xBD93F9,     # purple
        fg-border         => 0x44475A,
        fg-border-focused => 0xBD93F9,     # purple
    );
}
