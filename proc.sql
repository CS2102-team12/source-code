-- 3
CREATE OR REPLACE PROCEDURE add_customer ( _name TEXT, _home_address TEXT, _contact_number TEXT, _email_address TEXT,
_credit_card_number bigint, _expiry_date date, _cvv_code int) AS $$
DECLARE
    _cust_id INT;
BEGIN
    IF _expiry_date < CURRENT_DATE THEN
        RAISE EXCEPTION 'the card is expired!';
    END IF;
    SELECT COALESCE(MAX(cust_id) + 1,0) INTO _cust_id FROM Customers;
    INSERT INTO Customers
    VALUES (_cust_id,_home_address,_contact_number,_name,_email_address);
    INSERT INTO Credit_Cards
    VALUES (_credit_card_number,_cvv_code,_expiry_date);
    INSERT INTO Owns
    VALUES (_credit_card_number,_cust_id, CURRENT_DATE);
END;
$$ LANGUAGE plpgsql;

-- 5

CREATE OR REPLACE PROCEDURE add_course (_course_title TEXT, _course_description TEXT, _course_area TEXT, _duration INT) AS $$
DECLARE
    _course_id INT;
BEGIN
    IF _course_area IS NULL OR _course_area NOT IN (SELECT name FROM Course_areas) THEN 
        RAISE EXCEPTION 'Invalid course area!';
    END IF;
    SELECT COALESCE(MAX(course_id) + 1,0) INTO _course_id FROM Courses;
    INSERT INTO Courses
    VALUES (_course_id,_duration,_course_title,_course_description,_course_area);
END;
$$ LANGUAGE plpgsql;

-- 6
CREATE OR REPLACE FUNCTION find_instructors (_course_id INT, _session_date DATE, _start_hour INT) 
RETURNS TABLE(eid INT, name TEXT) AS $$
DECLARE
    _start_time Time;
    _end_time TIME;
    _duration INTERVAL;
BEGIN
    IF _course_id IS NULL OR _session_date IS NULL OR _start_hour IS NULL THEN
        RAISE EXCEPTION 'arguments cannot be null!';
    END IF;
    
    _start_time := make_time(_start_hour,0,0);
    -- find the session end time and duration
    SELECT end_time INTO _end_time FROM Sessions 
    WHERE session_date = _session_date AND start_time = _start_time AND course_id = _course_id;
    _duration := _end_time - _start_time;

    IF _end_time IS NULL THEN
        RAISE EXCEPTION 'The session cannot be found!';
    END IF;

    RETURN QUERY
    WITH Filtered_Instructors AS (
        SELECT eid FROM Instructors NATURAL JOIN Specializes NATURAL JOIN Course_areas NATURAL JOIN Courses 
        -- Find all instructors with matching speciality 
        WHERE course_id = _course_id 
        EXCEPT
        -- part timers that are not eligible
        SELECT eid FROM Part_time_Instructors P NATURAL JOIN Sessions WHERE (
            SELECT SUM(end_time - start_time) FROM Sessions WHERE eid = P.eid
        ) > make_interval(hours := 30) - _duration
        EXCEPT
        -- Past employees
        SELECT eid FROM Employees WHERE depart_date IS NOT NULL
        EXCEPT
        -- check that does not clash with existing sessions that is taught
        SELECT eid FROM Sessions WHERE session_date = _session_date AND (
            _start_time - make_interval(hours := 1) >= start_time AND _start_time - make_interval(hours := 1) <= end_time
            OR
            _end_time + make_interval(hours := 1) >= start_time AND _end_time + make_interval(hours := 1) <= end_time
            OR
            _start_time <= start_time AND _end_time >= end_time
        )
    )
    SELECT eid, name FROM Filtered_Instructors NATURAL JOIN Employees;
    
END;
$$ LANGUAGE plpgsql;

-- 9
-- will only return hours, days where it is allowed to host a session.
CREATE OR REPLACE FUNCTION get_available_rooms (_start_date DATE, _end_date DATE)
RETURNS TABLE(_room_id INT, _room_capacity INT, _day DATE, _available_hours INT[]) AS $$
DECLARE
    _counter DATE;
    _row RECORD;
    _hour RECORD;
BEGIN
    IF _start_date IS NULL OR _end_date IS NULL OR _end_date < _start_date THEN
        RAISE EXCEPTION 'Invalid arguments!';
    END IF;

    for _row in select rid, seating_capacity FROM Rooms ORDER BY rid
    loop
        _counter := _start_date;
        _room_id := row.rid;
        _room_capacity := _row.seating_capacity;
        WHILE _counter <= _end_date LOOP
            IF extract(dow from _counter) = 0 OR extract(dow from _counter) = 6 THEN
                CONTINUE;
            END IF;

            _available_hours := ARRAY[];

            for _hour in 9..11 loop
                if NOT _hour <@ ANY(
                    SELECT int4range(extract(hour from start_time),extract(hour from end_time)) 
                    FROM Sessions WHERE rid = _room_id and session_date = _counter
                ) THEN
                    _available_hours := _available_hours || Array[_hour];
                END IF;
            end loop;

            for _hour in 2..5 loop
                if NOT _hour <@ ANY(
                    SELECT int4range(extract(hour from start_time),extract(hour from end_time)) 
                    FROM Sessions WHERE rid = _room_id and session_date = _counter
                ) THEN
                    _available_hours := _available_hours || Array[_hour];
                END IF;
            end loop;
            _day := _counter;
            return NEXT;
            _counter := _counter + make_interval(days := 1);
        END LOOP;
    end loop;
END;
$$ LANGUAGE plpgsql;

