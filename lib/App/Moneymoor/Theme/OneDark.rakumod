unit module App::Moneymoor::Theme::OneDark;

use App::Moneymoor::Theme;

# One Dark — Atom's default, widely ported. Muted saturation on a
# neutral grey-blue base.
# https://github.com/atom/one-dark-ui
our sub theme(--> App::Moneymoor::Theme) is export {
    App::Moneymoor::Theme.new(
        name              => 'one-dark',
        bg-base           => 0x282C34,
        bg-highlight      => 0x3E4451,
        bg-surface        => 0x31353F,     # bg1
        bg-banner         => 0x21252B,
        fg-banner         => 0x61AFEF,
        fg-base           => 0xABB2BF,
        fg-dim            => 0x5C6370,     # comment
        fg-dimmer         => 0x4B5263,
        fg-bright         => 0xFFFFFF,
        fg-red            => 0xE06C75,
        fg-amber          => 0xE5C07B,     # light yellow
        fg-green          => 0x98C379,
        fg-blue           => 0x61AFEF,
        fg-purple         => 0xC678DD,
        fg-cyan           => 0x56B6C2,
        accent            => 0x61AFEF,     # blue
        fg-border         => 0x3E4451,
        fg-border-focused => 0x61AFEF,
    );
}
