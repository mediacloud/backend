

create type bot_policy_type AS ENUM ( 'all', 'no bots', 'only bots');
alter table snapshots add bot_policy              bot_policy_type null;


