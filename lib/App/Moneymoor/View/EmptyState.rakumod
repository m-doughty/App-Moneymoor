=begin pod

=head1 NAME

App::Moneymoor::View::EmptyState - copy for the "nothing here yet"
state across the budget table, register, reports, and sidebar.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::View::EmptyState;
use App::Moneymoor::Service::Icons;

empty-state-for('budget');
# ('No envelopes yet — n to create one',)

empty-state-for('register');
# ('No transactions — n to add one',)

empty-state-for('sidebar');
# ('No accounts yet', 'n to add your first account')

empty-state-for('made-up-state');
# ('nothing here',)

# Icon injection follows the same accessor everything else in the app
# reads — a nerd-tier glyph shows up here for free where a state names
# one.
empty-state-for('budget', :icons(icons('nerd')));

=end code

=head1 DESCRIPTION

Pure copy lookup for the budget table, register, reports panel and
accounts sidebar's empty states — no store, no theme, no widget.
Callers hand the widget a style (dim, centered) separately; this sub
only owns the words.

=item C<budget> — the envelope table has no categories yet.
=item C<register> — the selected account (or All Accounts) has no
      transactions yet.
=item C<reports> — the viewed period has no spending to chart.
=item C<sidebar> — the accounts list has no accounts yet.

Any state this module doesn't recognise falls back to a generic
C<'nothing here'> — same fallback semantics as
C<App::Moneymoor::Themes::load>.

=head1 EXPORTS

=item C<empty-state-for(Str $state, :$icons = icons() --> List)> —
      at most 2 lines of copy. C<$icons> is any
      C<App::Moneymoor::Service::Icons>-shaped value; no state reads
      from it today, but it is on the signature so a glyph-bearing
      state can be added later without touching call sites.

=end pod

unit module App::Moneymoor::View::EmptyState;

use App::Moneymoor::Service::Icons;

our sub empty-state-for(Str $state, :$icons = icons() --> List) is export {
    given $state {
        when 'budget' {
            ('No envelopes yet — n to create one',);
        }
        when 'register' {
            ('No transactions — n to add one',);
        }
        when 'reports' {
            ('No spending to show yet',);
        }
        when 'sidebar' {
            ('No accounts yet', 'n to add your first account');
        }
        default {
            ('nothing here',);
        }
    }
}