-- 13
CREATE OR REPLACE PROCEDURE buy_course_package (_customer_id INT, _package_id INT) AS $$
DECLARE
_credit_card_number BIGINT;
_num_redemptions INT;
BEGIN
    IF _customer_id IS NULL OR _package_id IS NULL THEN
        RAISE EXCEPTION 'All arguments cannot be null!';
    END IF;
    -- check that package is available
    IF _package_id NOT in (
        SELECT package_id FROM Course_packages WHERE CURRENT_DATE >= sale_start_date AND CURRENT_DATE <= sale_end_date
    ) THEN RAISE EXCEPTION 'Package not available!';
    END IF;
    -- check that cid in customers and that customer has no active/partially active package
    IF NOT _customer_id in (
        SELECT cust_id FROM Customers
    ) OR EXISTS (
        SELECT cust_id FROM Buys NATURAL LEFT JOIN Redeems NATURAL JOIN Sessions WHERE cust_id = _customer_id AND (
            num_remaining_redemptions > 0 OR CURRENT_DATE + make_interval(days := 7) < session_date
        ) 
    )
    THEN RAISE EXCEPTION 'The customer must exist in the database and have at most 1 active or partially active package!';
    END IF;

    SELECT card_number INTO _credit_card_number FROM Owns WHERE cust_id = _customer_id ORDER BY from_date DESC LIMIT 1;
    SELECT num_free_registrations INTO _num_redemptions FROM Course_packages WHERE package_id = _package_id;
    -- payment
    INSERT INTO Buys
    VALUES (CURRENT_DATE,_package_id,_credit_card_number,_customer_id,_num_redemptions);
END;
$$ LANGUAGE plpgsql;

-- 15
CREATE OR REPLACE FUNCTION get_available_course_offerings ()
RETURNS TABLE(_course_title TEXT, _course_area TEXT, _start_date DATE, _end_date DATE, _deadline DATE, 
              _course_fees NUMERIC, _num_remaining_seats INT) AS $$
DECLARE
    _number_registrations INT;
    _row RECORD;
BEGIN
    for _row in select course_id, launch_date, title, name, start_date, end_date, registration_deadline, fees, seating_capacity
    FROM Courses NATURAL JOIN Course_offerings 
    WHERE registration_deadline >= CURRENT_DATE
    ORDER BY registration_deadline, title
    LOOP
        SELECT COUNT(*) INTO _number_registrations FROM Registers 
        WHERE course_id = _row.course_id and launch_date = _row.launch_date;
        IF _number_registrations < _row.seating_capacity 
        THEN
            _course_title := _row.title;
            _course_area := _row.name;
            _start_date := _row.start_date;
            _end_date := _row.end_date;
            _deadline := _row.registration_deadline;
            _course_fees := _row._course_fees;
            _num_remaining_seats := _row.seating_capacity - _num_redemptions;
            RETURN NEXT;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- 17
CREATE OR REPLACE PROCEDURE register_session( _customer_id INT, _course_id INT, _launch_date DATE, 
                                              _session_number INT, _use_package BOOLEAN) AS $$
DECLARE
    _buy_date DATE;
    _package_id int;
    _card_number int;
BEGIN
    IF _customer_id IS NULL OR _course_id IS NULL OR _launch_date IS NULL OR _session_number IS NULL OR _use_package IS NULL THEN
        RAISE EXCEPTION 'All arguments cannot be null!';
    END IF;
    IF _session_number NOT IN (
        SELECT sid FROM Sessions NATURAL JOIN Course_offerings 
        WHERE launch_date = _launch_date AND course_id = _course_id AND registration_deadline > CURRENT_DATE
    )
    OR
    _customer_id NOT IN (SELECT cust_id FROM Customers) THEN
        RAISE EXCEPTION 'The session or customer is invalid!';
    END IF;

    IF (
        SELECT COUNT(*) FROM Registers 
        WHERE course_id = _course_id and launch_date = _launch_date AND sid = _session_number
    ) >= (
        SELECT seating_capacity FROM Rooms NATURAL JOIN Sessions 
        WHERE course_id = _course_id and launch_date = _launch_date AND sid = _session_number
    ) THEN
        RAISE EXCEPTION 'The session is full!';
    END IF;        

    IF EXISTS (SELECT 1 FROM Registers WHERE cust_id = _customer_id AND course_id = _course_id AND launch_date = _launch_date ) THEN
        RAISE EXCEPTION 'The customer has already registered for the course offering before!';
    END IF;
    
    IF _use_package THEN
        IF NOT EXISTS (SELECT 1 FROM Buys WHERE cust_id = _customer_id AND num_remaining_redemptions > 0) THEN
            RAISE EXCEPTION 'The customer does not have any eligible package to redeem the session!';
        END IF;
        SELECT buy_date, package_id, card_number INTO _buy_date,_package_id, _card_number FROM Buys 
        WHERE cust_id = _customer_id AND num_remaining_redemptions > 0;
        INSERT INTO Redeems 
        VALUES (CURRENT_DATE, _buy_date, _package_id, _card_number, _customer_id, _session_number, _course_id, _launch_date);
        INSERT INTO Registers 
        VALUES (CURRENT_DATE, _card_number, _customer_id, _session_number, _course_id, _launch_date);
        UPDATE Buys
        SET num_remaining_redemptions = num_remaining_redemptions - 1
        WHERE cust_id = _customer_id AND num_remaining_redemptions > 0;
    ELSE
        SELECT card_number INTO _card_number FROM Owns WHERE cust_id = _customer_id ORDER BY from_date DESC LIMIT 1;
        INSERT INTO Registers 
        VALUES (CURRENT_DATE, _card_number, _customer_id, _session_number, _course_id, _launch_date);
    END IF;
END;
$$ LANGUAGE plpgsql;

-- 22
CREATE OR REPLACE PROCEDURE update_room (_course_id INT, _launch_date DATE, _session_number INT, _new_room_id INT) AS $$
DECLARE
    _session_date INT;
    _session_start_hour INT;
    _session_duration INTERVAL;
