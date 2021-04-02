CREATE OR REPLACE PROCEDURE remove_employee(eid int, dep_date date)
AS $$
BEGIN
    IF EXISTS(SELECT 1 FROM Managers AS M WHERE M.eid = eid) THEN
        IF EXISTS(SELECT 1 FROM Course_areas AS CA WHERE CA.eid = eid) THEN
            RAISE EXCEPTION 'No departure of Manager managing a course area is allowed.';
        END IF;
    ELSIF EXISTS(SELECT 1 FROM Administrators AS A WHERE A.eid = eid) THEN
        IF EXISTS(SELECT 1 FROM Course_offerings AS CO WHERE CO.eid = eid AND CO.registration_deadline > dep_date) THEN
            RAISE EXCEPTION 'No departure of Administrator before a course registration closes is allowed.';
        END IF;
    ELSIF EXISTS(SELECT 1 FROM INSTRUCTORS AS I WHERE I.eid = eid) THEN
        IF EXISTS(SELECT 1 FROM Sessions AS S WHERE S.eid = eid AND S.start_date > dep_date) THEN
            RAISE EXCEPTION 'No departure of Instructor after a session has started is allowed.';
        END IF;
    END IF;

    --update departure date
    UPDATE Employees
    SET depart_date = dep_date
    WHERE id = eid;

    COMMIT;
END;
$$ LANGUAGE plpgsql;

--in progress
CREATE OR REPLACE FUNCTION get_available_instructors(course_identifier int, start_date date, end_date date) // check this
RETURNS TABLE AS $$
DECLARE
    start_month int := SELECT EXTRACT(MONTH FROM start_date);
    end_month int := SELECT EXTRACT(MONTH FROM end_date);
    course_area_chosen text := SELECT course_area FROM Courses WHERE course_id = course_identifier;
    curs CURSOR FOR (
    SELECT eid, session_date, start_time, end_time FROM (SELECT * FROM (Instructors natural join Specializes) WHERE name = course_area_chosen) AS X natural join Sessions AS Y;
    );
    instructor_id int;
    total_hours int;
    course_day int;

BEGIN
END;
$$ LANGUAGE plpgsql;

--in progress
CREATE TYPE information_session AS (session_date date, start_hour time, room_id int);

CREATE OR REPLACE PROCEDURE add_course_offering(course_id int, launch_date date,
fees numeric, deadline date, target_num int, admin_id int, VARIADIC sessions information_session[])
AS $$
DECLARE
    end_time time;
    seating_capacity int;
    room_id int;
    all_instructors boolean := TRUE;
    earliest_session information_session := $7[0];
    latest_session information_session := $7[0];
    current_session_number int := 1;
    duration int := (SELECT duration FROM Courses AS C WHERE C.course_id = course_id);
    course_area text := (SELECT name FROM Courses AS C WHERE C.course_id = course_id);
    mid int := (SELECT eid FROM Course_areas WHERE name = course_area);
    possible_instructor int;
