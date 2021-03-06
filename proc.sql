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
    SELECT make_interval(hours := duration) INTO _duration FROM Courses WHERE course_id = _course_id;
    _end_time := _start_time + _duration;

    RETURN QUERY
    WITH Filtered_Instructors AS (
        SELECT I.eid FROM Instructors I, Specializes S,  (Course_areas NATURAL JOIN Courses) AS Y
        WHERE S.name = Y.name AND S.eid = I.eid AND
        -- Find all instructors with matching speciality 
        Y.course_id = _course_id 
        EXCEPT
        -- part timers that are not eligible
        SELECT P.eid FROM Part_time_Instructors P NATURAL JOIN Sessions WHERE (
            SELECT SUM(end_time - start_time) FROM Sessions AS S WHERE S.eid = P.eid
        ) > make_interval(hours := 30) - _duration
        EXCEPT
        -- Past employees
        SELECT E.eid FROM Employees AS E WHERE depart_date IS NOT NULL
        EXCEPT
        -- check that does not clash with existing sessions that is taught
        SELECT S1.eid FROM Sessions AS S1 WHERE session_date = _session_date AND (
            _start_time - make_interval(hours := 1) >= start_time AND _start_time - make_interval(hours := 1) <= end_time
            OR
            _end_time + make_interval(hours := 1) >= start_time AND _end_time + make_interval(hours := 1) <= end_time
            OR
            _start_time <= start_time AND _end_time >= end_time
        )
    )
    SELECT Z.eid, Z.name FROM (Filtered_Instructors NATURAL JOIN Employees) AS Z;
    
END;
$$ LANGUAGE plpgsql;

-- 9
-- will only return hours, days where it is allowed to host a session.
CREATE OR REPLACE FUNCTION get_available_rooms (_start_date DATE, _end_date DATE)
RETURNS TABLE(_room_id INT, _room_capacity INT, _day DATE, _available_hours INT[]) AS $$
DECLARE
    _counter DATE;
    _row RECORD;
    _hour INT;
BEGIN
    IF _start_date IS NULL OR _end_date IS NULL OR _end_date < _start_date THEN
        RAISE EXCEPTION 'Invalid arguments!';
    END IF;

    for _row in select rid, seating_capacity FROM Rooms ORDER BY rid
    loop
        _counter := _start_date;
        _room_id := _row.rid;
        _room_capacity := _row.seating_capacity;
        WHILE _counter <= _end_date LOOP
            IF extract(dow from _counter) = 0 OR extract(dow from _counter) = 6 THEN
				_counter := _counter + make_interval(days := 1);
                CONTINUE;
            END IF;

            _available_hours := '{}';

            for _hour in 9..11 loop
                if NOT _hour <@ ANY(
                    SELECT int4range(extract(hour from start_time)::int,extract(hour from end_time)::int) 
                    FROM Sessions WHERE rid = _room_id and session_date = _counter
                ) THEN
                    _available_hours := _available_hours || _hour;
                END IF;
            end loop;

            for _hour in 14..17 loop
                if NOT _hour <@ ANY(
                    SELECT int4range(extract(hour from start_time)::int,extract(hour from end_time)::int) 
                    FROM Sessions WHERE rid = _room_id and session_date = _counter
                ) THEN
                    _available_hours := _available_hours || _hour;
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
    _number_redemptions INT;
    _row RECORD;
BEGIN
    for _row in select course_id, launch_date, title, name, start_date, end_date, registration_deadline, fees, seating_capacity
    FROM Courses NATURAL JOIN Course_offerings 
    WHERE registration_deadline >= CURRENT_DATE
    ORDER BY registration_deadline, title
    LOOP
        SELECT COUNT(*) INTO _number_registrations FROM Registers 
        WHERE course_id = _row.course_id and launch_date = _row.launch_date;
        SELECT COUNT(*) INTO _number_redemptions FROM Redeems
        WHERE course_id = _row.course_id and launch_date = _row.launch_date;
        IF _number_registrations + _number_redemptions < _row.seating_capacity 
        THEN
            _course_title := _row.title;
            _course_area := _row.name;
            _start_date := _row.start_date;
            _end_date := _row.end_date;
            _deadline := _row.registration_deadline;
            _course_fees := _row.fees;
            _num_remaining_seats := _row.seating_capacity - _number_registrations - _number_redemptions;
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
    _card_number bigint;
