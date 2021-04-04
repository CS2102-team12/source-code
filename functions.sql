-- 1, 4, 8, 11, 12, 16, 18, 23, 24, 30

-- 1
CREATE OR REPLACE FUNCTION add_employee(IN em_name TEXT, IN em_address TEXT,
IN em_phone TEXT, IN em_email TEXT, IN join_date date, IN salary_type TEXT,
IN rate INT, IN employee_type TEXT, IN em_areas text[]) RETURNS NULL AS $$

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
    
    ELSE IF salary_type = 'part_time' THEN
        INSERT INTO Part_time_Emp
        VALUES (rate, employee_id);
    
    END IF;

    IF employee_type = 'Administrator' THEN 
        INSERT INTO Administrators
        VALUES (employee_id);

    ELSE IF employee_type = 'Manager' THEN
        INSERT INTO Managers
        VALUES (employee_id);

        /* note: didn't check if key constraint violated */
        FOREACH area IN ARRAY em_areas
        LOOP
            INSERT INTO Course_areas
            VALUES (area, employee_id);
        END LOOP;
    
    ELSE IF employee_type = 'Instructor' THEN
        INSERT INTO Instructors
        VALUES (employee_id);

        IF salary_type = 'full_time' THEN
            INSERT INTO Full_time_Instructors
            VALUES (employee_id);
        
        ELSE IF salary_type = 'part_time' THEN
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
create or replace procedure update_credit_card(in customer_id int, in c_number int,
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
        OR (start_time >= s_hour AND start_time <= s_hour + s_duration));

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
    SELECT cname, fees, session_date, start_time, 
    end_time - start_time as session_duration, ename
    FROM (SELECT cust_id, sid, course_id, launch_date FROM Registers) as r1 natural join
    ((SELECT course_id, launch_date, fees FROM Course_offerings) as co1
    natural join (SELECT course_id, name as cname FROM Courses) as c1)) natural join
    ((SELECT sid, session_date, start_time, end_time, eid, launch_date, course_id FROM Sessions) as s1
    natural join (SELECT eid, name as ename FROM Employees) as e1)
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

    if num_registrations > 0 then return null;

    else if session_start_date <= current_date then return null;

    else DELETE FROM Sessions
    WHERE sid = session_id AND course_id = cid AND launch_date = l_date;

    end if;
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

    if deadline < current_date then return null;
    else if count_rid <= 0 then return null;
    else if count_eid <= 0 then return null;
    else
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
    end if;
END;
$$ LANGUAGE plpgsql;

--30
create or replace function view_manager_report()
returns table(manager_name text, num_course_areas int, num_course_offerings int,
total_registration_fees numeric, best_selling_course_offering text) as $$

DECLARE
    course_offerings_and_fees table(launch_date date, course_id int,
    eid int, registration_fees numeric);

    course_offerings_and_redemptions table(launch_date date, course_id int,
    eid int, redemption_fees numeric);

    course_offerings_and_total_fees table(launch_date date, course_id int,
    eid int, total_fees numeric);

    manager_and_best_selling table(eid int, title text);
    
BEGIN 
    SELECT co1.launch_date as launch_date, co1.course_id as course_id,
    co1.mid as eid, (count(*) * co1.fees) as registration_fees 
    FROM Course_offerings as co1, Sessions as s1, Registers as r1
    INTO course_offerings_and_fees
    WHERE co1.launch_date = s1.launch_date AND co1.course_id = s1.course_id
    AND r1.launch_date = co1.launch_date AND r1.course_id = co1.course_id
    AND r1.sid = s1.sid 
    AND extract(year from co1.end_date) = extract(year from current_date)
    GROUP BY co1.launch_date, co1.course_id, co1.mid;

    SELECT co1.launch_date as launch_date, co1.course_id as course_id,
    co1.mid as eid, (count(*) * r1.p1) as redemption_fees 
    FROM Course_offerings as co1, Sessions as s1, (Redeems natural join 
    (SELECT package_id, round(price/num_free_registrations) as p1 FROM Course_packages) as cp1) as r1
    INTO course_offerings_and_redemptions
    WHERE co1.launch_date = s1.launch_date AND co1.course_id = s1.course_id
    AND r1.launch_date = co1.launch_date AND r1.course_id = co1.course_id
    AND r1.sid = s1.sid
    AND extract(year from co1.end_date) = extract(year from current_date)
    GROUP BY co1.launch_date, co1.course_id, co1.mid;

    SELECT launch_date, course_id, eid, (redemption_fees + registration_fees) as total_fees
    FROM course_offerings_and_fees natural join course_offerings_and_redemptions
    INTO course_offerings_and_total_fees;

    SELECT co1.eid, co1.title
    FROM (course_offerings_and_total_fees
    natural join (SELECT course_id, title FROM Courses) as c1) as co1
    INTO manager_and_best_selling
    WHERE co1.total_fees >= SELECT(max(total_fees)
    FROM course_offerings_and_total_fees co2
    WHERE co1.eid = co2.eid); 
    

    SELECT m_name, count(a_name), count(launch_date, course_id), sum(total_fees), title
    FROM ((((Managers natural join (SELECT name as m_name, eid FROM Employees) as e1) 
    natural left join (SELECT name as a_name, eid FROM course_areas) as ca1))
    natural left join course_offerings_and_total_fees) 
    natural left join manager_and_best_selling
    GROUP BY eid, m_name
    ORDER BY m_name asc;
END;
$$ LANGUAGE plpgsql;