BEGIN

    IF EXISTS (SELECT 1 FROM Course_offerings AS CO WHERE CO.launch_date = launch_date AND CO.course_id = course_id) THEN
        RETURN;
    END IF;

    FOREACH new_session IN ARRAY $7
    LOOP

        -- find start date
        IF (new_session.session_date < earliest_session.session_date) THEN
            earliest_session = new_session;
        END IF;

        --find end date
        IF (new_session.session_date > latest_session.session_date) THEN
            latest_session = new_session;
        END IF;

        --check if weekday
        IF (EXTRACT(dow from new_session.session_date::timestamp) = 6 OR EXTRACT(dow from new_session.session_date::timestamp) == 7) THEN
            ROLLBACK;
            RETURN;
        END IF;

        room_id := new_session.room_id;
        seating_capacity := seating_capacity + (SELECT seating_capacity FROM Rooms WHERE rid = room_id);
        -- check if room currently has a clashing class
        IF EXISTS(SELECT 1 FROM Sessions AS S WHERE S.session_date = new_session.session_date AND S.rid = room_id AND (S.start_time < new_session.start_hour OR S.end_time > end_time)) THEN
            ROLLBACK;
            RETURN;
        END IF;


        end_time := start_time + duration;
        --check if session is valid
        IF ((new_session.start_time >= '0900' and start_time < '1200' or start_time >= '1400' and start_time < '1800') AND (end_time <= '1800' OR (end_time <= '1200' AND end_time >= '1400'))) THEN

            --check if there is session from same course offering with the same day and time
            IF EXISTS (SELECT 1 FROM Sessions AS S WHERE S.course_id = course_id AND S.launch_date = launch_date AND S.start_time = new_session.start_time) THEN
                ROLLBACK;
                RETURN;
            END IF;

            --valid session, check if there is an instructor available to teach this session

            WITH Part_time_instructor_Specializes AS (
                SELECT *, (end_time - start_time) AS duration FROM (Part_time_Instructors natural join Specializes) AS X WHERE X.name = course_area
                AND (EXTRACT(MONTH FROM session_date) = EXTRACT(MONTH FROM new_session.session_date) AND (end_time - start_time) + duration <= 30)
            ), Instructor_sessions AS (
                SELECT * FROM (Part_time_instructor_Specializes NATURAL LEFT JOIN Sessions) AS merging WHERE merging.start_time < new_session.start_hour AND (merging.end_time + 1) < end_time
            ), Part_time_filtered AS (
                SELECT * FROM Part_time_instructor_Specializes NATURAL JOIN Instructor_sessions
            ) SELECT eid INTO possible_instructor FROM Part_time_filtered LIMIT 1;

            IF (possible_instructor IS NULL) THEN
                WITH Full_time_instructor_Specializes AS(
                    SELECT * FROM (Full_time_Instructors natural join Specializes) AS X WHERE X.name = course_area
                ), Instructor_sessions AS (
                    SELECT * FROM (Full_time_instructor_Specializes NATURAL LEFT JOIN Sessions) AS merging WHERE merging.start_time < new_session.start_hour AND (merging.end_time + 1) < end_time
                ) SELECT eid INTO possible_instructor FROM Instructor_sessions LIMIT 1;
            END IF;

            -- no full-time or part-time instructor is free
            IF (possible_instructor IS NULL) THEN
                all_instructors := FALSE;
                ROLLBACK;
                RETURN;
            END IF;
        END IF;

        --insert this session into Sessions table
        INSERT INTO Sessions(sid, session_date, start_time, end_time, rid, eid, launch_date, course_id)
        VALUES (current_session_number, new_session.session_date, new_session.start_hour, end_time, room_id, possible_instructor, launch_date, course_id);

    END LOOP;

    --valid course offering with deadline at least 10 days from earliest session
    IF (deadline - earliest_session.session_date < 10) THEN
        ROLLBACK;
        RETURN;
    END IF;

    IF (all_instructors) THEN
        INSERT INTO Course_offerings(launch_date, start_date, end_date, registration_deadline, target_number_registrations, seating_capacity, fees, eid, mid)
        VALUES (launch_date, earliest_session.session_date, latest_session.session_date, deadline, target_num, seating_capacity, fees, eid, mid);
    END IF;
    COMMIT;

END;
$$ LANGUAGE plpgsql;

--in progress
CREATE OR REPLACE FUNCTION get_my_course_package(cust_id int)
RETURNS TABLE (j json) AS $$
DECLARE

BEGIN

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE update_course_session(cust_id int, course_id int, launch_date date, session_id int)
AS $$
DECLARE
    new_session_launch_date date;
    new_session_course_id int;
    total_count int;
    room_id int;
    seating_limit int;
BEGIN
    SELECT launch_date, course_id, rid INTO new_session_launch_date, new_session_course_id, room_id
    FROM Sessions
    WHERE sid = session_id;
    IF (new_session_course_id = session_id AND new_session_launch_date = launch_date) THEN
        seating_limit := (SELECT seating_capacity FROM Rooms WHERE rid = room_id);
        total_count := total_count + (SELECT count(*) FROM Registers WHERE sid = session_id);
        total_count := total_count + (SELECT count(*) FROM Redeems WHERE sid = session_id);
        IF (total_count <= seating_limit) THEN
            IF EXISTS(SELECT * FROM Registers AS R WHERE R.cust_id = cust_id AND R.course_id = course_id AND R.launch_date = launch_date) THEN
                UPDATE Registers as R
                SET R.sid = session_id
                WHERE R.course_id = course_id AND R.launch_date = launch_date AND R.cust_id = cust_id;
            ELSIF EXISTS(SELECT * FROM Redeems AS Re WHERE Re.cust_id = cust_id AND Re.course_id = course_id AND Re.launch_date = launch_date) THEN
                UPDATE Redeems as Re
                SET Re.sid = session_id
                WHERE Re.course_id = course_id AND Re.launch_date = launch_date AND Re.cust_id = cust_id;
            END IF;
        END IF;
    END IF;
    COMMIT;