BEGIN
    IF _customer_id IS NULL OR _course_id IS NULL OR _launch_date IS NULL OR _session_number IS NULL OR _use_package IS NULL THEN
        RAISE EXCEPTION 'All arguments cannot be null!';
    END IF;

    IF _session_number NOT IN (
        SELECT sid FROM Sessions as S, Course_offerings as C
        WHERE C.course_id = S.course_id AND C.launch_date = S.launch_date 
        AND C.launch_date = _launch_date AND C.course_id = _course_id
    ) THEN 
		RAISE EXCEPTION 'The session is invalid!';
	END IF;

    IF _session_number NOT IN (
        SELECT sid FROM Sessions as S, Course_offerings as C
        WHERE C.course_id = S.course_id AND C.launch_date = S.launch_date 
        AND C.launch_date = _launch_date AND C.course_id = _course_id AND C.registration_deadline > CURRENT_DATE
    ) THEN 
		RAISE EXCEPTION 'The registration has closed!';
	END IF;
    
    IF _customer_id NOT IN (SELECT cust_id FROM Customers) THEN
        RAISE EXCEPTION 'The customer is invalid!';
    END IF;

    IF (
        SELECT COUNT(*) FROM Registers 
        WHERE course_id = _course_id and launch_date = _launch_date AND sid = _session_number
    ) + (
        SELECT COUNT(*) FROM Redeems
        WHERE course_id = _course_id and launch_date = _launch_date AND sid = _session_number
    ) >= (
        SELECT seating_capacity FROM Rooms NATURAL JOIN Sessions 
        WHERE course_id = _course_id and launch_date = _launch_date AND sid = _session_number
    ) THEN
        RAISE EXCEPTION 'The session is full!';
    END IF;        

    IF EXISTS (SELECT 1 FROM Registers WHERE cust_id = _customer_id AND course_id = _course_id AND launch_date = _launch_date ) 
    OR EXISTS (SELECT 1 FROM Redeems WHERE cust_id = _customer_id AND course_id = _course_id AND launch_date = _launch_date ) THEN
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
    _session_date DATE;
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
        +
        (SELECT COUNT(*) FROM Redeems WHERE course_id = _course_id and launch_date = _launch_date AND sid = _session_number)
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
_curr_redemptions INT;
_curr_registers INT;
_last_amt INT;
_course RECORD;
_offering RECORD;
BEGIN
    FOR _course in SELECT * FROM Courses C ORDER BY (
        (
            SELECT COUNT(*) FROM Registers NATURAL JOIN Course_offerings WHERE course_id = C.course_id and launch_date = (
                SELECT launch_date FROM Course_offerings WHERE course_id = C.course_id and start_date = (
                    SELECT MAX(start_date) FROM Course_offerings WHERE course_id = C.course_id
                )
            )
        ) + (
            SELECT COUNT(*) FROM Redeems NATURAL JOIN Course_offerings WHERE course_id = C.course_id and launch_date = (
                SELECT launch_date FROM Course_offerings WHERE course_id = C.course_id and start_date = (
                    SELECT MAX(start_date) FROM Course_offerings WHERE course_id = C.course_id
                )
            )
        )
    ) DESC, course_id ASC
    LOOP
        IF (
            SELECT COUNT(launch_date) FROM Courses NATURAL JOIN Course_offerings
            WHERE course_id = _course.course_id AND date_part('year',start_date) = date_part('year',CURRENT_DATE)
        ) < 2 THEN
            CONTINUE;
        END IF;

        _last_amt := -1;
        _skip := false;

        FOR _offering in SELECT * FROM Course_offerings 
        WHERE course_id = _course.course_id AND date_part('year',start_date) = date_part('year',CURRENT_DATE) ORDER BY start_date
        LOOP
            SELECT COUNT(*) INTO _curr_registers FROM Registers WHERE course_id = _course.course_id AND launch_date = _offering.launch_date;
            SELECT COUNT(*) INTO _curr_redemptions FROM Redeems WHERE course_id = _course.course_id AND launch_date = _offering.launch_date;
            _curr_amt := _curr_redemptions + _curr_registers;
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
        
        SELECT COALESCE(SUM(amount),0) INTO _salary_paid FROM Pay_slips 
        WHERE date_part('year',payment_date) = _year AND date_part('month',payment_date) = _month;

        SELECT COALESCE(SUM(price),0) INTO _sales_course_packages FROM Buys NATURAL JOIN Course_packages
        WHERE date_part('year',buy_date) = _year AND date_part('month',buy_date) = _month;

        SELECT COALESCE(SUM(fees),0) INTO _registration_via_credit FROM (Course_offerings NATURAL JOIN Registers) CR
        WHERE date_part('year',reg_date) = _year AND date_part('month',reg_date) = _month;

        SELECT COALESCE(SUM(refund_amt),0) INTO _refunded_registration_fees FROM Cancels 
        WHERE date_part('year',cancel_date) = _year AND date_part('month',cancel_date) = _month;

        SELECT COALESCE(COUNT(*),0) INTO _num_redemptions FROM Redeems 
        WHERE date_part('year',redeem_date) = _year AND date_part('month',redeem_date) = _month;

        RETURN NEXT;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
                                                                             
-- 2
CREATE OR REPLACE PROCEDURE remove_employee(employee_id int, dep_date date)
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Employees WHERE eid = employee_id) THEN
        RAISE EXCEPTION 'Employee cannot be found.';
    END IF;
    IF (SELECT join_date FROM Employees WHERE eid = employee_id) >= dep_date THEN
        RAISE EXCEPTION 'The departure date has to be later than join date.';
    END IF;
    
    IF EXISTS(SELECT 1 FROM Managers AS M WHERE M.eid = employee_id) THEN
        IF EXISTS(SELECT 1 FROM Course_areas AS CA WHERE CA.eid = employee_id) THEN
            RAISE EXCEPTION 'No departure of Manager managing a course area is allowed.';
        END IF;
    ELSIF EXISTS(SELECT 1 FROM Administrators AS A WHERE A.eid = employee_id) THEN
        IF EXISTS(SELECT 1 FROM Course_offerings AS CO WHERE CO.eid = eid AND CO.registration_deadline > dep_date) THEN
            RAISE EXCEPTION 'No departure of Administrator before a course registration closes is allowed.';
        END IF;
    ELSIF EXISTS(SELECT 1 FROM INSTRUCTORS AS I WHERE I.eid = employee_id) THEN
        IF EXISTS(SELECT 1 FROM Sessions AS S WHERE S.eid = employee_id AND S.session_date > dep_date) THEN
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
CREATE TYPE information_session AS (session_date date, start_hour int, room_id int);