BEGIN
    IF _new_room_id IS NULL OR _course_id IS NULL OR _launch_date IS NULL OR _session_number IS NULL THEN
        RAISE EXCEPTION 'All arguments cannot be null!';
    END IF;

    IF NOT EXISTS ( 
        SELECT 1 FROM Sessions WHERE sid = _session_number AND launch_date = _launch_date AND course_id = _course_id
    ) THEN
        RAISE EXCEPTION 'The session cannot be found!';
    END IF;

    SELECT session_date, extract(hour from start_time), end_time - start_time 
    INTO _session_date, _session_start_hour, _session_duration 
    FROM Sessions WHERE sid = _session_number AND launch_date = _launch_date AND course_id = _course_id;
    
    IF NOT EXISTS (
        SELECT 1 FROM find_rooms(_session_date, make_time(_session_start_hour,0,0), _session_duration) WHERE rid = _new_room_id
    ) OR CURRENT_DATE > (
        SELECT session_date FROM Sessions WHERE sid = _session_number AND launch_date = _launch_date AND course_id = _course_id
    ) OR CURRENT_DATE = (
        SELECT session_date FROM Sessions WHERE sid = _session_number AND launch_date = _launch_date AND course_id = _course_id
    ) AND CURRENT_TIME >= (
        SELECT start_time FROM Sessions WHERE sid = _session_number AND launch_date = _launch_date AND course_id = _course_id
    ) OR (
        (SELECT seating_capacity FROM Rooms WHERE rid = _new_room_id) 
        < 
        (SELECT COUNT(*) FROM Registers WHERE course_id = _course_id and launch_date = _launch_date AND sid = _session_number)
    ) THEN
        RAISE EXCEPTION 'The pairing of the room to the session is not valid!';
    END IF;

    UPDATE Sessions 
    SET rid = _new_room_id
    WHERE course_id = _course_id and launch_date = _launch_date AND sid = _session_number;    

END;
$$ LANGUAGE plpgsql;

-- 28
CREATE OR REPLACE FUNCTION popular_courses ()
RETURNS TABLE(_course_id INT, _course_title TEXT, _course_area TEXT, _offerings_this_year INT, _reg_for_latest_offering INT) AS $$
DECLARE
_skip BOOLEAN;
_curr_amt INT;
_last_amt INT;
_course RECORD;
_offering RECORD;
BEGIN
    FOR _course in SELECT * FROM Courses C ORDER BY (
        SELECT COUNT(*) FROM Registers NATURAL JOIN Course_offerings WHERE course_id = C.course_id and start_date = (
            SELECT MAX(start_date) FROM Course_offerings WHERE course_id = C.course_id
        )
    ) DESC, course_id ASC
    LOOP
        IF (
            SELECT COUNT(launch_date) FROM Courses NATURAL JOIN Course_offerings
            WHERE course_id = _course.course_id AND date_part('year',start_date) = date_part('year',CURRENT_DATE)
        ) < 2 THEN
            CONTINUE;
        END IF;

        _last_amt := 0;
        _skip := false;

        FOR _offering in SELECT * FROM Course_offerings 
        WHERE course_id = _course.course_id AND date_part('year',start_date) = date_part('year',CURRENT_DATE) ORDER BY start_date
        LOOP
            SELECT COUNT(*) INTO _curr_amt FROM Registers WHERE course_id = _course.course_id AND launch_date = _offering.launch_date;
            IF _curr_amt <= _last_amt THEN
                _skip := true;
                EXIT;
            END IF;
            _last_amt := _curr_amt;
        END LOOP;

        IF _skip THEN 
            CONTINUE;
        END IF;

        _course_id := _course.course_id;
        _course_title := _course.title;
        _course_area := _course.name;
        SELECT COUNT(launch_date) INTO _offerings_this_year FROM Courses NATURAL JOIN Course_offerings
        WHERE course_id = _course.course_id AND date_part('year',start_date) = date_part('year',CURRENT_DATE);
        _reg_for_latest_offering := _last_amt;
        RETURN NEXT;

    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- 29

CREATE OR REPLACE FUNCTION view_summary_report ( _num_months INT)
RETURNS TABLE (_month INT, _year INT, _salary_paid NUMERIC, _sales_course_packages NUMERIC, 
               _registration_via_credit NUMERIC, _refunded_registration_fees NUMERIC, _num_redemptions INT) AS $$
DECLARE
    _date DATE;
BEGIN
    IF _num_months IS NULL THEN
        RAISE EXCEPTION 'The argument cannot be null!';
    END IF;
    IF _num_months <=0 THEN
        RAISE EXCEPTION 'the number of months specified has to be at least 1!';
    END IF;

    -- each of last n month, from current
    FOR i IN 0.._num_months - 1 LOOP
        _date := CURRENT_DATE - make_interval(months := i);
        _month := date_part('month', _date);
        _year := date_part('year', _date);
        
        SELECT SUM(amount) INTO _salary_paid FROM Pay_slips 
        WHERE date_part('year',payment_date) = _year AND date_part('month',start_date) = _month;

        SELECT SUM(price) INTO _sales_course_packages FROM Buys NATURAL JOIN Course_packages
        WHERE date_part('year',buy_date) = _year AND date_part('month',buy_date) = _month;

        SELECT SUM(fees) INTO _registration_via_credit FROM (Course_offerings NATURAL JOIN Registers) CR
        WHERE date_part('year',reg_date) = _year AND date_part('month',reg_date) = _month AND NOT EXISTS (
            SELECT 1 FROM Redeems WHERE redeem_date = CR.reg_date AND card_number = CR.card_number 
            AND cust_id = CR.cust_id AND sid = CR.sid AND course_id = CR.course_id AND launch_date = CR.launch_date 
        );

        SELECT SUM(refund_amt) INTO _refunded_registration_fees FROM Cancels 
        WHERE date_part('year',cancel_date) = _year AND date_part('month',cancel_date) = _month;

        SELECT COUNT(*) INTO _num_redemptions FROM Redeems 
        WHERE date_part('year',redeem_date) = _year AND date_part('month',redeem_date) = _month;

        RETURN NEXT;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
                                                                             
-- 2
CREATE OR REPLACE PROCEDURE remove_employee(employee_id int, dep_date date)
AS $$
BEGIN
    IF EXISTS(SELECT 1 FROM Managers AS M WHERE M.eid = employee_id) THEN
        IF EXISTS(SELECT 1 FROM Course_areas AS CA WHERE CA.eid = employee_id) THEN
            RAISE EXCEPTION 'No departure of Manager managing a course area is allowed.';
        END IF;
    ELSIF EXISTS(SELECT 1 FROM Administrators AS A WHERE A.eid = employee_id) THEN
        IF EXISTS(SELECT 1 FROM Course_offerings AS CO WHERE CO.eid = eid AND CO.registration_deadline > dep_date) THEN
            RAISE EXCEPTION 'No departure of Administrator before a course registration closes is allowed.';
        END IF;
    ELSIF EXISTS(SELECT 1 FROM INSTRUCTORS AS I WHERE I.eid = employee_id) THEN
        IF EXISTS(SELECT 1 FROM Sessions AS S WHERE S.eid = employee_id AND S.start_date > dep_date) THEN
            RAISE EXCEPTION 'No departure of Instructor after a session has started is allowed.';
        END IF;
    END IF;

    --update departure date
    UPDATE Employees
    SET depart_date = dep_date
    WHERE eid = employee_id;

    COMMIT;
