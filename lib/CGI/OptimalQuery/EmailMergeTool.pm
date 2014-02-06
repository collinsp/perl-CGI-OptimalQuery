package CGI::OptimalQuery::EmailMergeTool;

use strict;
use warnings;
use CGI();
use Mail::Sendmail();
use JSON::XS;
no warnings qw( uninitialized );


=comment

A ready to use tool that enhances CGI::OptimalQuery to allow users to create email merges from recordsets. EmailMergeTool also integrates with the AutomatedActionTool to allow users to run automated email merges based off a user configured recordset.

use CGI::OptimalQuery::EmailMergeTool();

my $schema = {
  'select' => { .. },
  'joins'  => { .. },
  'tools' => {
    'emailmerge' => {
      title => 'Email Merge',

      # default shown, only need to include the ones you want to override
      options => {
        # set this to 1 to make the to field readonly
        readonly_to => 0, 

        # default email to 
        # this must be defined if readonly_to is true
        # note: template vars are allowed. If template variable is used, it
        # must be a valid email address.
        # example:  to => '<SESSION_USER_EMAIL>'
        to => '',

        # specify the default subject
        # note: template vars are allowed
        subject => '',

        # specify the email from address. the user cannot override this
        # note: template vars are NOT allowed
        # this must be defined!
        from => undef,

        # set this to 1 to make the from field readonly
        readonly_from => 0,

        # specify the default greeting
        # note: template vars are allowed
        greeting => '',

        # specify the default body
        # note: template vars are allowed
        body => '',

        # specify the default footer
        # note: template vars are allowed here
        footer => '',

        # specify additional template vars you would like made available in
        # the mailmerge
        template_vars => {
          # example:   'SESSION_USER_EMAIL' => get_current_session_user_email()
        },

        # do not send more then 50 emails at any one time
        max_emails => 50,

        # default implementation using Mail::Sendmail is provided
        sendallemails => sub { my ($emailAr) = @_; ... } 
      },

      handler => \&CGI::OptimalQuery::EmailMergeTool::handler
    }
  }
};

CGI::OptimalQuery->new($schema)->output();

=cut


sub escapeHTML {
  return defined $_[0] ? CGI::escapeHTML($_[0]) : '';
}

# simple function to fill data into a template string in the following format
#  filltemplate("hi <NAME>", { NAME => "bob" })
sub filltemplate {
  my ($template, $dat) = @_;
  my $rv = '';
  foreach my $part (split /(\<\w+\>)/, $template) {
    if ($part =~ /^\<(\w+)\>$/) {
      my $k = uc($1);
      $rv .= $$dat{$k};
    } else {
      $rv .= $part;
    }
  }
  return $rv;
}