CREATE OR REPLACE PROCEDURE add_course_offering(course_id_in int, launch_date_in date,
fees numeric, deadline date, target_num int, admin_id int, VARIADIC sessions information_session[])
AS $$
DECLARE
    end_time_derv time;
    _seating_capacity int := 0;
    room_id int;
    all_instructors boolean := TRUE;
    current_session int := 1;
    earliest_session information_session;
    latest_session information_session;
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
        room_id := new_session.room_id;
        _seating_capacity := _seating_capacity + (SELECT seating_capacity FROM Rooms WHERE rid = room_id);
        IF (current_session = 1) THEN
            earliest_session := new_session;
            latest_session := new_session;
            current_session := current_session + 1;
            CONTINUE;
        END IF;

        -- find start date
        IF (new_session.session_date < earliest_session.session_date) THEN
            earliest_session := new_session;
        END IF;
        --find end date
        IF (new_session.session_date > latest_session.session_date) THEN
            latest_session := new_session;
        END IF;
    END LOOP;

    INSERT INTO Course_offerings(launch_date, start_date, end_date, registration_deadline, target_number_registrations, seating_capacity, fees, eid, mid, course_id)
    VALUES (launch_date_in, earliest_session.session_date, latest_session.session_date, deadline, target_num, _seating_capacity, fees, admin_id, mid, course_id_in);

    FOREACH new_session IN ARRAY $7
    LOOP
        room_id := new_session.room_id;
        --check if weekday
        IF (EXTRACT(dow FROM new_session.session_date::timestamp) = 6 OR EXTRACT(dow FROM new_session.session_date::timestamp) = 0) THEN
            ROLLBACK;
            RAISE EXCEPTION 'No session should be held on weekends.';
            RETURN;
        END IF;

        start_time_derv := make_time(new_session.start_hour,0,0);
        end_time_derv := make_time(new_session.start_hour + duration,0,0);
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
            IF EXISTS (SELECT 1 FROM Sessions AS S WHERE S.course_id = course_id_in AND S.launch_date = launch_date_in AND S.start_time = start_time_derv AND S.session_date = new_session.session_date) THEN
                ROLLBACK;
                RAISE EXCEPTION 'There is 2 sessions in the same day and time.';
                RETURN;
            END IF;
            --valid session, check if there is an instructor available to teach this session
            SELECT eid INTO possible_instructor FROM (SELECT * FROM find_instructors(course_id_in, new_session.session_date, new_session.start_hour)) AS X LIMIT 1;
            -- no full-time or part-time instructor is free
            IF (possible_instructor IS NULL) THEN
                all_instructors := FALSE;
                ROLLBACK;
                RAISE EXCEPTION 'There is a session without any available instructor.';
                RETURN;
            END IF;
        ELSE
            RAISE EXCEPTION 'Session time is not valid.';
        END IF;
        --insert this session into Sessions table
        INSERT INTO Sessions(sid, session_date, start_time, end_time, rid, eid, launch_date, course_id)
        VALUES (current_session_number, new_session.session_date, start_time_derv, end_time_derv, room_id, possible_instructor, launch_date_in, course_id_in);
        current_session_number := current_session_number + 1;
    END LOOP;

    --valid course offering with deadline at least 10 days from earliest session
    IF (earliest_session.session_date - deadline < 10) THEN
        ROLLBACK;
        RAISE EXCEPTION 'Deadline for course offering is less than 10 days from earliest session.';
        RETURN;
    END IF;
    COMMIT;

END;
$$ LANGUAGE plpgsql;

--14
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
        IF (latest_session_date IS NULL) THEN
            RAISE EXCEPTION 'You do not have any active or partially active course package.';
        ELSIF (CURRENT_DATE > latest_session_date) THEN
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
        ) AS Information_of_redeemed_sessions
      FROM pre_json
    ) SELECT jsonb_agg(js) into sessions_info FROM final_json JS;

    final := (select package_info_without_sessions || sessions_info);
    RETURN final::json;
END;
$$ LANGUAGE plpgsql;

--19
CREATE OR REPLACE PROCEDURE update_course_session(cust_id_in int, course_id_in int, launch_date_in date, session_id int)
AS $$
DECLARE
    total_count int;
    room_id int;
    seating_limit int;
BEGIN
    -- query for room of new session
    SELECT rid INTO  room_id
    FROM Sessions
    WHERE sid = session_id AND course_id = course_id_in AND launch_date = launch_date_in;
    --select query finds a valid session
    IF (room_id IS NOT NULL) THEN
        seating_limit := (SELECT seating_capacity FROM Rooms WHERE rid = room_id);
        total_count := total_count + (SELECT count(*) FROM Registers WHERE sid = session_id AND course_id = course_id_in AND launch_date = launch_date_in);
        total_count := total_count + (SELECT count(*) FROM Redeems WHERE sid = session_id AND course_id = course_id_in AND launch_date = launch_date_in);
        IF (total_count <= seating_limit OR total_count IS NULL) THEN
            IF EXISTS(SELECT * FROM Registers AS R WHERE R.cust_id = cust_id_in AND R.course_id = course_id_in AND R.launch_date = launch_date_in) THEN
                UPDATE Registers
                SET sid = session_id
                WHERE course_id = course_id_in AND launch_date = launch_date_in AND cust_id = cust_id_in;
                RETURN;
            ELSIF EXISTS(SELECT * FROM Redeems AS R WHERE R.cust_id = cust_id_in AND R.course_id = course_id_in AND R.launch_date = launch_date_in) THEN
                UPDATE Redeems
                SET sid = session_id
                WHERE course_id = course_id_in AND launch_date = launch_date_in AND cust_id = cust_id_in;
                RETURN;
            END IF;
            RAISE EXCEPTION 'You did not register for any session.';
        END IF;
        RAISE EXCEPTION 'The session is full.';
    ELSE
        RAISE EXCEPTION 'The session input is not a valid session.';
    END IF;
    COMMIT;
END;
$$ LANGUAGE plpgsql;

