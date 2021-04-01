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
CREATE OR REPLACE PROCEDURE add_course_offering(cust_id int)
AS $$
DECLARE

BEGIN

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
$$
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
    IF (new_session_course_id == session_id AND new_session_launch_date == launch_date) THEN
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
            ENDIF;
        ENDIF;
    ENDIF;
    COMMIT;
END;
$$ LANGUAGE plpgsql;

--check: package_credit refers to the current amount of credit in active package, or is it the credit refunded (1 or 0).
CREATE OR REPLACE PROCEDURE cancel_registration(cust_id int, course_id int, launch_date date)
$$
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
        ENDIF;
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
        ENDIF;
    ENDIF;
END;
$$ LANGUAGE plpgsql;

