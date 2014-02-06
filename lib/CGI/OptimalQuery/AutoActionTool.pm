package CGI::OptimalQuery::AutoActionTool;

use strict;
use warnings;
use CGI();
use JSON::XS();
no warnings qw( uninitialized );


=comment

This optional module extends CGI::OptimalQuery functionality to allow developers set auto actions for various tools.

INSTALLATION

1) Create the table to store the autoactions

-- when processing auto actions,
-- in order to account for uncommitted transaction data
-- current_dt = DATE_SUB(now(), INTERVAL 5 MINUTE)
-- additional where clause is added depending on the trigger_mask
-- then action function matching specified action_key is executed
-- finally last_run_dt is set to the used current_dt
CREATE TABLE oq_autoaction (
  id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  uri TEXT NOT NULL,
  oq_title TEXT NOT NULL,
  user_title TEXT NOT NULL,
  params TEXT,
  CONSTRAINT unq_oq_autoaction UNIQUE (uri,oq_title,user_title),

  start_dt DATETIME NOT NULL,
  end_dt   DATETIME,

  -- processing this action will be ignored if last_run_st + interval_min > current_dt
  -- this can prevent an action from accurring too often
  repeat_interval_min INTEGER UNSIGNED NOT NULL DEFAULT 1440,

  -- when creating an action for the first time, developer should set this to now() to prevent
  -- the newlycreated autoaction from running on existing records
  last_run_dt DATETIME NOT NULL,

  -- bit mask options where
  -- == 0 then action is disabled
  -- & 1 execute action anytime data exists
  -- & 2 add filter OR (DTM > last_run_dt AND DTM <= current_dt)
  -- & 4 add filter OR (DTC > last_run_dt AND DTC <= current_dt)
  trigger_mask INTEGER UNSIGNED NOT NULL,

  error_txt TEXT
);

2) Create a script that will invoke CGI::OptimalQuery.

For example:

vi /web/events/bin/run_oq_savedsearch_actions.pl
------------------- cut -------------------------------------
#!/usr/bin/perl

usr strict;
use CGI::OptimalQuery::AutoActionRunner();
use Events::Request();

# invoke the right optimalquery for the uri somehow
# the callback function specified will be invoked for every saved search that has an action
CGI::OptimalQuery::AutoActionTool::execute(sub{
  my ($user_id, $uri, $q) = @_;
  CEMS::Request::execute($user_id, $uri);
});
-------------------------------------------------------------

3) Call the script via crontab

crontab -e
# periodically execute saved search actions
# flood control is implemented on a per action basis
0,15,30,45 * * * /web/events/bin/run_oq_savedsearch_actions.pl





A ready to use tool that enhances CGI::OptimalQuery to allow users to create email merges from recordsets. EmailMergeTool also integrates with the AutomatedActionTool to allow users to run automated email merges based off a user configured recordset.

use CGI::OptimalQuery::AutoActionTool();

my $schema = {
  'select' => { .. },
  'joins'  => { .. },
  'tools' => {
    'autoaction' => {
      title => 'Auto Actions',
      handler => \&CGI::OptimalQuery::AutoActionTool::handler
    }
  }
};

CGI::OptimalQuery->new($schema)->output();

=cut


sub escapeHTML {
  return defined $_[0] ? CGI::escapeHTML($_[0]) : '';
}

sub handler {
  my ($o) = @_;
  my $q = $$o{q};
  my $opts = $$o{schema}{tools}{autoaction}{options};

  # execute preview
  if ($q->param('load_oq_autoaction') =~ /^\d+$/) {
    my $id = int($q->param('load_oq_autoaction'));
    my $h = $$o{dbh}->selectrow_hashref("SELECT * FROM oq_autoaction WHERE id=?", undef, $id);
    $$o{output_handler}->(CGI::header('application/json').JSON::XS::encode_json($h));
    return undef;
  }

  # render view
  my $buf = "
<div class=OQautoactiontool>
<div class=OQautoactionform>";

  # display actions
  my $ar = $$o{dbh}->selectall_arrayref("
    SELECT id, user_title, error_txt, uri
    FROM oq_autoaction
    WHERE upper(uri) = upper(?)
    AND oq_title = ?
    ORDER BY 2", undef, $$o{schema}{URI}, $$o{schema}{title});

  if ($#$ar == -1) {
    $buf .= "<p>no auto actions found</p>";
  } else {
    my @x;
    foreach my $row (@$ar) {
      my ($id, $user_title, $error_txt, $uri) = @$row;
      my $x = "<a href=$uri?OQLoadAutoAction=$id>".escapeHTML($user_title)."</a>";
      $x .= '<div>error: '.escapeHTML($error_txt).'</div>' if $error_txt;
      push @x, $x;
    }
    $buf .= join('<hr>', @x);
  }

  $buf .= "
</div>
</div>";
  return $buf;
}

1;