--20
CREATE OR REPLACE PROCEDURE cancel_registration(cust_id_in int, course_id_in int, launch_date_in date)
AS $$
DECLARE
    current_date date := (SELECT NOW()::date);
    start_session date;
    session_start_time time;
    refund_amt numeric := 0.00;
    course_amount numeric  := (SELECT fees FROM Course_offerings AS CO WHERE CO.course_id = course_id_in AND CO.launch_date = launch_date_in);
    package_credit int := 0;
    session_id int := 0;
BEGIN
    SELECT session_date, sid INTO start_session, session_id
    FROM Sessions as R
    WHERE R.course_id = course_id_in AND R.launch_date = launch_date_in;

    IF EXISTS(SELECT * FROM Registers AS R WHERE R.cust_id = cust_id_in AND R.course_id = course_id_in AND R.launch_date = launch_date_in) THEN
        SELECT session_date, sid, start_time INTO start_session, session_id, session_start_time FROM (Registers NATURAL JOIN Sessions) AS R WHERE R.cust_id = cust_id_in AND R.course_id = course_id_in AND R.launch_date = launch_date_in;
        IF (start_session - current_date >= 7) THEN
            refund_amt := course_amount * 0.9;
            --remove from registers table
            DELETE FROM Registers AS R WHERE (R.cust_id = cust_id_in AND R.launch_date = launch_date_in AND R.course_id = course_id_in);
            --insert into cancels table
            INSERT INTO Cancels VALUES (current_date, refund_amt, package_credit, cust_id_in, session_id, course_id_in, launch_date_in);
            COMMIT;
        ELSIF (start_session - current_date >= 0 and start_session - current_date < 7) THEN
            IF (start_session - current_date = 0 and session_start_time < CURRENT_TIME) THEN
                RAISE EXCEPTION 'The session you are trying to cancel has ended already.';
            END IF;
            DELETE FROM Registers AS R WHERE (R.cust_id = cust_id_in AND R.launch_date = launch_date_in AND R.course_id = course_id_in);
            INSERT INTO Cancels VALUES (current_date, refund_amt, package_credit, cust_id_in, session_id, course_id_in, launch_date_in);
            COMMIT;
        ELSE
            RAISE EXCEPTION 'The session you are trying to cancel has ended already.';
        END IF;
    ELSIF EXISTS(SELECT * FROM Redeems AS Re WHERE Re.cust_id = cust_id_in AND Re.course_id = course_id_in AND Re.launch_date = launch_date_in) THEN
        SELECT session_date, sid, start_time INTO start_session, session_id, session_start_time FROM (Redeems NATURAL JOIN Sessions) AS Re WHERE Re.cust_id = cust_id_in AND Re.course_id = course_id_in AND Re.launch_date = launch_date_in;
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
            IF (start_session - current_date = 0 and session_start_time < CURRENT_TIME) THEN
                RAISE EXCEPTION 'The session you are trying to cancel has ended already.';
            END IF;
            
            DELETE FROM Redeems AS R WHERE (R.cust_id = cust_id_in AND R.launch_date = launch_date_in AND R.course_id = course_id_in);
            INSERT INTO Cancels VALUES (current_date, refund_amt, package_credit, cust_id_in, session_id, course_id_in, launch_date_in);
            COMMIT;
        ELSE
            RAISE EXCEPTION 'The session you are trying to cancel has ended already.';
        END IF;
    ELSE 
        RAISE EXCEPTION 'You did not register for this session!';
    END IF;
END;
$$ LANGUAGE plpgsql;

--21
CREATE OR REPLACE PROCEDURE update_instructor(session_id int, course_id_in int, launch_date_in date, new_instructor_id int)
AS $$
DECLARE
    current_date date := (SELECT NOW()::date);
    session_date date := (SELECT session_date FROM Sessions WHERE sid = session_id AND course_id = course_id_in AND launch_date = launch_date_in);
    session_start_time time := (SELECT start_time FROM Sessions WHERE sid = session_id AND course_id = course_id_in AND launch_date = launch_date_in);
BEGIN
    IF (current_date <= session_date AND CURRENT_TIME < session_start_time) THEN
        UPDATE Sessions AS S
        SET eid = new_instructor_id
        WHERE S.sid = session_id AND S.course_id = course_id_in AND S.launch_date = launch_date_in;
        COMMIT;
    ELSE
        RAISE EXCEPTION 'The session has already started, updating of instructor is not allowed.';
    END IF;

END;
$$ LANGUAGE plpgsql;