END;
$$ LANGUAGE plpgsql;

--check: package_credit refers to the current amount of credit in active package, or is it the credit refunded (1 or 0).
CREATE OR REPLACE PROCEDURE cancel_registration(cust_id int, course_id int, launch_date date)
AS $$
DECLARE
    current_date date := (SELECT NOW()::date);
    start_session date;
    refund_amt numeric := 0.00;
    course_amount numeric  := (SELECT fees FROM Course_offerings AS CO WHERE CO.course_id = course_id AND CO.launch_date = launch_date);
    package_credit int := 0;
    session_id int := 0;
BEGIN
    SELECT session_date, sid INTO start_session, session_id
    FROM Sessions
    WHERE R.course_id = course_id AND R.launch_date = launch_date AND R.cust_id = cust_id;

    IF EXISTS(SELECT * FROM Registers AS R WHERE R.cust_id = cust_id AND R.course_id = course_id AND R.launch_date = launch_date) THEN
        IF (start_session - current_date >= 7) THEN
            refund_amt := course_amount * 0.9;
            INSERT INTO Cancels VALUES (current_date, refund_amt, package_credit, cust_id, session_id, course_id, launch_date);
            COMMIT;
        ELSIF (start_session - current_date >= 0 and start_session - current_date < 7) THEN
            INSERT INTO Cancels VALUES (current_date, refund_amt, package_credit, cust_id, session_id, course_id, launch_date);
            COMMIT;
        ELSE:
            RAISE EXCEPTION 'The session you are trying to cancel has ended already.';
        END IF;
    ELSIF EXISTS(SELECT * FROM Redeems AS Re WHERE Re.cust_id = cust_id AND Re.course_id = course_id AND Re.launch_date = launch_date) THEN
        IF (start_session - current_date >= 7) THEN
            package_credit := 1;
            --add one credit to current active package
            UPDATE Buys AS B
            SET num_remaining_redemptions = num_remaining_redemptions + 1
            WHERE B.cust_id = cust_id AND (num_remaining_redemptions > 0 OR current_date - B.buy_date <= 7);
            --insert into cancels table
            INSERT INTO Cancels VALUES (current_date, refund_amt, package_credit, cust_id, session_id, course_id, launch_date);
            COMMIT;
        ELSIF (start_session - current_date >= 0 and start_session - current_date < 7) THEN
            INSERT INTO Cancels VALUES (current_date, refund_amt, package_credit, cust_id, session_id, course_id, launch_date);
            COMMIT;
        ELSE:
            RAISE EXCEPTION 'The session you are trying to cancel has ended already.';
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;

--started defined based on day, will that be ok, or should I take into account of time?, might also want to refactor the code as it looks a bit bad
CREATE OR REPLACE PROCEDURE update_instructor(session_id int, course_id int, launch_date date, new_instructor_id int)
AS $$
DECLARE
    current_date date := (SELECT NOW()::date);
    session_date date := (SELECT session_date FROM Sessions WHERE sid = session_id);
    session_start_time time := (SELECT start_time FROM Sessions WHERE sid = session_id);
    session_end_time time := (SELECT end_time FROM Sessions WHERE sid = session_id);
    closest_end_session_new_instructor time;
    total_hours_part_time int;
