create or replace procedure test_register_session() as $$
    /* (_customer_id INT, _course_id INT, _launch_date DATE, 
    _session_number INT, _use_package BOOLEAN) */
    DECLARE
        customer_id int;
        l1 date;
        cid int;
        s1 int;
        l int;
        d1 date;
   
    BEGIN
        l := 0;

    LOOP
        EXIT WHEN l = 10;
        select cust_id into customer_id from customers
        order by random() limit 1;

        select launch_date, course_id, registration_deadline into l1, cid, d1 from Course_offerings
        where registration_deadline >= current_date;

        select sid into s1 from Sessions
        where l1 = launch_date and course_id = cid
        order by random() limit 1;

        RAISE NOTICE 'Attempting registration: %, %, %, %, no package, deadline: %',
        customer_id, cid, l1, s1, d1;

        call register_session(customer_id, cid, l1, s1, false);

        COMMIT;

        l := l + 1;
    END LOOP;

    END;
$$ LANGUAGE plpgsql;

create or replace procedure test_buy_package() as $$
    /* (_customer_id INT, _course_id INT, _launch_date DATE, 
    _session_number INT, _use_package BOOLEAN) */
    DECLARE
        customer_id int;
        l int;
        pid int;

    BEGIN
        l := 0;

    LOOP
        EXIT WHEN l = 10;
        select cust_id into customer_id from customers
        order by random() limit 1;

        select package_id into pid from Course_packages
        order by random() limit 1;

        RAISE NOTICE 'Attempting package purchase: customer - %, package - %',
        customer_id, pid;

        call buy_course_package(customer_id, pid);

        COMMIT;

        l := l + 1;
    END LOOP;

    END;
$$ LANGUAGE plpgsql;

create or replace procedure test_remove_sessions() as $$
    /* add_session(in l_date date, in cid int, in new_session_id int,
    in new_session_day date, in new_session_start_hour time, 
    in instructor_id int, in room_id int) */
    BEGIN

        call remove_session('2021-04-18', 6, 1);

        call add_session('2021-04-18', 6, 1, 
        '2021-07-12', '10:00', 14, 12);

        call add_session('2021-04-18', 6, 1, 
        '2021-07-05', '09:00', 14, 3);



        select * from sessions where launch_date = '2021-04-18' and course_id = 6;

    END;
$$ LANGUAGE plpgsql;

--call test_register_session();
--call test_buy_package();
call test_remove_sessions();