-- 25
CREATE OR REPLACE FUNCTION pay_salary()
RETURNS TABLE (employee_id int, employee_name text, status text, number_of_work_days int, work_hours int, hourly_rate numeric, monthly_salary numeric, salary_amount_paid numeric) AS $$
DECLARE
    current_month int := (SELECT DATE_PART('month', NOW()));
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
        SELECT depart_date, join_date, name INTO departure_date, joined_date, employee_name
        FROM Employees
        WHERE eid = current_eid;
        IF EXISTS(SELECT 1 FROM Full_time_Emp AS FT WHERE FT.eid = current_eid) THEN
            monthly_salary := (SELECT FT.monthly_salary FROM Full_time_Emp AS FT WHERE eid = current_eid);
            status := 'Full-time';
            work_hours := NULL;
            hourly_rate := NULL;
            

            --full time and leaving
            IF (departure_date IS NOT NULL AND (EXTRACT(MONTH FROM departure_date) = current_month)) THEN
                -- join and leave in the same current month
                IF (EXTRACT(MONTH FROM joined_date) = current_month) THEN
                    number_of_work_days := EXTRACT(DAY FROM departure_date)::int - EXTRACT(DAY FROM joined_date)::int + 1;
                    salary_amount_paid := monthly_salary * (number_of_work_days::double precision/current_month_days);
                    salary_amount_paid := round(salary_amount_paid::numeric, 2);
                    
                    -- add into pay_slips table
                    INSERT INTO Pay_slips (payment_date, amount, num_work_hours, num_work_days, eid)
                    VALUES (NOW(), salary_amount_paid, NULL, number_of_work_days, current_eid);

                    RETURN NEXT;
                    CONTINUE;

                --join different from current month, leave in current month
                ELSE
                    number_of_work_days := EXTRACT(DAY FROM departure_date) - 1 + 1;
                    salary_amount_paid := monthly_salary * (number_of_work_days::double precision/current_month_days);
                    salary_amount_paid := round(salary_amount_paid::numeric, 2);
                    -- add into pay_slips table
                    INSERT INTO Pay_slips (payment_date, amount, num_work_hours, num_work_days, eid)
                    VALUES (NOW(), salary_amount_paid, NULL, number_of_work_days, current_eid);

                    RETURN NEXT;
                    CONTINUE;
                END IF;
            END IF;
            number_of_work_days := current_month_days;
            salary_amount_paid := monthly_salary;
            work_hours := NULL;
            hourly_rate := NULL;
            salary_amount_paid := round(salary_amount_paid::numeric, 2);
            INSERT INTO Pay_slips (payment_date, amount, num_work_hours, num_work_days, eid)
            VALUES (NOW(), salary_amount_paid, NULL, number_of_work_days, current_eid);
            RETURN NEXT;

        ELSIF EXISTS(SELECT 1 FROM Part_time_Emp AS PT WHERE PT.eid = current_eid) THEN
            hourly_rate := (select PT.hourly_rate FROM Part_time_Emp AS PT WHERE eid = current_eid);
            status := 'Part-time';
            WITH calc_hours AS (
                SELECT DATE_PART('HOUR',(end_time - start_time)) AS duration
                FROM Sessions
                WHERE eid = current_eid AND (EXTRACT(MONTH FROM session_date) = current_month)
            ) SELECT sum(duration) INTO work_hours FROM calc_hours;
            
            IF (work_hours IS NULL) THEN
                work_hours := 0;
            END IF;

            salary_amount_paid := work_hours * hourly_rate;
            
            salary_amount_paid := round(salary_amount_paid::numeric, 2);
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
            _course_id := _row.course_id;
            _launch_date := _row.launch_date;
            _course_title := _row.title;
            _course_area := _row.name;
            _deadline := _row.registration_deadline;
            _course_fees := _row.fees;
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
RETURNS TABLE (customer_id_out int, customer_name_out text, course_area_A text,
course_identifier_C int, course_title_C text, launch_date_offering_C date,
course_offering_deadline date, fees_course_offering numeric) AS $$
DECLARE
    curs CURSOR FOR (SELECT cust_id, name FROM Customers ORDER BY cust_id);
    all_offering_curs CURSOR FOR (SELECT _course_id, _launch_date, _course_title, _course_area, _deadline,
              _course_fees FROM get_available_course_offerings_with_id_and_launch_date());
    r RECORD;
    courses_record RECORD;
    last_purchase RECORD;
    last_register DATE;
    customer_name text;
    customer_id int;
    _rows RECORD;
    current_customer_name text;
    current_customer_id int;
BEGIN
    OPEN curs;
    LOOP
        FETCH curs INTO r;
        EXIT WHEN NOT FOUND;
        current_customer_name := r.name;
        current_customer_id := r.cust_id;
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
                customer_name_out := current_customer_name;
                customer_id_out := current_customer_id;
                course_area_A := courses_record._course_area;
                course_identifier_C := courses_record._course_id;
                course_title_C := courses_record._course_title;
                launch_date_offering_C := courses_record._launch_date;
                course_offering_deadline := courses_record._deadline;
                fees_course_offering := courses_record._course_fees;
                RETURN NEXT;
            END LOOP;
            CLOSE all_offering_curs;
        ELSIF ((DATE_PART('YEAR', NOW()::date) - DATE_PART('YEAR', last_register)) * 12 +
            (DATE_PART('MONTH', NOW()::date) - DATE_PART('MONTH', last_register)) >= 6) THEN

            --if less than 6 months and registered for a course before, find areas of last 3 sign-ups

            for _rows in select *
            FROM get_available_course_offerings_with_id_and_launch_date() NATURAL JOIN get_last_three_areas(customer_id) AS Z
            LOOP
                customer_name_out := current_customer_name;
                customer_id_out := current_customer_id;
                course_identifier_C := _rows._course_id;
                launch_date_offering_C := _rows._launch_date;
                course_title_C := _rows._course_title;
                course_area_A := _rows._course_area;
                course_offering_deadline := _rows._deadline;
                fees_course_offering := _rows._course_fees;
                RETURN NEXT;
            END LOOP;
        END IF;
        CONTINUE;
    END LOOP;
    CLOSE curs;
END;
$$ LANGUAGE plpgsql;

-- 27
CREATE OR REPLACE FUNCTION retrieve_top_packages(N int)
RETURNS TABLE (package_id int, total int) AS $$
BEGIN
    RETURN QUERY
    WITH filter_packages AS (
        SELECT * FROM (SELECT W.package_id, sale_start_date, price FROM Course_packages AS W) AS X NATURAL JOIN Buys WHERE EXTRACT(YEAR FROM sale_start_date) = EXTRACT(YEAR FROM NOW())
    ), packages_with_count AS (
        SELECT FP.package_id, count(FP.package_id)::int AS amount FROM filter_packages AS FP GROUP BY FP.package_id
    ), counts AS (
        SELECT DISTINCT count(FP.package_id)::int AS amount FROM filter_packages AS FP GROUP BY FP.package_id
    ), top_N_count AS (
        SELECT DISTINCT amount FROM counts ORDER BY amount DESC LIMIT N
    ) select Y.package_id, amount from (packages_with_count AS PC natural join top_N_count natural join Course_packages) AS Y ORDER BY amount DESC, price DESC;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION top_packages(N int)