END;
$$ LANGUAGE plpgsql;

-- 10
CREATE TYPE information_session AS (session_date date, start_hour time, room_id int);

CREATE OR REPLACE PROCEDURE add_course_offering(course_id_in int, launch_date_in date,
fees numeric, deadline date, target_num int, admin_id int, VARIADIC sessions information_session[])
AS $$
DECLARE
    end_time_derv time;
    _seating_capacity int;
    room_id int;
    all_instructors boolean := TRUE;
    earliest_session information_session := $7[0];
    latest_session information_session := $7[0];
    current_session_number int := 1;
    duration int := (SELECT duration FROM Courses AS C WHERE C.course_id = course_id_in);
    course_area text := (SELECT name FROM Courses AS C WHERE C.course_id = course_id_in);
    mid int := (SELECT eid FROM Course_areas WHERE name = course_area);
    possible_instructor int;
    new_session information_session;
    start_time_derv time;

BEGIN

    IF EXISTS (SELECT 1 FROM Course_offerings AS CO WHERE CO.launch_date = launch_date_in AND CO.course_id = course_id_in) THEN
        RAISE EXCEPTION 'Same course has a course offering on the same launch date.';
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
        IF (EXTRACT(dow FROM new_session.session_date::timestamp) = 6 OR EXTRACT(dow FROM new_session.session_date::timestamp) = 0) THEN
            ROLLBACK;
            RAISE EXCEPTION 'No session should be held on weekends.';
            RETURN;
        END IF;

        start_time_derv := make_time(new_session.start_hour,0,0);
        end_time_derv := make_time(new_session.start_hour + duration,0,0);
        room_id := new_session.room_id;
        _seating_capacity := _seating_capacity + (SELECT seating_capacity FROM Rooms WHERE rid = room_id);
        -- check if room currently has a clashing class
        IF EXISTS(SELECT 1 FROM Sessions AS S WHERE S.session_date = new_session.session_date AND S.rid = room_id AND
        (S.start_time < start_time_derv OR S.end_time > end_time_derv)) THEN
            ROLLBACK;
            RAISE EXCEPTION 'The room will be use for other classes during this session.';
            RETURN;
        END IF;

        --check if session is valid
        IF (((start_time_derv >= make_time(9,0,0) and start_time_derv < make_time(12,0,0)) or (start_time_derv >= make_time(14,0,0) and start_time_derv < make_time(18,0,0))) AND (end_time_derv <= make_time(18,0,0) OR (end_time_derv <= make_time(12,0,0) AND end_time_derv >= make_time(14,0,0)))) THEN

            --check if there is session from same course offering with the same day and time
            IF EXISTS (SELECT 1 FROM Sessions AS S WHERE S.course_id = course_id_in AND S.launch_date = launch_date_in AND S.start_time = new_session.start_time) THEN
                ROLLBACK;
                RAISE EXCEPTION 'There is 2 sessions in the same day and time.';
                RETURN;
            END IF;

            --valid session, check if there is an instructor available to teach this session
            SELECT eid INTO possible_instructor FROM (SELECT find_instructors(course_id_in, new_session.session_date, new_session.start_hour)) AS X LIMIT 1;

            -- no full-time or part-time instructor is free
            IF (possible_instructor IS NULL) THEN
                all_instructors := FALSE;
                ROLLBACK;
                RAISE EXCEPTION 'There is a session without any available instructor.';
                RETURN;
            END IF;
        END IF;

        --insert this session into Sessions table
        INSERT INTO Sessions(sid, session_date, start_time, end_time, rid, eid, launch_date, course_id)
        VALUES (current_session_number, new_session.session_date, start_time_derv, end_time_derv, room_id, possible_instructor, launch_date_in, course_id_in);

    END LOOP;

    --valid course offering with deadline at least 10 days from earliest session
    IF (deadline - earliest_session.session_date < 10) THEN
        ROLLBACK;
        RAISE EXCEPTION 'Deadline for course offering is less than 10 days from earliest session.';
        RETURN;
    END IF;

    IF (all_instructors) THEN
        INSERT INTO Course_offerings(launch_date, start_date, end_date, registration_deadline, target_number_registrations, seating_capacity, fees, eid, mid)
        VALUES (launch_date_in, earliest_session.session_date, latest_session.session_date, deadline, target_num, seating_capacity, fees, eid, mid);
    END IF;
    COMMIT;

END;
$$ LANGUAGE plpgsql;

--14
--might need to check if the json format is agreeable with all of you, currently: {all the info}, {session 1 info}, {session 2 info}
CREATE OR REPLACE FUNCTION get_my_course_package(cust_id_in int)
RETURNS json AS $$
DECLARE
    active_package_id int;
    package_name text;
    purchase_date date;
    cust_card_num int;
    latest_session_date date;
    price_of_package numeric;
    number_free_sessions int;
    number_remaining int := 0;
    package_info_without_sessions JSONB;
    sessions_info JSONB;
    final JSONB;
