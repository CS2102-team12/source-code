
--checks if the instructor specialises in the area of the session he is assigned to
--checks if the instructor is teaching 2 consecutive sessions
CREATE TRIGGER session_instructor_trigger
BEFORE INSERT OR UPDATE ON Sessions
FOR EACH ROW EXECUTE FUNCTION session_instructor_func();

CREATE OR REPLACE FUNCTION session_instructor_func() RETURNS TRIGGER
AS $$
DECLARE
inst_spec int;
inst_time int;
part_time_inst_hrs int;
courseArea text;
session_duration int;

BEGIN

select name INTO courseArea 
from Courses
where NEW.course_id = course_id;

select count(*) INTO inst_spec
from Specializes
where NEW.eid = eid
and courseArea = name;

select count(*) INTO inst_time
from Sessions
where NEW.eid = eid
and NEW.session_date = session_date
and (DATE_PART('hour', NEW.start_time-end_time) < 1
or DATE_PART('hour', start_time-NEW.end_time) < 1);

select sum(DATE_PART('hour',end_time-start_time)) into part_time_inst_hrs
from Part_time_Instructors natural join Sessions 
where eid = NEW.eid
and extract(month from session_date) = extract(month from NEW.session_date)
and extract(year from session_date) = extract(year from NEW.session_date);

select duration INTO session_duration
from Courses
where course_id = NEW.course_id;

IF inst_spec = 0 THEN
	RAISE NOTICE 'Instructor does not specialize in this course';
END IF;

IF part_time_inst_hrs + session_duration > 30 THEN
	RAISE NOTICE 'Part-time instructor not allowed to teach more than 30 hrs per month';
END IF;

IF (TG_OP='INSERT') THEN	
	IF inst_time > 0 THEN
	RAISE NOTICE 'Instructor not allowed to teach consecutive courses';
	END IF;
	IF inst_spec = 0 or inst_time > 0 or part_time_inst_hrs + session_duration > 30 THEN
		RETURN NULL;
	ELSE
		RETURN NEW;
	END IF;
END IF;

IF (TG_OP='UPDATE') THEN	
	IF inst_time > 1 THEN
		RAISE NOTICE 'Instructor not allowed to teach consecutive courses';
	END IF;
	IF inst_spec = 0 or inst_time > 1 or part_time_inst_hrs + session_duration > 30 THEN
		RETURN NULL;
	ELSE
		RETURN NEW;
	END IF;
END IF;
END;
$$ LANGUAGE plpgsql;


--checks if the session to be inserted clashes with another session of the same course offering
--checks if the room to be inserted is being used by other sessions
--checks if the instructor assigned has other sessions at the same time
CREATE TRIGGER session_time_trigger
BEFORE INSERT ON Sessions
FOR EACH ROW EXECUTE FUNCTION session_time_func();

CREATE OR REPLACE FUNCTION session_time_func() RETURNS TRIGGER
AS $$
DECLARE
same_session_time int;
BEGIN

same_session_time := 0;

select count(*) INTO same_session_time
from Sessions
where exists ( 
select 1 
from Sessions
where NEW.session_date = session_date
and (NEW.start_time >= start_time
and NEW.start_time <= end_time
or NEW.end_time >= start_time
and NEW.end_time <= end_time
or NEW.start_time < start_time
and NEW.end_time > end_time)
and (NEW.course_id = course_id
or NEW.rid = rid
or NEW.eid = eid)
);

IF (TG_OP='INSERT') THEN	
	IF same_session_time > 0 THEN
		RAISE NOTICE 'INSERTION ERROR: This session is in conflict with other sessions';
		RETURN NULL;
	ELSE
		RETURN NEW;
	END IF;
END IF;

IF (TG_OP='UPDATE') THEN	
	IF same_session_time > 1 THEN
		RAISE NOTICE 'UPDATE ERROR: This session is in conflict with other sessions';
		RETURN NULL;
	ELSE
		RETURN NEW;
	END IF;
END IF;
END;
$$ LANGUAGE plpgsql;


--checks if a customer has already registered for a course session for a particular course using credit card
CREATE TRIGGER registration_limit_trigger
BEFORE INSERT OR UPDATE ON Registers
FOR EACH ROW EXECUTE FUNCTION registration_limit_func();

CREATE OR REPLACE FUNCTION registration_limit_func() RETURNS TRIGGER
AS $$
DECLARE
num_reg int;
num_redeem int;
num_registration int;
capacity int;
reg_deadline date;
BEGIN

select count(*) INTO num_registration
from Registers
where NEW.course_id = course_id
and NEW.launch_date = launch_date
and NEW.sid = sid;

select seating_capacity INTO capacity
from (Sessions natural join Rooms)
where NEW.course_id = course_id
and NEW.launch_date = launch_date
and NEW.sid = sid;

select count(*) INTO num_reg
from Registers
where NEW.cust_id = cust_id
and NEW.course_id = course_id
and NEW.launch_date = launch_date;

select count(*) INTO num_redeem
from Redeems
where NEW.cust_id = cust_id
and NEW.course_id = course_id
and NEW.launch_date = launch_date;

select registration_deadline INTO reg_deadline
from Course_offerings
where NEW.course_id = course_id
AND NEW.launch_date = launch_date; 

IF num_registration = capacity THEN
	RAISE NOTICE 'The registration for this session is full';
END IF;

