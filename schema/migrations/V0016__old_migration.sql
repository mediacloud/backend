


CREATE OR REPLACE FUNCTION story_triggers_enabled() RETURNS boolean  LANGUAGE  plpgsql AS $$
BEGIN

    BEGIN
       IF current_setting('PRIVATE.use_story_triggers') = '' THEN
          perform enable_story_triggers();
       END IF;
       EXCEPTION when undefined_object then
        perform enable_story_triggers();

     END;

    return true;
    return current_setting('PRIVATE.use_story_triggers') = 'yes';
END$$;