BEGIN

    IF NOT EXISTS (SELECT 1 FROM Buys AS B WHERE B.cust_id = cust_id_in AND num_remaining_redemptions >= 1) THEN
        SELECT package_id, buy_date, card_number INTO active_package_id, purchase_date, cust_card_num FROM Buys B WHERE B.cust_id = cust_id_in ORDER BY buy_date DESC LIMIT 1;

        --check if the last redeemed session could still be cancelled
        SELECT session_date INTO latest_session_date FROM (Redeems NATURAL JOIN Sessions) AS X WHERE X.cust_id = cust_id_in ORDER BY redeem_date DESC LIMIT 1;
        IF (EXTRACT(DATE FROM NOW()) > EXTRACT(DATE FROM latest_session_date)) THEN
            RAISE EXCEPTION 'You do not have any active or partially active course package.';
        END IF;
    ELSE
        SELECT package_id, buy_date, num_remaining_redemptions INTO active_package_id, purchase_date, number_remaining FROM Buys B WHERE B.cust_id = cust_id_in AND B.num_remaining_redemptions >= 1;
    END IF;

    SELECT name, price, num_free_registrations INTO package_name, price_of_package, number_free_sessions FROM Course_packages WHERE package_id = active_package_id;

    package_info_without_sessions := (select jsonb_build_object('package_name', package_name, 'purchase_date', purchase_date, 'price_of_package', price_of_package,
     'number_of_free_sessions', number_free_sessions, 'number_of_sessions_not_redeemed', number_remaining));

    WITH filter_redeems AS (
        SELECT * FROM Redeems WHERE buy_date = purchase_date AND package_id = active_package_id AND cust_id = cust_id_in
    ), redeems_sessions AS(
        SELECT * FROM (filter_redeems NATURAL JOIN Sessions)
    ), pre_json AS (
        select sid, name, session_date, start_time FROM (redeems_sessions natural join Courses)
    ), final_json AS (SELECT json_agg(
        jsonb_build_object('redeemed_course_name', name, 'redeemed_session_date', session_date, 'redeemed_start_time', start_time)
        )
      FROM pre_json
    ) SELECT json_agg(row_to_json(t))::jsonb INTO sessions_info FROM final_json;

    final := (select package_info_without_sessions || sessions_info);
    RETURN final::json;
END;
$$ LANGUAGE plpgsql;

--19
CREATE OR REPLACE PROCEDURE update_course_session(cust_id_in int, course_id_in int, launch_date_in date, session_id int)
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
    IF (new_session_course_id = session_id AND new_session_launch_date = launch_date_in) THEN
        seating_limit := (SELECT seating_capacity FROM Rooms WHERE rid = room_id);
        total_count := total_count + (SELECT count(*) FROM Registers WHERE sid = session_id);
        total_count := total_count + (SELECT count(*) FROM Redeems WHERE sid = session_id);
        IF (total_count <= seating_limit) THEN
            IF EXISTS(SELECT * FROM Registers AS R WHERE R.cust_id = cust_id_in AND R.course_id = course_id_in AND R.launch_date = launch_date_in) THEN
                UPDATE Registers as R
                SET R.sid = session_id
                WHERE R.course_id = course_id_in AND R.launch_date = launch_date_in AND R.cust_id = cust_id_in;
            ELSIF EXISTS(SELECT * FROM Redeems AS Re WHERE Re.cust_id = cust_id_in AND Re.course_id = course_id_in AND Re.launch_date = launch_date_in) THEN
                UPDATE Redeems as Re
                SET Re.sid = session_id
                WHERE Re.course_id = course_id_in AND Re.launch_date = launch_date_in AND Re.cust_id = cust_id_in;
            END IF;
        END IF;
    END IF;
    COMMIT;
END;
$$ LANGUAGE plpgsql;

--20
--check: package_credit refers to the current amount of credit in active package, or is it the credit refunded (1 or 0).
-- check: whether we should remove from registers and redeems, using check of launch_date and course_id and cust_id
CREATE OR REPLACE PROCEDURE cancel_registration(cust_id_in int, course_id_in int, launch_date_in date)
AS $$
DECLARE
    current_date date := (SELECT NOW()::date);
    start_session date;
    refund_amt numeric := 0.00;
    course_amount numeric  := (SELECT fees FROM Course_offerings AS CO WHERE CO.course_id = course_id_in AND CO.launch_date = launch_date_in);
    package_credit int := 0;
    session_id int := 0;
BEGIN
    SELECT session_date, sid INTO start_session, session_id
    FROM Sessions
    WHERE R.course_id = course_id_in AND R.launch_date = launch_date_in AND R.cust_id = cust_id_in;

    IF EXISTS(SELECT * FROM Registers AS R WHERE R.cust_id = cust_id_in AND R.course_id = course_id_in AND R.launch_date = launch_date_in) THEN
        IF (start_session - current_date >= 7) THEN
            refund_amt := course_amount * 0.9;
            --remove from registers table
            DELETE FROM Registers AS R WHERE (R.cust_id = cust_id_in AND R.launch_date = launch_date_in AND R.course_id = course_id_in);
            --insert into cancels table
            INSERT INTO Cancels VALUES (current_date, refund_amt, package_credit, cust_id_in, session_id, course_id_in, launch_date_in);
            COMMIT;
        ELSIF (start_session - current_date >= 0 and start_session - current_date < 7) THEN
            DELETE FROM Registers AS R WHERE (R.cust_id = cust_id_in AND R.launch_date = launch_date_in AND R.course_id = course_id_in);
            INSERT INTO Cancels VALUES (current_date, refund_amt, package_credit, cust_id_in, session_id, course_id_in, launch_date_in);
            COMMIT;
        ELSE:
            RAISE EXCEPTION 'The session you are trying to cancel has ended already.';
        END IF;
    ELSIF EXISTS(SELECT * FROM Redeems AS Re WHERE Re.cust_id = cust_id_in AND Re.course_id = course_id_in AND Re.launch_date = launch_date_in) THEN
        IF (start_session - current_date >= 7) THEN
            package_credit := 1;
            --add one credit to current active package
            UPDATE Buys AS B
            SET num_remaining_redemptions = num_remaining_redemptions + 1
            WHERE B.cust_id = cust_id_in AND (num_remaining_redemptions > 0 OR current_date - B.buy_date <= 7);

            --remove entry from Redeem table
            DELETE FROM Redeems AS R WHERE (R.cust_id = cust_id_in AND R.launch_date = launch_date_in AND R.course_id = course_id_in);
            --insert into cancels table
            INSERT INTO Cancels VALUES (current_date, refund_amt, package_credit, cust_id_in, session_id, course_id_in, launch_date_in);
            COMMIT;
        ELSIF (start_session - current_date >= 0 and start_session - current_date < 7) THEN
            DELETE FROM Redeems AS R WHERE (R.cust_id = cust_id_in AND R.launch_date = launch_date_in AND R.course_id = course_id_in);
            INSERT INTO Cancels VALUES (current_date, refund_amt, package_credit, cust_id_in, session_id, course_id_in, launch_date_in);
            COMMIT;
        ELSE
            RAISE EXCEPTION 'The session you are trying to cancel has ended already.';
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;