RETURNS TABLE (package_identifier int, free_sessions int, price numeric, start_date date, end_date date, num_sold int) AS $$
DECLARE
    curs CURSOR FOR (SELECT package_id, total FROM retrieve_top_packages(N));
    r RECORD;
    current_package_id int;
BEGIN

    OPEN curs;
        LOOP
            FETCH curs INTO r;
            EXIT WHEN NOT FOUND;
            current_package_id := r.package_id;
            package_identifier := current_package_id;
            num_sold := r.total;
            free_sessions := (SELECT num_free_registrations FROM Course_packages WHERE package_id = current_package_id);
            price := (SELECT CP.price FROM Course_packages AS CP WHERE CP.package_id = current_package_id);
            start_date := (SELECT sale_start_date FROM Course_packages AS CP WHERE CP.package_id = current_package_id);
            end_date := (SELECT sale_end_date FROM Course_packages AS CP WHERE CP.package_id = current_package_id);
            RETURN NEXT;
        END LOOP;
    CLOSE curs;
END;
$$ LANGUAGE plpgsql;

-- 1, 4, 8, 11, 12, 16, 18, 23, 24, 30

-- 1
CREATE OR REPLACE PROCEDURE add_employee(IN em_name TEXT, IN em_address TEXT,
IN em_phone TEXT, IN em_email TEXT, IN join_date date, IN salary_type TEXT,
IN rate numeric, IN employee_type TEXT, IN em_areas text[]) AS $$

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
    RETURN QUERY(
    SELECT r1.rid FROM Rooms r1
    EXCEPT
    SELECT s1.rid FROM Sessions s1
    WHERE s1.session_date = s_date
    AND ((end_time <= s_hour + s_duration AND end_time >= s_hour)
        OR (start_time >= s_hour AND start_time <= s_hour +  s_duration)
	OR (start_time <= s_hour AND end_time >= s_hour + s_duration)));

END;
$$ LANGUAGE plpgsql;

-- 11
create or replace procedure add_course_package(in p_name text, in n_free int, 
in s_date date, in e_date date, in c_price numeric) as $$
DECLARE
    cid INT;

BEGIN
    if e_date < s_date then 
        raise exception 'Course package sale start date (%) cannot be later than end date (%).', s_date, e_date;

    elseif n_free <= 0 then
        raise exception 'Number of redemptions cannot be less than or equal zero.';

    elseif c_price < 0 then
        raise exception 'Price cannot be negative.';
    
    end if;

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
    RETURN QUERY(SELECT c1.name, c1.num_free_registrations, c1.sale_end_date, c1.price
    FROM Course_packages as c1
    WHERE c1.sale_end_date >= current_date);

END;
$$ LANGUAGE plpgsql;

-- 16
create or replace function get_available_course_sessions(in l_date date, in cid int)
returns table(session_date date, start_time time, instructor text, num_remaining_seats bigint) as $$
DECLARE
    s_capacity int;
    d_line date;

BEGIN
    SELECT seating_capacity, registration_deadline
    INTO s_capacity, d_line FROM Course_offerings
    WHERE l_date = launch_date AND cid = course_id;

    RETURN QUERY(
    SELECT s1.session_date, s1.start_time, s1.name as instructor, 
    s_capacity - (select count(*) from Registers 
    where launch_date = l_date and course_id = cid and sid = s1.sid)
    -  (select count(*) from Redeems 
    where launch_date = l_date and course_id = cid and sid = s1.sid)
    as num_remaining_seats
    FROM (Sessions natural join (SELECT eid, name FROM Employees) as foo1) as s1
    WHERE l_date = launch_date AND cid = course_id
    AND d_line >= current_date
    ORDER BY (s1.session_date, s1.start_time) asc);
END;
$$ LANGUAGE plpgsql;

-- 18
create or replace function get_my_registrations(in cid int)
returns table(course_name text, course_fee numeric, session_date_ date,
start_time_ time, session_duration_ interval, instructor_ text) as $$

BEGIN
    RETURN QUERY (
        WITH cust_registers AS (SELECT cust_id, sid, launch_date, course_id 
        FROM Registers where cust_id = cid),
        cust_redeems AS (SELECT cust_id, sid, launch_date, course_id
        FROM Redeems where cust_id = cid),
        c1 AS (SELECT course_id, name as cname FROM Courses),
        e1 AS (SELECT eid, name as ename FROM Employees),
        co1 AS (SELECT course_id, launch_date, fees FROM Course_offerings),
        s1 AS (SELECT start_time, end_time, session_date, course_id, launch_date, sid, eid FROM Sessions),
        c2 AS (SELECT * FROM c1 natural join co1),
        s2 AS (SELECT * FROM s1 natural join c2),
        s3 AS (SELECT * FROM s2 natural join e1),
        cust_registers_with_cname AS (SELECT * FROM cust_registers 
            natural join s3),
        cust_redeems_with_cname AS (SELECT * FROM cust_redeems 
            natural join s3)
        SELECT cname, fees, session_date, start_time, 
        end_time - start_time, ename
        FROM cust_registers_with_cname
        UNION
        SELECT cname, fees, session_date, start_time, 
        end_time - start_time, ename
        FROM cust_redeems_with_cname
        ORDER BY session_date, start_time asc
    );
END;
$$ LANGUAGE plpgsql;