BEGIN
    IF (session_date - current_date >= 0) THEN
        IF EXISTS (SELECT 1 FROM Full_time_Instructors WHERE eid = new_instructor_id) THEN
            IF NOT EXISTS(SELECT 1 FROM Sessions AS S WHERE (S.start_time < session_start_time or S.end_time > session_end_time)) THEN
                closest_end_session_new_instructor := (SELECT end_time FROM Sessions WHERE sid = session_id AND end_hour < session_start_time ORDER BY DESC LIMIT 1);
                IF (closest_end_session_new_instructor >= 1) THEN
                    UPDATE Sessions AS S
                    SET eid = new_instructor_id
                    WHERE S.sid = session_id;
                    COMMIT;
                END IF;
            END IF;
        ELSIF EXISTS (SELECT 1 FROM Part_time_Instructors WHERE eid = new_instructor_id) THEN
            SELECT sum(end_time - start_time) into total_hours_part_time
            FROM Sessions AS S
            WHERE S.eid = new_instructor_id AND (EXTRACT(MONTH from S.session_date) = EXTRACT(MONTH from session_date));
            IF (total_hours_part_time + (session_end_time - session_start_time) <= 30) THEN
                IF NOT EXISTS(SELECT 1 FROM Sessions AS S WHERE (S.start_time < session_start_time or S.end_time > session_end_time)) THEN
                    closest_end_session_new_instructor := (SELECT end_time FROM Sessions WHERE sid = session_id AND end_hour < session_start_time ORDER BY DESC LIMIT 1);
                    IF (closest_end_session_new_instructor >= 1) THEN
                        UPDATE Sessions AS S
                        SET eid = new_instructor_id
                        WHERE S.sid = session_id;
                        COMMIT;
                    END IF;
                END IF;
            END IF;
        END IF;
    END IF;

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pay_salary()
RETURNS TABLE (employee_id int, employee_name text, status text, number_of_work_days int, work_hours int, hourly_rate numeric, monthly_salary numeric, salary_amount_paid numeric) AS $$
DECLARE
    current_month date := (SELECT EXTRACT(MONTH FROM NOW()));
    current_month_days int := (SELECT EXTRACT(days FROM date_trunc('month', NOW()) + interval '1 month - 1 day')::int);
    curs CURSOR for (SELECT * FROM Employees ORDER BY eid ASC);
    r RECORD;
    current_eid int;

    departure_date date;
    joined_date date;

BEGIN
    OPEN curs;
    LOOP
        FETCH curs INTO r;
        EXIT WHEN NOT FOUND;
        current_eid := r.eid;
        employee_id := current_eid;
        SELECT dep_date, join_date, name INTO departure_date, joined_date, employee_name
        FROM Employees
        WHERE eid = current_eid;
        IF EXISTS(SELECT 1 FROM Full_time_Emp AS FT WHERE FT.eid = current_eid) THEN
            monthly_salary := (SELECT monthly_salary FROM Full_time_Emp WHERE eid = current_eid);
            status := 'Full-time';
            work_hours := NULL;
            hourly_rate := NULL;

            --full time and leaving
            IF (departure_date IS NOT NULL AND (EXTRACT(MONTH FROM departure_date) = current_month)) THEN
                -- join and leave in the same current month
                IF (EXTRACT(MONTH FROM joined_date) = current_month) THEN
                    number_of_work_days := EXTRACT(DAY FROM departure_date)::int - EXTRACT(DAY FROM joined_date)::int + 1;
                    salary_amount_paid := monthly_salary * (number_of_work_days/current_month_days);
                    -- add into pay_slips table
                    INSERT INTO Pay_slips (payment_date, amount, num_work_hours, num_work_days, eid)
                    VALUES (NOW(), salary_amount_paid, NULL, number_of_work_days, current_eid);

                    RETURN NEXT;

                --join different from current month, leave in current month
                ELSE
                    number_of_work_days := EXTRACT(DAY FROM departure_date) - 1 + 1;
                    salary_amount_paid := monthly_salary * (number_of_work_days/current_month_days);
                    -- add into pay_slips table
                    INSERT INTO Pay_slips (payment_date, amount, num_work_hours, num_work_days, eid)
                    VALUES (NOW(), salary_amount_paid, NULL, number_of_work_days, current_eid);

                    RETURN NEXT;
                END IF;
            END IF;
            number_of_work_days := current_month_days;
            salary_amount_paid := monthly_salary;
            RETURN NEXT;

        ELSIF EXISTS(SELECT 1 FROM Part_time_Emp AS PT WHERE PT.eid = current_eid) THEN
            hourly_rate := (select hourly_rate FROM Part_time_Emp WHERE eid = current_eid);
            status := 'Part-time';
            WITH calc_hours AS (
                SELECT (end_time - start_time) AS duration
                FROM Sessions
                WHERE eid = current_eid AND (EXTRACT(MONTH FROM session_date) = current_month)
            ) SELECT sum(duration) INTO work_hours FROM calc_hours;
            salary_amount_paid := work_hours * hourly_rate;
            monthly_salary := NULL;
            number_of_work_days := NULL;

            -- add into pay_slips table
            INSERT INTO Pay_slips (payment_date, amount, num_work_hours, num_work_days, eid)
            VALUES (NOW(), salary_amount_paid, work_hours, NULL, current_eid);

            RETURN NEXT;
        END IF;
    END LOOP;
    CLOSE curs;

END;
$$ LANGUAGE plpgsql;


