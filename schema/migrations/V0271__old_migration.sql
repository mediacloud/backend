


CREATE OR REPLACE FUNCTION media_set_retains_sw_data_for_date(v_media_sets_id int, test_date date, default_start_day date, default_end_day date) RETURNS BOOLEAN AS
$$
DECLARE
    media_rec record;
    current_time timestamp;
    start_date   date;
    end_date     date;
BEGIN
    current_time := timeofday()::timestamp;

    -- RAISE NOTICE 'time - %', current_time;

   media_rec = media_set_sw_data_retention_dates( v_media_sets_id, default_start_day,  default_end_day ); -- INTO (media_rec);

   start_date = media_rec.start_date; 
   end_date = media_rec.end_date;

    -- RAISE NOTICE 'start date - %', start_date;
    -- RAISE NOTICE 'end date - %', end_date;

    return  ( ( start_date is null )  OR ( start_date <= test_date ) ) AND ( (end_date is null ) OR ( end_date >= test_date ) );
END;
$$
LANGUAGE 'plpgsql' STABLE
 ;