--21
--whether a course has started defined based on day, will that be ok, or should I take into account of time?, might also want to refactor the code as it looks a bit bad
CREATE OR REPLACE PROCEDURE update_instructor(session_id int, course_id_in int, launch_date_in date, new_instructor_id int)
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
                closest_end_session_new_instructor := (SELECT end_time FROM Sessions WHERE sid = session_id AND end_time < session_start_time ORDER BY end_time DESC LIMIT 1);
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
                    closest_end_session_new_instructor := (SELECT end_time FROM Sessions WHERE sid = session_id AND end_time < session_start_time ORDER BY end_time DESC LIMIT 1);
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

-- 25
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

--26

--modify get_available_course_offerings_slightly
CREATE OR REPLACE FUNCTION get_available_course_offerings_with_id_and_launch_date()
RETURNS TABLE(_course_id INT, _launch_date DATE, _course_title TEXT, _course_area TEXT, _deadline DATE,
              _course_fees NUMERIC) AS $$
DECLARE
    _number_registrations INT;
    _row RECORD;
BEGIN
    for _row in select course_id, launch_date, title, name, start_date, end_date, registration_deadline, fees, seating_capacity
    FROM Courses NATURAL JOIN Course_offerings
    WHERE registration_deadline >= CURRENT_DATE
    ORDER BY registration_deadline
    LOOP
        SELECT COUNT(*) INTO _number_registrations FROM Registers
        WHERE course_id = _row.course_id and launch_date = _row.launch_date;
        IF _number_registrations < _row.seating_capacity
        THEN
            _course_id := _row.id;
            _launch_date := _row.launch_date;
            _course_title := _row.title;
            _course_area := _row.name;
            _deadline := _row.registration_deadline;
            _course_fees := _row._course_fees;
            RETURN NEXT;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

--helper function to generate table
CREATE OR REPLACE FUNCTION get_last_three_areas(_cust_id int)
RETURNS TABLE(_course_area text) AS $$
DECLARE
    _number_registrations INT;
    _row RECORD;
BEGIN
RETURN QUERY
    WITH merge_registers_redeems AS (
        SELECT cust_id, course_id, reg_date AS sign_up_date FROM Registers
        UNION
        SELECT cust_id, course_id, redeem_date FROM Redeems
    ) SELECT name
        FROM (merge_registers_redeems NATURAL JOIN Courses) AS X
        WHERE cust_id = _cust_id ORDER BY sign_up_date DESC LIMIT 3;

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION promote_courses()
RETURNS TABLE (customer_id int, customer_name text, course_area_A text,
course_identifier_C int, course_title_C text, launch_date_offering_C date,
course_offering_deadline date, fees_course_offering date) AS $$
DECLARE
    curs CURSOR FOR (SELECT cust_id, name FROM Customers ORDER BY cust_id);
    all_offering_curs CURSOR FOR (SELECT get_available_course_offerings_with_id_and_launch_date());
    r RECORD;
    courses_record RECORD;
    last_purchase RECORD;
    last_register DATE;
    customer_name text;
    customer_id int;
    _rows RECORD;
BEGIN
    OPEN curs;
    LOOP
        FETCH curs INTO r;
        EXIT WHEN NOT FOUND;
        customer_name := r.name;
        customer_id := r.id;

        -- get last register/redeem session
        WITH merge_registers_redeems AS (
        SELECT cust_id, reg_date AS sign_up_date FROM Registers
        UNION
        SELECT cust_id, redeem_date FROM Redeems
        ) SELECT sign_up_date INTO last_register FROM merge_registers_redeems WHERE cust_id = r.cust_id ORDER BY sign_up_date DESC LIMIT 1;

        IF (last_register IS NULL) THEN
            OPEN all_offering_curs;
            LOOP
                FETCH all_offering_curs INTO courses_record;
                EXIT WHEN NOT FOUND;
                course_area_A := all_offering_curs._course_area;
                course_identifier_C := all_offering_curs._course_id;
                course_title_C := all_offering_curs._course_title;
                launch_date_offering_C := all_offering_curs._launch_date;
                course_offering_deadline := all_offering_curs._deadline;
                fees_course_offering := all_offering_curs._course_fees;
                RETURN NEXT;
            END LOOP;
            CLOSE all_offering_curs;
        ELSIF ((DATE_PART('YEAR', NOW()::date) - DATE_PART('YEAR', last_purchase.redeem_date::date)) * 12 +
            (DATE_PART('MONTH', NOW()::date) - DATE_PART('MONTH', last_purchase.redeem_date::date)) >= 6) THEN

            --if less than 6 months and registered for a course before, find areas of last 3 sign-ups
            
            for _rows in select *
            FROM get_available_course_offerings_with_id_and_launch_date() NATURAL JOIN get_last_three_areas(customer_id) AS Z
            LOOP 
                course_identifier_C := _row.id;
                launch_date_offering_C := _row.launch_date;
                course_title_C := _row.title;
                course_area_A := _row.name;
                course_offering_deadline := _row.registration_deadline;
                fees_course_offering := _row._course_fees;
                RETURN NEXT;
            END LOOP;
        END IF;
        CONTINUE;
    END LOOP;
    CLOSE curs;
END;
$$ LANGUAGE plpgsql;

-- 27
CREATE OR REPLACE FUNCTION top_packages(N int)
RETURNS TABLE (package_identifier int, free_sessions int, price numeric, start_date date, end_date date, num_sold int) AS $$
DECLARE
    curs CURSOR FOR (SELECT retrieve_top_packages(N));
    r RECORD;
    current_package_id int;
BEGIN

    OPEN curs;
        LOOP
            FETCH curs INTO r;
            EXIT WHEN NOT FOUND;
            current_package_id := curs.package_id;
            package_identifier := current_package_id;
            num_sold := curs.total;
            free_sessions := (SELECT num_free_registrations FROM Course_packages WHERE package_id = current_package_id);
            price := (SELECT price FROM Course_packages WHERE package_id = current_package_id);
            start_date := (SELECT sale_start_date FROM Course_packages WHERE package_id = current_package_id);
            end_date := (SELECT sale_end_date FROM Course_packages WHERE package_id = current_package_id);
            RETURN NEXT;
        END LOOP;
    CLOSE curs;
