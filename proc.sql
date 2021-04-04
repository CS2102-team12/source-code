-- 3
CREATE OR REPLACE PROCEDURE add_customer ( _name TEXT, _home_address TEXT, _contact_number TEXT, _email_address TEXT,
_credit_card_number int, _expiry_date date, _cvv_code int) AS $$
DECLARE
    _cust_id INT;
BEGIN
    SELECT COALESCE(MAX(cust_id) + 1,0) INTO _cust_id FROM Customers;
    INSERT INTO Customers
    VALUES (_cust_id,_home_address,_contact_number,_name,_email_address);
    INSERT INTO Credit_Cards
    VALUES (_credit_card_number,CURRENT_DATE,_cvv_code,_expiry_date);
    INSERT INTO Owns
    VALUES (_credit_card_number,_cust_id);
END;
$$ LANGUAGE plpgsql;

-- 5

CREATE OR REPLACE PROCEDURE add_course (_course_title TEXT, _course_description TEXT, _course_area TEXT, _duration INT) AS $$
DECLARE
    _course_id INT;
BEGIN
    IF _course_area IS NULL OR _course_area NOT IN (SELECT name FROM Course_areas) THEN 
        RAISE EXCEPTION 'Invalid _course_area!';
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
            IF extract(dow from _counter) > 5 THEN
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
_credit_card_number INT;
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
    IF _session_number NOT IN (SELECT sid FROM get_available_course_sessions(_course_id, _launch_date))
    OR
    _customer_id NOT IN (SELECT cust_id FROM Customers) THEN
        RAISE EXCEPTION 'The session or customer cannot be found!';
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
        SELECT 1 FROM find_rooms(_session_date, _session_start_hour, _session_duration) WHERE rid = _new_room_id
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