# create the email merges from the data and return an array ref of emails
sub create_emails {
  my ($o, $opts) = @_;
  my $q = $$o{q};

  my %emails;

  # copy template vars
  my %dat = %{ $$opts{template_vars} };

  my $from = $q->param('emailmergefrom');

  # for each row in query, merge record into templates
  while (my $rec = $o->sth->fetchrow_hashref()) {
    @dat{keys %$rec} = values %$rec;

    my $to = filltemplate(scalar($q->param('emailmergeto')) ||'', \%dat);
    my $subject = filltemplate(scalar($q->param('emailmergesubject')), \%dat);
    my $greeting = filltemplate(scalar($q->param('emailmergegreeting')), \%dat);
    my $body = filltemplate(scalar($q->param('emailmergebody')), \%dat);
    my $footer = filltemplate(scalar($q->param('emailmergefooter')), \%dat);
    my @to = map { s/\s//g; lc($_) } split /\,/, $to;
    foreach my $emailAddress (@to) {
      $body = "\n".$body if
        $emails{$to}{$subject}{$greeting}{$footer} ne '' &&
        $emails{$to}{$subject}{$greeting}{$footer} !~ /\n\s*$/s;
      $emails{$to}{$subject}{$greeting}{$footer} .= $body;
    }
  }

  my @rv;
  while (my ($to,$x) = each %emails) {
    while (my ($subject,$x) = each %$x) {
      while (my ($greeting,$x) = each %$x) {
        $greeting .= "\n" if $greeting;
        while (my ($footer,$body) = each %$x) {
          $body .= "\n" if $footer;
          push @rv, {
            to => $to,
            from => $from,
            subject => $subject,
            body => $greeting.$body.$footer
          };
        }
      }
    }
  }

  return \@rv;
}

sub sendallemails {
  my ($emails) = @_; 
  foreach my $email (@$emails) {
    $$email{rv} = Mail::Sendmail::sendmail(%$email);
    if (! $$email{rv}) {
      $$email{'error'} = $Mail::Sendmail::log; 
    }
  }
  return undef;
}

sub handler {
  my ($o) = @_;
  my $q = $$o{q};
  my $opts = $$o{schema}{tools}{emailmerge}{options};


  # set default options
  $$opts{to} ||= '';
  $q->param('emailmergeto', $$opts{to}) if $$opts{readonly_to};

  $$opts{from} ||= '';
  $q->param('emailmergefrom', $$opts{from}) if $$opts{readonly_from};

  $$opts{subject} ||= '';
  $$opts{greeting} ||= '';
  $$opts{body} ||= '';
  $$opts{footer} ||= '';
  $$opts{max_emails} = 50 unless $$opts{max_emails} =~ /^\d+$/;
  $$opts{template_vars} ||= {};
  $$opts{sendallemails} ||= \&sendallemails;

  # process action
  my $act = $$o{q}->param('act');

  # execute preview
  if ($act eq 'preview') {
    # check required fields
    return "enter to email address" if $$o{q}->param('emailmergeto') eq '';
    return "enter an email subject" if $$o{q}->param('emailmergesubject') eq '';
    return "enter email from address" if $$o{q}->param('emailmergefrom') eq '';
    return "enter an email body" if $$o{q}->param('emailmergebody') eq '';

    my $emailAr = create_emails($o, $opts);
    my $totalEmails = $#$emailAr + 1;
    return "Total emails ($totalEmails) exceeds maximum limit of ($$opts{max_emails}). Please reduce the amount of emails sent." if ($#$emailAr + 1) > $$opts{max_emails};

    my $buf = "<p><strong>Total email ($totalEmails)</strong></p>";
    foreach my $email (@$emailAr) {
      $buf .= "<div><strong>To: </strong>".escapeHTML($$email{to})."<br><strong>Subject: </strong>".escapeHTML($$email{subject})."<p class=oqemailmergepreviewbody>".escapeHTML($$email{body})."</p></div><hr>";
    }

    return "
<div class=OQemailmergeview>
<div class=OQemailmergemsgs>
$buf
</div>
<p>
<button type=button class=OQEmailMergePreviewBackBut>back</button>
<button type=button class=OQEmailMergeSendEmailBut>send email</button></div>
</p>
</div>";
  }

  # delete the auto action
  elsif ($act eq 'deleteautoaction') {
    my $id = int($$o{q}->param('id'));
    if ($id) {
      $$o{dbh}->do("DELETE FROM oq_autoaction WHERE id=?", undef, $id);
      return "autoaction deleted";
    } else {
      return "missing id param";
    }
  }

  # save the auto action
  elsif ($act eq 'saveautoaction') {

    # check required fields
    return "enter to email address" if $$o{q}->param('emailmergeto') eq '';
    return "enter an email subject" if $$o{q}->param('emailmergesubject') eq '';
    return "enter email from address" if $$o{q}->param('emailmergefrom') eq '';
    return "enter an email body" if $$o{q}->param('emailmergebody') eq '';

    my $id = $$o{q}->param('oq_autoaction_id');
    my $trigger_mask = int($$o{q}->param('automateemailmergetype'));

    # get interval minutes
    my $min = int($q->param('automateemailmergerepeatintervalmin'));
    $min = 15 if $min < 15;

    # create a human description of the action
    my $user_title;
    { my @x;
      if ($trigger_mask & 1) { push @x, 'all';      }
      if ($trigger_mask & 2) { push @x, 'modified'; }
      if ($trigger_mask & 4) { push @x, 'created';  }
      my $trigger_descr = join('OR', @x);
      $user_title = "Send email to: ".$q->param('emailmergeto')."; subject: ".$q->param('emailmergesubject')." for $trigger_descr records in '$$o{schema}{title}'";
      $user_title .= " matching filter: ".$q->param('filter_descr') if $q->param('filter_descr') ne '';
      $user_title .= " every $min minutes.";
    }

    # save the params
    my $params;
    { my $x = {};
      my @names = $$o{q}->param();
      foreach my $n (@names) {
        $$x{$n} = $$o{q}->param($n);
      }
      delete $$x{page};
      delete $$x{rows_page};
      delete $$x{on_select};
      delete $$x{act};
      $params = encode_json($x);
    }

    # save record in database
    if ($id) {
      $$o{dbh}->do("UPDATE oq_autoaction SET uri=?, oq_title=?, user_title=?, params=?, repeat_interval_min=?, trigger_mask=?, error_txt=NULL WHERE id=?", undef, $$o{schema}{URI},$$o{schema}{title},$user_title,$params,$min,$trigger_mask,$id);
    } else {
      my @dt = localtime;
      my $now = ($dt[5] + 1900).'-'.sprintf('%02d',$dt[4] + 1).'-'.sprintf('%02d',$dt[3]).' '.sprintf('%02d',$dt[2]).':'.sprintf('%02d',$dt[1]);
      $$o{dbh}->do("INSERT INTO oq_autoaction (uri,oq_title,user_title,params,repeat_interval_min,trigger_mask,last_run_dt,start_dt) VALUES (?,?,?,?,?,?,?,?)", undef, $$o{schema}{URI},$$o{schema}{title},$user_title,$params,$min,$trigger_mask,$now,$now);
    }

    return "<strong>saved automated action:</strong> ".escapeHTML($user_title);
  }

  # execute an emailmerge given the configured params
  elsif ($act eq 'execute') {
    my $num_ok  = 0;
    my $num_err = 0;
    my %errs;
    my $emailAr = create_emails($o, $opts);
    $$opts{sendallemails}->($emailAr);

    # look through sent emails, get stats
    foreach my $email (@$emailAr) {
      if ($$email{error}) {
        $num_err++;
        $errs{$$email{error}}++;
      } else {
        $num_ok++;
      }
    }

    my $rv = "<p>Sent: $num_ok; Errors: $num_err</p>";

    if ($num_err > 0) {
      $rv .= "<p><h4>Error Messages</h4><table>";
      foreach my $msg (sort %errs) {
        my $cnt = $errs{$msg};
        $rv .= "<tr><td>".escapeHTML($msg)."</td><td>".escapeHTML($cnt)."</td></tr>";
      }
      $rv .= "</table></p>";
    }

    return "<div class=OQemailmergeview>".$rv."</div>";
  }




  # render the default view
  my $buf;

  # set default params if we are creating a new record
  if (! defined $q->param('emailmergeto')) {
    $q->param('emailmergeto', $$opts{to});
    $q->param('emailmergesubject', $$opts{subject});
    $q->param('emailmergebody', $$opts{body});
    $q->param('emailmergegreeting', $$opts{greeting});
    $q->param('emailmergefooter', $$opts{footer});
  }

  # find all template variables
  my @vars = (
    keys %{$$opts{template_vars}},
    keys %{$$o{schema}{select}}
  );
  @vars = sort @vars;

  my $vars = join('', map { "<div class=OQTemplateVar>&lt;".escapeHTML($_)."&gt;</div>" } @vars);
  my $readonlyto = 'readonly' if $$opts{readonly_to};
  my $readonlyfrom = 'readonly' if $$opts{readonly_from};
  $buf .= "
<div class=OQemailmergetool>
<div class=OQemailmergeform>
<p>
<label>to</label><br>
<input type=text name=emailmergeto value='".escapeHTML($$o{q}->param('emailmergeto'))."' $readonlyto>

<p>
<label>from</label><br>
<input type=text name=emailmergefrom value='".escapeHTML($$o{q}->param('emailmergefrom'))."' $readonlyfrom>

<p>
<label>subject</label><br>
<input type=text name=emailmergesubject value='".escapeHTML($$o{q}->param('emailmergesubject'))."'>

<p>
<label>greeting</label><br>
<textarea name=emailmergegreeting>".escapeHTML($$o{q}->param('emailmergegreeting'))."</textarea><br>
<small>Enter text that will appear at the top of the email.</small>

<p>
<label>body</label><br>
<textarea name=emailmergebody>".escapeHTML($$o{q}->param('emailmergebody'))."</textarea><br>
<small>Multiple emails to the same person with the same subject will have their bodies bundled together.</small>

<p>
<label>footer</label><br>
<textarea name=emailmergefooter>".escapeHTML($$o{q}->param('emailmergefooter'))."</textarea><br>
<small>Enter text that will appear at the bottom of the email.</small>

<p>
<input type=hidden name=oq_autoaction_id value='".escapeHTML($$o{q}->param('oq_autoaction_id'))."'>
<label><input type=checkbox name=automateemailmerge value=1";
  $buf .= " checked" if $$o{q}->param('automateemailmerge') eq '1';
  $buf .= "> Automatically send email</label> for
<select name=automateemailmergetype><option value=1>all";
  if ($$o{schema}{select}{DTM}) {
    $buf .= "<option value=2";
    $buf .= " selected" if $$o{q}->param('automateemailmergetype') eq '2';
    $buf .= ">modified";
  }
  if ($$o{schema}{select}{DTC}) {
    $buf .= "<option value=4";
    $buf .= " selected" if $$o{q}->param('automateemailmergetype') eq '4';
    $buf .= ">created";
  }
  if ($$o{schema}{select}{DTC} && $$o{schema}{select}{DTM}) {
    $buf .= "<option value=6";
    $buf .= " selected" if $$o{q}->param('automateemailmergetype') eq '6';
    $buf .= ">modified OR created";
  }
  $buf .= "</select> records every
<input type=text style='width: 3em;' name=automateemailmergerepeatintervalmin value='"
  .escapeHTML($$o{q}->param('automateemailmergerepeatintervalmin') || 60)."'> minutes.

<p class=EmailMergeCmdBar>
<button type=button class=OQEmailMergeDeleteAutoActionBut>delete automatic action</button>
<button type=button class=OQEmailMergeSaveAutoActionBut>save automatic action</button>
<button type=button class=OQEmailMergePreviewBut>preview</button>
</p>

</div>

<div class=OQemailmergetemplatevars>
<h4>Template Variables</h4>
<div class=OQemailmergetemplatevarlist>
$vars
</div>
</div>

</div>

".'
<script>
function updateemailmergecmdbar() {
  if ($("input[name=automateemailmerge]:checked").length==0) {
    $("button.OQEmailMergePreviewBut").css("visibility","visible");
    $("button.OQEmailMergeSaveAutoActionBut").css("visibility","hidden");
    $("button.OQEmailMergeDeleteAutoActionBut").css("visibility","hidden");
  } else {
    $("button.OQEmailMergePreviewBut").css("visibility","hidden");
    $("button.OQEmailMergeSaveAutoActionBut").css("visibility","visible");
    if ($("input[name=oq_autoaction_id]").val()) {
      $("button.OQEmailMergeDeleteAutoActionBut").css("visibility","visible");
    } else {
      $("button.OQEmailMergeDeleteAutoActionBut").css("visibility","hidden");
    }
  }
  return true;
}
$("input[name=automateemailmerge]").click(updateemailmergecmdbar);
updateemailmergecmdbar();
</script>
';

  return $buf;
}

1;
