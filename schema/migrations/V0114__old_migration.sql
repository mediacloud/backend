

create function insert_controversy_tag_set() returns trigger as $insert_controversy_tag_set$
    begin
        insert into tag_sets ( name, label, description )
            select 'controversy_'||NEW.name, NEW.name||' controversy', 'Tag set for stories within the '||NEW.name||' controversy.';
        
        select tag_sets_id into NEW.controversy_tag_sets_id from tag_sets where name = 'controversy_'||NEW.name;

        return NEW;
    END;
$insert_controversy_tag_set$ LANGUAGE plpgsql;

create trigger controversy_tag_set before insert on controversies
    for each row execute procedure insert_controversy_tag_set();         