IF NEW.reg_date > reg_deadline THEN
	RAISE NOTICE 'The registration for this course has closed';
END IF;

IF num_redeem > 0 THEN
	RAISE NOTICE 'Customer has already redeemed for a course session for this course offering';
END IF;

IF (TG_OP='INSERT') THEN	
	IF num_reg > 0 THEN
		RAISE NOTICE 'Customer has already registered for a course session for this course offering';
	END IF;
	IF num_reg > 0 or num_redeem > 0 or NEW.reg_date > reg_deadline or num_registration = capacity THEN
		RETURN NULL;
	ELSE
		RETURN NEW;
	END IF;
END IF;

IF (TG_OP='UPDATE') THEN
	IF num_reg > 1 THEN
		RAISE NOTICE 'Customer has already registered for a course session for this course offering';
	END IF;
	IF num_reg > 1 or num_redeem > 0 or NEW.reg_date > reg_deadline or num_registration = capacity THEN
		RETURN NULL;
	ELSE
		RETURN NEW;
	END IF;
END IF;
END;
$$ LANGUAGE plpgsql;


--checks if a customer has already registered for a course session for a particular course using course package redemption
CREATE TRIGGER redemption_limit_trigger
BEFORE INSERT OR UPDATE ON Redeems
FOR EACH ROW EXECUTE FUNCTION redemption_limit_func();

CREATE OR REPLACE FUNCTION redemption_limit_func() RETURNS TRIGGER
AS $$
DECLARE
num_reg int;
num_redeem int;
num_registration int;
capacity int;
reg_deadline date;
BEGIN

select count(*) INTO num_registration
from Registers
where NEW.course_id = course_id
and NEW.launch_date = launch_date
and NEW.sid = sid;

select seating_capacity INTO capacity
from (Sessions natural join Rooms)
where NEW.course_id = course_id
and NEW.launch_date = launch_date
and NEW.sid = sid;

select count(*) INTO num_reg
from Registers
where NEW.cust_id = cust_id
and NEW.course_id = course_id
and NEW.launch_date = launch_date;

select count(*) INTO num_redeem
from Redeems
where NEW.cust_id = cust_id
and NEW.course_id = course_id
and NEW.launch_date = launch_date;

select registration_deadline INTO reg_deadline
from Course_offerings
where NEW.course_id = course_id
AND NEW.launch_date = launch_date; 

IF num_registration = capacity THEN
	RAISE NOTICE 'The registration for this session is full';
END IF;

IF NEW.redeem_date > reg_deadline THEN
	RAISE NOTICE 'The registration for this course has closed';
END IF;

IF num_reg > 0 THEN
	RAISE NOTICE 'Customer has already registered for a course session for this course offering';
END IF;

IF (TG_OP='INSERT') THEN	
	IF num_redeem > 0 THEN
		RAISE NOTICE 'Customer has already redeemed for a course session for this course offering';
	END IF;
	IF num_reg > 0 or num_redeem > 0 or NEW.redeem_date > reg_deadline or num_registration = capacity THEN
		RETURN NULL;
	ELSE
		RETURN NEW;
	END IF;
END IF;

IF (TG_OP='UPDATE') THEN
	IF num_redeem > 1 THEN
		RAISE NOTICE 'Customer has already redeemed for a course session for this course offering';
	END IF;
	IF num_reg > 0 or num_redeem > 1 or NEW.redeem_date > reg_deadline or num_registration = capacity THEN
		RETURN NULL;
	ELSE
		RETURN NEW;
	END IF;
END IF;
END;
$$ LANGUAGE plpgsql;

--check if a customer has more than 1 active/partially active packages
CREATE TRIGGER package_trigger
BEFORE INSERT OR UPDATE ON Buys
FOR EACH ROW EXECUTE FUNCTION package_func();

CREATE OR REPLACE FUNCTION package_func() RETURNS TRIGGER
AS $$
DECLARE
num_active_pkg int;
num_partially_active_pkg int;

BEGIN

select count(*) INTO num_active_pkg
from Buys
where NEW.cust_id = cust_id
and num_remaining_redemptions > 0;

select count(*) INTO num_partially_active_pkg
from Buys B1
where NEW.cust_id = B1.cust_id
and num_remaining_redemptions = 0
and exists (
select 1 
from (Redeems natural join Sessions)
where package_id = B1.package_id
and session_date - now()::date >= 7
);

IF (TG_OP='INSERT') THEN	
	IF num_active_pkg = 1 THEN
		RAISE NOTICE 'Customer can only have at most 1 active package';
	END IF;
	IF num_partially_active_pkg = 1 THEN
		RAISE NOTICE 'Customer can only have at most 1 partially active package';
	END IF;
	IF num_active_pkg = 1 or num_partially_active_pkg = 1 THEN
		RETURN NULL;
	ELSE
		RETURN NEW;
	END IF;
END IF;

IF (TG_OP='UPDATE') THEN	
	IF num_active_pkg > 1 THEN
		RAISE NOTICE 'Customer can only have at most 1 active package';
	END IF;
	IF num_partially_active_pkg > 1 THEN
		RAISE NOTICE 'Customer can only have at most 1 partially active package';
	END IF;
	IF num_active_pkg > 1 or num_partially_active_pkg > 1 THEN
		RETURN NULL;
	ELSE
		RETURN NEW;
	END IF;
END IF;
END;
$$ LANGUAGE plpgsql;