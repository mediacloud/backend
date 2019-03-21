

alter table story_sentences add is_dup boolean null;

-- we have to do this in a function to create the partial index on a constant value,
-- which you cannot do with a simple 'create index ... where publish_date > now()'
create or replace function create_initial_story_sentences_dup() RETURNS boolean as $$
declare
    one_month_ago date;
begin
    select now() - interval '1 month' into one_month_ago;

    raise notice 'date: %', one_month_ago;

    execute 'create index story_sentences_dup on story_sentences( md5( sentence ) ) ' ||
        'where week_start_date( publish_date::date ) > ''' || one_month_ago || '''::date';

    return true;
END;
$$ LANGUAGE plpgsql;

select create_initial_story_sentences_dup();



