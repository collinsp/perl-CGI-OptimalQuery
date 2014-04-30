# -*- perl -*-

# t/003_sqlite.t - check module loading and create testing directory
use CGI::OptimalQuery();
use DBI();

use Test::More tests => 5;
my $TOTAL_TESTS = 5;

use warnings;
no warnings qw( uninitialized );

# create test database, make some test data
my $tempdb_fn;
my $prefix = 'oqtestdeleteme_';
my $dbh;

END {
  eval { $dbh->disconnect() if $dbh; }; if ($@) { print STDERR $@; }
  unlink $tempdb_fn if $tempdb_fn;
}
SKIP: {
  eval {
    use File::Temp();
    $tempdb_fn = File::Temp::mktemp('cgi_oq_sqlite_testdb_XXXX');
    $dbh = DBI->connect("dbi:SQLite:dbname=$tempdb_fn","","");
  }; if ($@){}
  skip "could not create sqlite database for testing", $TOTAL_TESTS unless $dbh;

  pass("connect");

  # test people
  $dbh->do("CREATE TABLE ".$prefix."person ( person_id INTEGER, name TEXT, birthdate DATE )");
  my @people = (
    [1, 'Harrison Ford', '1942-07-13'],
    [2, 'Mark Hamill', '1951-09-25'],
    [3, 'Irvin Kershner', '1923-04-29'],
    [4, 'Richard Marquand', '1938-01-01'],
    [5, 'Steven Spielberg', '1946-12-18'],
  );
  $dbh->do("INSERT INTO ".$prefix."person VALUES (?,?,?)", undef, @$_) for @people;

  # test movies
  $dbh->do("CREATE TABLE ".$prefix."movie ( movie_id INTEGER, name TEXT, releaseyear INTEGER, director_person_id INTEGER )");
  my @movies = (
    [1, 'The Empire Strikes Back', 1980, 3],
    [2, 'Return of the Jedi', 1983, 4],
    [3, 'Raiders of the Lost Ark', 1981, 5]
  );
  $dbh->do("INSERT INTO ".$prefix."movie VALUES (?,?,?,?)", undef, @$_) for @movies;

  # test cast
  $dbh->do("CREATE TABLE ".$prefix."moviecast ( movie_id INTEGER, person_id INTEGER)");
  my @cast = ([1,1],[1,2],[2,1],[2,2],[3,1]);
  $dbh->do("INSERT INTO ".$prefix."moviecast VALUES (?,?)", undef, @$_) for @cast;
  pass("create testdb");

  # create a test optimal query
  my $buf;
  my $o = CGI::OptimalQuery->new({
    'URI' => '/Movies',
    'dbh' => $dbh,
    'select' => {
      'ID' => ['movie','movie.movie_id','Movie ID'],
      'name' => ['movie','movie.name','Movie Name'],
      'DIRECTOR' => ['director', 'director.name', "Director's Name"],
      'cast' => ['moviecastperson', 'moviecastperson.name', 'All Cast (seprated by commas)'],
      'DIRECTOR_BITHDATE' => ['director', 'director.birthdate', 'Director Birthdate'],
      'RELEASE_YEAR' => ['movie', 'movie.releaseyear', 'Release Year']
    },
    'output_handler' => sub { $buf .= $_[0] },
    'module' => 'CSV',
    'joins' => {
      'movie' => [undef, $prefix.'movie AS movie'],
      'director' => ['movie', 'LEFT JOIN '.$prefix.'person AS director ON (movie.director_person_id = director.person_id)'],
      'moviecast' => ['movie', 'JOIN '.$prefix.'moviecast AS moviecast ON (movie.movie_id = moviecast.movie_id)', undef, { new_cursor => 1 }],
      'moviecastperson' => ['moviecast', 'JOIN '.$prefix.'person AS moviecastperson ON (moviecast.person_id=moviecastperson.person_id)']
    }
  });
  pass("create object");

  $o->output();

  ok($buf =~ /Return\ of\ the\ Jedi/s, 'lowercase select alias');
  ok($buf =~ /Harrison Ford\, Mark Hamill/s, 'multival field');
}

