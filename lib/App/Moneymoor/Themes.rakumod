=begin pod

=head1 NAME

App::Moneymoor::Themes - the registry: every built-in palette, and the
by-name loader the config file and the Settings dialog go through.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Themes;

App::Moneymoor::Themes::all-names();     # the eleven, alphabetical
my $theme = App::Moneymoor::Themes::load('rose-pine');

# Spelling is forgiving, and an unknown name is not an error:
load('RosePine').name;      # 'rose-pine'
load('rose_pine').name;     # 'rose-pine'
load('chartreuse').name;    # 'gruvbox' — the default

=end code

=head1 DESCRIPTION

Eleven palettes, one loader. Separate from C<App::Moneymoor::Theme>
(the data class) because the palette modules construct C<Theme>
instances, and a registry living in the same file would close the
C<use> cycle.

C<load> never throws and never returns a type object. The name it is
given comes from a hand-editable C<config.json>, and a palette is not
worth refusing to start the app over: an unrecognised name — or one
with the wrong separator, or the wrong case — resolves to Gruvbox.
Aliases exist for the spellings the schemes themselves use
(C<tokyonight>, C<onedark>, C<rosepine>, C<solarized-dark>,
C<catppuccin-mocha>).

=head2 Why C<need>, not C<use>

Every palette module exports its own C<theme> sub, so importing two of
them into one scope is a symbol collision — and this module wants all
eleven. C<need> loads a module without importing anything from it,
which is what lets C<load> call each one by its fully-qualified name.

=head1 EXPORTS

=item C<all-names(--> List)> — the eleven canonical names, sorted, in
      the order the Settings picker shows them.
=item C<load(Str:D $name --> App::Moneymoor::Theme)> — a palette, or
      Gruvbox.

=head1 SEE ALSO

=item L<App::Moneymoor::Theme> — what these return.
=item L<App::Moneymoor::Config> — where the configured name comes from.

=end pod

unit module App::Moneymoor::Themes;

use App::Moneymoor::Theme;

# Every palette module exports its own `theme` sub — they'd all
# collide on import. `need` loads the module without importing any
# symbols; we call each by its fully-qualified name below.
need App::Moneymoor::Theme::Gruvbox;
need App::Moneymoor::Theme::Solarized;
need App::Moneymoor::Theme::Dracula;
need App::Moneymoor::Theme::TokyoNight;
need App::Moneymoor::Theme::Catppuccin;
need App::Moneymoor::Theme::Nord;
need App::Moneymoor::Theme::Monokai;
need App::Moneymoor::Theme::OneDark;
need App::Moneymoor::Theme::RosePine;
need App::Moneymoor::Theme::Kanagawa;
need App::Moneymoor::Theme::Everforest;

#| Alphabetical ordering used by the settings picker so new
#| additions slot in predictably — no "newest at the bottom" ordering.
our sub all-names(--> List) is export {
    <catppuccin dracula everforest gruvbox kanagawa monokai
     nord one-dark rose-pine solarized tokyo-night>
}

our sub load(Str:D $name --> App::Moneymoor::Theme) is export {
    my $canonical = $name.lc.subst(/_/, '-', :g);
    given $canonical {
        when 'gruvbox'                           { App::Moneymoor::Theme::Gruvbox::theme    }
        when 'solarized' | 'solarized-dark'      { App::Moneymoor::Theme::Solarized::theme  }
        when 'dracula'                           { App::Moneymoor::Theme::Dracula::theme    }
        when 'tokyo-night' | 'tokyonight'        { App::Moneymoor::Theme::TokyoNight::theme }
        when 'catppuccin' | 'catppuccin-mocha'   { App::Moneymoor::Theme::Catppuccin::theme }
        when 'nord'                              { App::Moneymoor::Theme::Nord::theme       }
        when 'monokai'                           { App::Moneymoor::Theme::Monokai::theme    }
        when 'one-dark' | 'onedark'              { App::Moneymoor::Theme::OneDark::theme    }
        when 'rose-pine' | 'rosepine'            { App::Moneymoor::Theme::RosePine::theme   }
        when 'kanagawa'                          { App::Moneymoor::Theme::Kanagawa::theme   }
        when 'everforest'                        { App::Moneymoor::Theme::Everforest::theme }
        default                                  { App::Moneymoor::Theme::Gruvbox::theme    }
    }
}
