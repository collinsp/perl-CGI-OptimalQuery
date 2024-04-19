package CGI::OptimalQuery::ExportDataTool;

use strict;

sub on_open {
  return "


<label class=ckbox><input type=checkbox class=OQExportAllResultsInd checked> all pages</label>
<p>
<strong>download as..</strong><br>
<button type=button class=OQDownloadCSV title='Download as a Comma Separated Values file compatible with Microsoft Excel'>CSV</button>
<button type=button class=OQDownloadHTML title='Download as an HTML file which is viewable in any web browser'>HTML</button>
<button type=button class=OQDownloadJSON title='Download as an JSON file - a common data format other computer systems can process'>JSON</button>
<button type=button class=OQDownloadXML title='Download as an XML file - a common data format other computer systems can process'>XML</button>";
}

sub activate {
  my ($o) = @_;
  $$o{schema}{tools}{export} ||= {
    title => "Export Data",
    on_open => \&on_open
  };
}

1;