END;
$$ LANGUAGE plpgsql;

-- 1, 4, 8, 11, 12, 16, 18, 23, 24, 30

-- 1
CREATE OR REPLACE PROCEDURE add_employee(IN em_name TEXT, IN em_address TEXT,
IN em_phone TEXT, IN em_email TEXT, IN join_date date, IN salary_type TEXT,
IN rate INT, IN employee_type TEXT, IN em_areas text[]) AS $$

DECLARE
    employee_id INT;
    area text;

BEGIN
    SELECT case
        when max(eid) is null then 0
        else max(eid)
        end into employee_id FROM Employees;
    
    employee_id := employee_id + 1;

    INSERT INTO Employees
    VALUES (employee_id, em_name, em_phone, em_address, em_email, null, join_date);

    IF salary_type = 'full_time' THEN
        INSERT INTO Full_time_Emp
        VALUES (rate, employee_id);
    
    elseif salary_type = 'part_time' THEN
        INSERT INTO Part_time_Emp
        VALUES (rate, employee_id);
    
    END IF;

    IF employee_type = 'Administrator' THEN 
        INSERT INTO Administrators
        VALUES (employee_id);

    elseif employee_type = 'Manager' THEN
        INSERT INTO Managers
        VALUES (employee_id);

        /* note: didn't check if key constraint violated */
        FOREACH area IN ARRAY em_areas
        LOOP
            INSERT INTO Course_areas
            VALUES (area, employee_id);
        END LOOP;
    
    elseif employee_type = 'Instructor' THEN
        INSERT INTO Instructors
        VALUES (employee_id);

        IF salary_type = 'full_time' THEN
            INSERT INTO Full_time_Instructors
            VALUES (employee_id);
        
        elseif salary_type = 'part_time' THEN
            INSERT INTO Part_time_Instructors
            VALUES (employee_id);
        
        END IF;

        FOREACH area IN ARRAY em_areas
        LOOP
            INSERT INTO Specializes
            VALUES (employee_id, area);
        END LOOP;
    
    END IF;
END;
$$ LANGUAGE plpgsql;

-- 4
create or replace procedure update_credit_card(in customer_id int, in c_number bigint,
in ex_date date, in c_cvv int) as $$

BEGIN
    INSERT INTO Credit_cards
    VALUES (c_number, c_cvv, ex_date);

    INSERT INTO Owns
    VALUES (c_number, customer_id, current_date);
END;
$$ LANGUAGE plpgsql;


-- 8
/* session duration's type is 'interval'. */
/* Exclude all rooms on that date that are occupied during the given session's 
time interval. */
create or replace function find_rooms(in s_date date, in s_hour time, in s_duration interval)
returns table(rid int) as $$

BEGIN
    SELECT rid FROM Rooms
    EXCEPT
    SELECT rid FROM Sessions
    WHERE session_date = s_date
    AND ((end_time <= s_hour + s_duration AND end_time >= s_hour)
        OR (start_time >= s_hour AND start_time <= s_hour + s_duration)
	OR (start_time <= s_hour AND end_time >= s_hour + s_duration));

END;
$$ LANGUAGE plpgsql;


-- 11
create or replace procedure add_course_package(in p_name text, in n_free int, 
in s_date date, in e_date date, in c_price numeric) as $$
DECLARE
    cid INT;

BEGIN
    SELECT case
        when max(package_id) is null then 0
        else max(package_id)
        end into cid FROM Course_packages;
    
    cid := cid + 1;

    INSERT INTO Course_packages
    VALUES (cid, s_date, e_date, n_free, p_name, c_price);

END;
$$ LANGUAGE plpgsql;

-- 12
create or replace function get_available_course_packages()
returns table(name text, num_free_registrations int, sale_end_date date, price numeric) as $$

BEGIN
    SELECT name, num_free_registrations, sale_end_date, price
    FROM Course_packages
    WHERE sale_end_date >= current_date;

END;
$$ LANGUAGE plpgsql;

-- 16
create or replace function get_available_course_sessions(in l_date date, in cid int)
returns table(session_date date, start_time time, instructor text, num_remaining_seats int) as $$
DECLARE
    s_capacity int;

BEGIN
    SELECT seating_capacity INTO s_capacity FROM Course_offerings
    WHERE l_date = launch_date AND cid = course_id;

    SELECT session_date, start_time, name as instructor, 
    s_capacity - count(distinct cust_id) as num_remaining_seats
    FROM (Sessions natural join (SELECT eid, name FROM Employees) as foo1)
        natural join (SELECT cust_id, sid FROM Registers) as foo2
    WHERE l_date = launch_date AND cid = course_id
    GROUP BY session_date, start_time, name
    ORDER BY (session_date, start_time) asc;
END;
$$ LANGUAGE plpgsql;

-- 18
create or replace function get_my_registrations(in cid int)
returns table(course_name text, course_fee numeric, session_date date,
start_time time, session_duration interval, instructor text) as $$

BEGIN
    WITH r1 AS (SELECT cust_id, sid, course_id, launch_date FROM Registers),
    co1 AS (SELECT course_id, launch_date, fees FROM Course_offerings),
    c1 AS (SELECT course_id, name as cname FROM Courses),
    s1 AS (SELECT sid, session_date, start_time, end_time, eid, launch_date, course_id FROM Sessions),
    e1 AS (SELECT eid, name as ename FROM Employees)
    SELECT cname, fees, session_date, start_time, 
    end_time - start_time as session_duration, ename
    FROM r1 natural join
    (co1 natural join c1) natural join
    (s1 natural join e1)
    WHERE cust_id = cid
    ORDER BY session_date, start_time asc;
END;
$$ LANGUAGE plpgsql;


--23
create or replace procedure remove_session(in l_date date, in cid int, in session_id int) as $$

DECLARE
    num_registrations int;
    session_start_date date;

