

create type retweeter_scores_match_type AS ENUM ( 'retweet', 'regex' );
alter table retweeter_scores add match_type retweeter_scores_match_type not null default 'retweet';



