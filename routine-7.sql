--get free hours for instructors that could teach the course (on days where the instructor has other assigned sessions)
CREATE OR REPLACE FUNCTION get_instructor_free_hours (cid int, start_date date, end_date date)
RETURNS TABLE(eid int, name text, num_hours int, day date, available_hours time []) AS $$
DECLARE
	curs CURSOR FOR (
	select session_date, S2.eid, I1.name
	from Sessions S1, Specializes S2, Courses C1, Instructors I1
	where S1.eid = S2.eid
	and I1.eid = S1.eid
	and S2.name = C1.name
	and C1.course_id = cid
	and S1.session_date >= start_date
	and S1.session_date <= end_date
	);
	r RECORD;
	start_hour time;
	same_time int;

BEGIN

	OPEN curs;
	LOOP
		FETCH curs INTO r;
		EXIT WHEN NOT FOUND;

			eid := r.eid;
			name := r.name;
			select sum(DATE_PART('hour', end_time - start_time) ) into num_hours
			from Sessions S1
			where S1.eid = r.eid
			and extract(month from S1.session_date) = extract(month from r.session_date)
			and extract(year from S1.session_date) = extract(year from r.session_date);
			day := r.session_date;
			start_hour := '0900';
			available_hours := array[];

			while start_hour < '1800'
			LOOP

				select count(*) into same_time
				from Sessions S1
				where S1.eid = r.eid
				and S1.course_id = cid 
				and S1.session_date = r.session_date 
				and (start_hour >= r.start_time and start_hour <= r.end_time)
				or DATE_PART('hour', r.start_time - start_hour) < 1
				or DATE_PART('hour', start_hour - r.end_time) < 1;

				IF same_time=0 and (start_hour < '1200' or start_hour > '1400') THEN
					available_hours := array_append(available_hours, start_hour);
				END IF;

				IF start_hour = '1100' THEN
					start_hour := start_hour + '3 hour'::interval;
				ELSE
					start_hour := start_hour + '1 hour'::interval;
				END IF;

			END LOOP;
		
			RETURN NEXT;

	END LOOP;
	CLOSE curs;
END;
$$ LANGUAGE plpgsql;

--get free hours for instructors that could teach the course (on days where the instructor has NO assigned sessions)
CREATE OR REPLACE FUNCTION get_instructor_free_days(cid int, start_date date, end_date date)
RETURNS TABLE(eid int, name text, num_hours int, day date, available_hours time []) AS $$
DECLARE
	curs CURSOR FOR (
	select distinct S2.eid, I1.name
	from Specializes S2, Courses C1, Instructors I1
	where I1.eid = S2.eid
	and I1.eid = S1.eid
	and S2.name = C1.name
	and C1.course_id = cid
	);
	r RECORD;
	start_day date;
	same_time int;

BEGIN
	OPEN curs;
	LOOP
		FETCH curs INTO r;
		EXIT WHEN NOT FOUND;

			eid := r.eid;
			name := r.name;
			select sum(DATE_PART('hour', end_time - start_time) ) into num_hours
			from Sessions S1
			where S1.eid = r.eid
			and extract(month from S1.session_date) = extract(month from start_day)
			and extract(year from S1.session_date) = extract(year from start_day);
			available_hours := array ['0900', '1000', '1100', '1200', '1300', '1400', '1500', '1600', '1700'];
			start_day := start_date;

			
			while start_day <= end_date
			LOOP

				select count(*) into same_time
				from Sessions S1
				where S1.eid = r.eid
				and S1.course_id = cid 
				and S1.session_date = start_date;

				IF same_time=0 THEN
					day := start_day;
					RETURN NEXT;
				END IF;

				start_day := start_day + '1 day'::interval;

			END LOOP;
		
			RETURN NEXT;

	END LOOP;
	CLOSE curs;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_available_instructors(cid int, start_date date, end_date date)
RETURNS TABLE(eid int, name text, num_hours int, day date, available_hours time []) as $$
select * from
(
select * from get_instructor_free_days(cid, start_date, end_date)
union
select * from get_instructor_free_hours(cid, start_date, end_date)
) T1
order by eid, day asc;
$$ LANGUAGE sql;