BEGIN
    SELECT count(*) INTO num_registrations FROM Registers
    WHERE sid = session_id AND course_id = cid AND launch_date = l_date;

    SELECT session_date INTO session_start_date FROM Sessions
    WHERE sid = session_id AND course_id = cid AND launch_date = l_date;

    if num_registrations > 0 then 
        raise exception 'Session cannot be removed. Number of registrations more than 0.';

    elseif session_start_date <= current_date then
        raise exception 'Session cannot be removed. Session has already started.';

    end if;

    DELETE FROM Sessions
    WHERE sid = session_id AND course_id = cid AND launch_date = l_date;

END;
$$ LANGUAGE plpgsql;

--24
/* note: new_session_duration not specified in problem statement. */
create or replace procedure add_session(in l_date date, in cid int, in new_session_id int,
in new_session_day date, in new_session_start_hour time, in new_session_duration interval,
in instructor_id int, in room_id int) as $$

DECLARE
    deadline date;
    count_rid int;
    count_eid int;
    new_sid int;

BEGIN 
    SELECT registration_deadline INTO deadline 
    FROM Course_offerings WHERE launch_date = l_date AND course_id = cid;

    SELECT count(rid) into count_rid
    FROM find_rooms(new_session_day, new_session_start_hour, new_session_duration)
    WHERE rid = room_id;

    SELECT count(eid) into count_eid
    FROM find_instructors(cid, new_session_day, new_session_start_hour)
    WHERE eid = instructor_id;

    if deadline < current_date then
        raise exception 'Course offering deadline has passed.';

    elseif count_rid <= 0 then
        raise exception 'Room is occupied.';

    elseif count_eid <= 0 then
        raise exception 'Instructor is busy.';

    end if;

    SELECT case
        when max(sid) is null then 0
        else max(sid)
        end into new_sid
    FROM Sessions
    WHERE launch_date = l_date AND course_id = cid;

    new_sid := new_sid + 1;

    INSERT INTO Sessions
    VALUES (new_sid, new_session_day, new_session_start_hour,
    new_session_start_hour + new_session_duration, room_id, instructor_id,
    l_date, cid);

END;
$$ LANGUAGE plpgsql;

--30
create or replace function view_manager_report()
returns table(manager_name text, num_course_areas int, num_course_offerings int,
total_registration_fees numeric, best_selling_course_offering text) as $$
    
BEGIN 
    WITH course_offerings_and_fees AS (
    SELECT co1.launch_date as launch_date, co1.course_id as course_id,
    co1.mid as eid, (count(*) * co1.fees) as registration_fees 
    FROM Course_offerings as co1, Sessions as s1, Registers as r1
    WHERE co1.launch_date = s1.launch_date AND co1.course_id = s1.course_id
    AND r1.launch_date = co1.launch_date AND r1.course_id = co1.course_id
    AND r1.sid = s1.sid 
    AND extract(year from co1.end_date) = extract(year from current_date)
    GROUP BY co1.launch_date, co1.course_id, co1.mid), 

    course_offerings_and_redemptions AS (
    SELECT co1.launch_date as launch_date, co1.course_id as course_id,
    co1.mid as eid, (count(*) * r1.p1) as redemption_fees 
    FROM Course_offerings as co1, Sessions as s1, (Redeems natural join 
    (SELECT package_id, round(price/num_free_registrations) as p1 FROM Course_packages) as cp1) as r1
    WHERE co1.launch_date = s1.launch_date AND co1.course_id = s1.course_id
    AND r1.launch_date = co1.launch_date AND r1.course_id = co1.course_id
    AND r1.sid = s1.sid
    AND extract(year from co1.end_date) = extract(year from current_date)
    GROUP BY co1.launch_date, co1.course_id, co1.mid),

    course_offerings_and_total_fees AS (
    SELECT launch_date, course_id, eid, (redemption_fees + registration_fees) as total_fees
    FROM course_offerings_and_fees natural join course_offerings_and_redemptions),

    manager_and_best_selling AS (
    SELECT co1.eid, co1.title
    FROM (course_offerings_and_total_fees
    natural join (SELECT course_id, title FROM Courses) as c1) as co1
    WHERE co1.total_fees >= (SELECT max(total_fees)
    FROM course_offerings_and_total_fees co2
    WHERE co1.eid = co2.eid))

    SELECT m_name, count(a_name), count(launch_date, course_id), sum(total_fees), title
    FROM ((((Managers natural join (SELECT name as m_name, eid FROM Employees) as e1) 
    natural left join (SELECT name as a_name, eid FROM course_areas) as ca1))
    natural left join course_offerings_and_total_fees) 
    natural left join manager_and_best_selling
    GROUP BY eid, m_name
    ORDER BY m_name asc;
END;
$$ LANGUAGE plpgsql;

--7
CREATE OR REPLACE FUNCTION get_available_instructors(cid int, start_date date, end_date date)
RETURNS TABLE(eid int, name text, num_hours int, day date, available_hours time []) AS $$
DECLARE
	curs CURSOR FOR (
	(select S2.eid, I1.name
	from Specializes S2, Courses C1, Instructors I1, Employees E1
	where I1.eid = S2.eid
	and I1.eid = S1.eid
	and S2.name = C1.name
	and C1.course_id = cid
	and E1.depart_date IS NULL
	EXCEPT
	select eid, name
	from (Part_time_Instructors natural join Instructors) PI
	where (
		select sum(DATE_PART('hour', end_time - start_time))
		from Sessions
		where eid = PI.eid
		and course_id = cid
		and session_date >= start_date
		and session_date <= end_date
		and extract(month from session_date) = extract(month from start_date)
		and extract(year from session_date) = extract(year from start_date)
	) >= 30
	)order by eid asc);
	r RECORD;
	start_day date;
	start_hour time;

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
				and extract(month from S1.session_date) = extract(month from start_date)
				and extract(year from S1.session_date) = extract(year from start_date);
				start_day := start_date;
			
				while start_day <= end_date
				LOOP

					IF extract(dow from start_day) = 6 THEN
						start_day := start_day + '2 days'::interval;
						CONTINUE;
					END IF;

					IF extract(dow from start_day) = 0 THEN
						start_day := start_day + '1 day'::interval;
						CONTINUE;
					END IF;

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
	END LOOP;
	CLOSE curs;
END;
$$ LANGUAGE plpgsql;
                                                                             