--23
create or replace procedure remove_session(in l_date date, in cid int, in session_id int) as $$

DECLARE
    num_registrations int;
    session_start_date date;
    num_sessions int;
    check_if_session_exist int;

    current_sid int;
    loop_counter int;

BEGIN
    SELECT count(*) INTO num_registrations FROM Registers
    WHERE sid = session_id AND course_id = cid AND launch_date = l_date;

    SELECT session_date INTO session_start_date FROM Sessions
    WHERE sid = session_id AND course_id = cid AND launch_date = l_date;

    SELECT count(distinct sid) INTO num_sessions FROM Sessions
    WHERE course_id = cid AND launch_date = l_date;

    SELECT count(*) INTO check_if_session_exist FROM Sessions
    WHERE course_id = cid AND launch_date = l_date AND sid = session_id;

    if num_registrations > 0 then 
        raise exception 'Session cannot be removed. Number of registrations more than 0.';

    elseif session_start_date <= current_date then
        raise exception 'Session cannot be removed. Session has already started.';
    
    elseif num_sessions <= 1 then
        raise exception 'Session cannot be removed. Number of sessions cannot be 0.';

    elseif check_if_session_exist <= 0 then
        raise exception 'No such session is found.';

    end if;
    
    DELETE FROM Sessions
    WHERE sid = session_id AND course_id = cid AND launch_date = l_date;

    UPDATE Course_offerings
    SET start_date = (SELECT session_date FROM Sessions WHERE
    course_id = cid AND launch_date = l_date AND 
    session_date <= all(SELECT session_date FROM Sessions WHERE
    course_id = cid AND launch_date = l_date))
    WHERE course_id = cid AND launch_date = l_date;

    UPDATE Course_offerings
    SET end_date = (SELECT session_date FROM Sessions WHERE
    course_id = cid AND launch_date = l_date AND 
    session_date >= all(SELECT session_date FROM Sessions WHERE
    course_id = cid AND launch_date = l_date))
    WHERE course_id = cid AND launch_date = l_date;

    loop_counter := session_id + 1;

    LOOP
        EXIT WHEN loop_counter >= num_sessions + 1;

        UPDATE Sessions
        SET sid = sid - 1
        WHERE sid = loop_counter
        AND launch_date = l_date AND course_id = cid;

        loop_counter := loop_counter + 1;
    END LOOP;

END;
$$ LANGUAGE plpgsql;

--24
create or replace procedure add_session(in l_date date, in cid int, in new_session_id int,
in new_session_day date, in new_session_start_hour time, in instructor_id int, in room_id int) as $$

DECLARE
    deadline date;
    session_duration int;
    count_rid int;
    count_eid int;
    num_sessions int;
    loop_counter int;

BEGIN 
    /* find registration deadline. */
    SELECT registration_deadline INTO deadline 
    FROM Course_offerings WHERE launch_date = l_date AND course_id = cid;

    /* Find duration of the course session for end_time. */
    SELECT duration INTO session_duration
    FROM Courses
    WHERE course_id = cid;

    /* Count number of rooms that are available. */
    SELECT count(rid) into count_rid
    FROM find_rooms(new_session_day, new_session_start_hour, make_interval(hours := session_duration))
    WHERE rid = room_id;

    /* Count number of instructors that are available. */
    SELECT count(eid) into count_eid
    FROM find_instructors(cid, new_session_day, cast(extract(hour from new_session_start_hour) as integer))
    WHERE eid = instructor_id;

    /* Find current number of sessions for the course offering. */
    SELECT count(distinct sid) INTO num_sessions
    FROM Sessions
    WHERE launch_date = l_date AND course_id = cid;

    if deadline < current_date then
        raise exception 'Course offering deadline has passed. Deadline: %; Today: %', deadline, current_date;

    elseif new_session_day < deadline + 10 then
        raise exception 'Session day must be at least 10 days after registration deadline.';

    elseif count_rid <= 0 then
        raise exception 'Room is occupied.';

    elseif count_eid <= 0 then
        raise exception 'Instructor is busy.';
    
    end if;

    /* make sure insertion is within 1 to num_sessions + 1. */
    new_session_id := least(greatest(new_session_id, 1), num_sessions + 1);

    /* increment sid of sessions after the inserted session. */
    loop_counter := num_sessions;
    LOOP
        EXIT WHEN loop_counter = new_session_id - 1;

        UPDATE Sessions
        SET sid = sid + 1
        WHERE sid = loop_counter
        AND launch_date = l_date AND course_id = cid;

        loop_counter := loop_counter - 1;
    END LOOP;

    /* Insert new session. */
    INSERT INTO Sessions
    VALUES (new_session_id, new_session_day, new_session_start_hour,
    new_session_start_hour + make_interval(hours := session_duration), 
    room_id, instructor_id, l_date, cid);

    UPDATE Course_offerings
    SET start_date = (SELECT session_date FROM Sessions WHERE
    course_id = cid AND launch_date = l_date AND 
    session_date <= all(SELECT session_date FROM Sessions WHERE
    course_id = cid AND launch_date = l_date))
    WHERE course_id = cid AND launch_date = l_date;

    UPDATE Course_offerings
    SET end_date = (SELECT session_date FROM Sessions WHERE
    course_id = cid AND launch_date = l_date AND 
    session_date >= all(SELECT session_date FROM Sessions WHERE
    course_id = cid AND launch_date = l_date))
    WHERE course_id = cid AND launch_date = l_date;

END;
$$ LANGUAGE plpgsql;


