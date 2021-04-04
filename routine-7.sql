CREATE OR REPLACE FUNCTION get_available_instructors(cid int, start_date date, end_date date)
RETURNS TABLE(eid int, name text, num_hours int, day date, available_hours time []) AS $$
DECLARE
	curs CURSOR FOR (
	select distinct S2.eid, I1.name
	from Specializes S2, Courses C1, Instructors I1
	where I1.eid = S2.eid
	and I1.eid = S1.eid
	and S2.name = C1.name
	and C1.course_id = cid
	order by eid asc
	);
	r RECORD;
	start_day date;
	start_hour time;
	num_part_time_hours int;

BEGIN
	OPEN curs;
	LOOP
		FETCH curs INTO r;
		EXIT WHEN NOT FOUND;
				select sum(DATE_PART('hour', end_time - start_time) ) into num_hours
				from Sessions S1
				where S1.eid = r.eid
				and extract(month from S1.session_date) = extract(month from start_day)
				and extract(year from S1.session_date) = extract(year from start_day);
			
			IF EXISTS (select 1 from Part_time_Instructors where eid = r.eid) and num_hours > 30 THEN

			ELSE
				eid := r.eid;
				name := r.name;
				start_day := start_date;
			
				while start_day <= end_date
				LOOP

					day := start_day;

					IF NOT EXISTS (select 1 
						from Sessions S1 
						where S1.eid = r.eid 
						and S1.course_id = cid 
						and S1.session_date = start_day) THEN
							available_hours := array ['0900', '1000', '1100', '1200', '1300', '1400', '1500', '1600', '1700'];
							RETURN NEXT;
					ELSE
						start_hour := '0900';
						available_hours := array[];

						while start_hour < '1800'
						LOOP

							IF NOT EXISTS (select 1 
								from Sessions S1 
								where S1.eid = r.eid 
								and S1.course_id = cid  
								and S1.session_date = r.session_date 
								and (start_hour >= r.start_time and start_hour <= r.end_time)
								or DATE_PART('hour', r.start_time - start_hour) < 1
								or DATE_PART('hour', start_hour - r.end_time) < 1) THEN
									available_hours := array_append(available_hours, start_hour);
							END IF;

							IF start_hour = '1100' THEN
								start_hour := start_hour + '3 hour'::interval;
							ELSE
								start_hour := start_hour + '1 hour'::interval;
							END IF;

						END LOOP;

						RETURN NEXT;

					END IF;

					start_day := start_day + '1 day'::interval;

				END LOOP;
			END IF;
	END LOOP;
	CLOSE curs;
END;
$$ LANGUAGE plpgsql;