--30
create or replace function view_manager_report()
returns table(manager_name text, num_course_areas bigint, num_course_offerings bigint,
total_registration_fees numeric, best_selling_course_offering text) as $$    
BEGIN 
    RETURN QUERY(
        WITH m1 AS (select * from Managers natural join Employees), 
        r1 AS (select * from Registers natural join (select 
            launch_date, course_id, fees, mid, end_date from course_offerings) as foo
            where extract(year from end_date) = extract(year from current_date)),
        cp1 AS (select package_id, price/num_free_registrations as fees
            from Course_packages),
        r2 AS (select * from Redeems natural join cp1 natural join (select 
            launch_date, course_id, mid, end_date from course_offerings) as foo
            where extract(year from end_date) = extract(year from current_date)),
        best1 AS (select mid, course_id,
            coalesce(sum(fees), 0) as total_fees_1
            from r1 group by mid, course_id),
        best2 AS (select mid, course_id,
            coalesce(sum(fees), 0) as total_fees_2
            from r2 group by mid, course_id),
        best3 AS (select mid, course_id,
            coalesce(total_fees_1, 0) + coalesce(total_fees_2, 0)
            as total_fees
            from best1 natural full join best2),
        best4 AS (select * from best3 natural join (select
            course_id, name as cname from Courses) as foo),
        best5 AS (select mid, cname from best4 as foo
            where total_fees = (select max(total_fees) from 
            best4 where foo.mid = mid)),
        best6 AS (select * from (select eid as mid from Managers) as foo
            natural left join best5)
        SELECT m1.name, (select count(*) from course_areas where eid = m1.eid),
        (select count(*) from course_offerings where mid = m1.eid),
        (select coalesce(sum(fees), 0) from r1 where mid = m1.eid) + 
        (select coalesce(sum(fees), 0) from r2 where mid = m1.eid),
        (select string_agg(cname, ', ') from best6 
            where mid = m1.eid group by mid)
        FROM m1
        ORDER BY m1.name asc
    );
END;
$$ LANGUAGE plpgsql;

--7
CREATE OR REPLACE FUNCTION get_available_instructors(cid int, start_date date, end_date date)
RETURNS TABLE(eid int, name text, num_hours int, day date, available_hours time []) AS $$
DECLARE
	curs CURSOR FOR (
	select E.eid, E.name
	from (Specializes natural join Courses natural join Instructors) A, Employees E
	where A.eid = E.eid
	and course_id = cid
	and depart_date IS NULL
	order by eid asc);
	r RECORD;
	start_day date;
	start_hour time;
	end_hour time;
	session_duration int;

BEGIN

IF cid IS NULL OR start_date IS NULL OR end_date IS NULL THEN
	RAISE EXCEPTION 'Arguments cannot be null!';
END IF;

select duration INTO session_duration
from Courses
where course_id = cid;

OPEN curs;
LOOP
	FETCH curs INTO r;
	EXIT WHEN NOT FOUND;

	eid := r.eid;
	name := r.name;
	start_day := start_date;

	while start_day <= end_date
	LOOP

		IF extract(dow from start_day) = 6 THEN
			start_day := start_day + '2 days'::interval;
			CONTINUE;
		ELSIF extract(dow from start_day) = 0 THEN
			start_day := start_day + '1 day'::interval;
			CONTINUE;
		END IF;
		
		select COALESCE(sum(DATE_PART('hour',end_time - start_time)),0) into num_hours
		from Sessions S1
		where S1.eid = r.eid
		and extract(month from S1.session_date) = extract(month from start_day)
		and extract(year from S1.session_date) = extract(year from start_day);

	--check if instructor is part-time and will exceed 30 hrs
		IF EXISTS (select 1 from Part_time_Instructors P where P.eid = r.eid) and num_hours + session_duration > 30 THEN
			start_day := start_day + '1 day'::interval;
			CONTINUE;	
		ELSE
			
			day := start_day;
			start_hour := '0900';
			available_hours := array[]::time[];

			--check if instructor has any session on this day
			IF NOT EXISTS (select 1 
				from Sessions S1 
				where S1.eid = r.eid
				and S1.session_date = start_day) THEN
				while start_hour + make_interval(hours := session_duration) <= '1800'
				LOOP
					end_hour := start_hour + make_interval(hours := session_duration);
					IF start_hour = '1200' THEN
						start_hour = '1400';
						CONTINUE;
					ELSIF end_hour <= '1200' or start_hour >= '1400' THEN
						available_hours := array_append(available_hours, start_hour);
					END IF;
					start_hour := start_hour + '1 hour'::interval;
				END LOOP;
				RETURN NEXT;
			ELSE
				while start_hour + make_interval(hours := session_duration) <= '1800'
				LOOP
					end_hour := start_hour + make_interval(hours := session_duration);
					IF start_hour = '1200' THEN
						start_hour = '1400';
						CONTINUE;
					ELSIF end_hour <= '1200' or start_hour >= '1400' THEN 
						--check if instructor has another session clashing with this hour
						IF NOT EXISTS (select 1 
							from Sessions S1 
							where S1.eid = r.eid  
							and S1.session_date = start_day 
							and ((start_hour >= start_time and start_hour <= end_time)
							or (end_hour >= start_time and end_hour <= end_time)
							or (start_hour < start_time and end_hour > end_time)
							or DATE_PART('hour', start_time - end_hour) = 0
							or DATE_PART('hour', start_hour - end_time) = 0)) THEN
								available_hours := array_append(available_hours, start_hour);
						END IF;
					END IF;
					start_hour := start_hour + '1 hour'::interval;
				END LOOP;
				--check if instructor has no available hours for this day
				IF array_length(available_hours,1) > 0 THEN
					RETURN NEXT;
				END IF;

			END IF;
		END IF;
		
		start_day := start_day + '1 day'::interval;

	END LOOP;
END LOOP;
CLOSE curs;
END;
$$ LANGUAGE plpgsql;
