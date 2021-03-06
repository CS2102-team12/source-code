drop table if exists Customers, Credit_cards, Owns, Employees, Pay_slips,
Part_time_Emp, Full_time_Emp, Administrators, Managers, Course_packages, Rooms, Courses,
Course_areas, Instructors, Specializes, Full_time_Instructors, Part_time_Instructors,
Course_offerings, Sessions, Cancels, Registers, Buys, Redeems;

create table Customers (
cust_id int primary key,
address text not null,
phone text not null,
name text not null,
email text not null
);

create table Credit_cards (
card_number bigint primary key
constraint _card_number check(card_number > 0),
CVV int not null,
expiry_date date not null
);

create table Owns (
card_number bigint references Credit_cards
constraint _card_number check(card_number > 0),
cust_id int references Customers,
from_date date not null,
primary key(card_number,cust_id)
);

create table Employees (
eid int primary key,
name text not null,
phone text not null,
address text not null,
email text not null,
depart_date date,
join_date date not null
);

create table Pay_slips (
payment_date date not null,
amount numeric not null
constraint _amount check(amount >= 0),
num_work_hours numeric
constraint part_time_hours check (num_work_hours <= 30),
num_work_days int
constraint _num_work_days check (num_work_days >= 0),
eid int references Employees
on delete cascade,
primary key(eid,payment_date)
);

create table Part_time_Emp (
hourly_rate numeric not null
constraint _hourly_rate check(hourly_rate > 0),
eid int primary key references Employees
on delete cascade
);

create table Full_time_Emp (
monthly_salary numeric not null
constraint _monthly_salary check(monthly_salary > 0),
eid int primary key references Employees
on delete cascade
);

create table Administrators (
eid int primary key references Full_time_Emp
on delete cascade
);

create table Managers (
eid int primary key references Full_time_Emp
on delete cascade
);

create table Course_packages (
package_id int primary key,
sale_start_date date not null,
sale_end_date date not null
constraint _sale_date check(sale_start_date::date <= sale_end_date::date),
num_free_registrations int not null
constraint _free_registrations check(num_free_registrations > 0),
name text not null,
price numeric not null
constraint _price check(price > 0)
);

create table Rooms (
rid int primary key,
location text not null,
seating_capacity int not null
constraint _seating_capacity check(seating_capacity > 0)
);

create table Course_areas (
name text primary key,
eid int not null references Managers
);

create table Courses (
course_id int primary key,
duration int not null
constraint _duration check(duration > 0),
title text not null,
description text not null, 
name text not null references Course_areas
);

create table Instructors (
eid int primary key references Employees
on delete cascade
);

create table Specializes (
eid int references Instructors,
name text references Course_areas,
primary key(eid,name)
);

create table Full_time_Instructors (
eid int primary key references Instructors
on delete cascade
);

create table Part_time_Instructors (
eid int primary key references Instructors
on delete cascade
);

create table Course_offerings (
launch_date date not null,
start_date date not null
constraint _start_date check(start_date::date > launch_date::date),
end_date date not null
constraint _end_date check (end_date::date >= start_date::date),
registration_deadline date not null
constraint reg_deadline check ( DATE_PART('day',start_date::timestamp-registration_deadline::timestamp) >= 10),
target_number_registrations int not null
constraint _target_registrations check(target_number_registrations > 0),
seating_capacity int not null
constraint _seating_capacity check(seating_capacity > 0),
fees numeric not null
constraint _fees check(fees > 0),
eid int not null references Administrators,
mid int not null references Managers,
course_id int references Courses
on delete cascade,
primary key(launch_date,course_id)
);

create table Sessions (
sid int,
session_date date not null
constraint session_day check ( extract(dow from session_date::timestamp) >= 1 and extract(dow from session_date::timestamp) <= 5),
start_time time not null
constraint session_start_time check ( start_time::time >= '0900' and start_time::time < '1200' or start_time::time >= '1400' and start_time::time < '1800'),
end_time time not null
constraint session_end_time check (end_time::time <= '1800' and end_time::time > '0900' and end_time::time > start_time::time),
rid int not null references Rooms,
eid int not null references Instructors,
launch_date date
constraint _launch_date check(launch_date::date < session_date::date),
course_id int,
foreign key(launch_date, course_id) references Course_offerings
on delete cascade,
primary key(sid,course_id,launch_date)
);

create table Cancels (
cancel_date date,
refund_amt numeric
constraint _refund_amt check(refund_amt >= 0),
package_credit int,
cust_id int references Customers,
sid int,
course_id int,
launch_date date
constraint _launch_date check(launch_date::date < cancel_date::date),
foreign key(sid,course_id,launch_date) references Sessions
on update cascade,
primary key(cust_id,cancel_date,sid,course_id,launch_date)
);

create table Registers (
reg_date date,
card_number bigint
constraint _card_number check(card_number > 0),
cust_id int,
sid int,
course_id int,
launch_date date
constraint _launch_date check(launch_date::date < reg_date::date),
foreign key(card_number,cust_id) references Owns,
foreign key(sid,course_id,launch_date) references Sessions
on update cascade,
primary key(card_number,cust_id,reg_date,sid,course_id,launch_date)
);

create table Buys (
buy_date date,
package_id int references Course_packages,
card_number bigint
constraint _card_number check(card_number > 0),
cust_id int,
num_remaining_redemptions int not null,
foreign key(card_number,cust_id) references Owns,
primary key(buy_date,package_id,card_number,cust_id)
);

create table Redeems (
redeem_date date,
buy_date date
constraint _buy_date check(redeem_date::date >= buy_date::date),
package_id int references Course_packages,
card_number bigint
constraint _card_number check(card_number > 0),
cust_id int,
sid int,
course_id int,
launch_date date
constraint _launch_date check(launch_date::date < redeem_date::date),
foreign key(sid,course_id,launch_date) references Sessions
on update cascade,
foreign key(buy_date,package_id,card_number,cust_id) references Buys,
primary key(redeem_date,sid,course_id,launch_date,buy_date,package_id,card_number,cust_id)
);


--check if start date/end date of a course offering is the date of its earliest/latest session
CREATE OR REPLACE FUNCTION course_offering_date_func() RETURNS TRIGGER
AS $$
DECLARE

earliest_session_date date;
latest_session_date date;
_start_date date;
_end_date date;

BEGIN

select session_date INTO earliest_session_date
from Sessions S
where NEW.course_id = course_id
and NEW.launch_date = launch_date
and session_date <= all (
select session_date
from Sessions
where course_id = S.course_id
and launch_date = S.launch_date);

select session_date INTO latest_session_date
from Sessions S
where NEW.course_id = course_id
and NEW.launch_date = launch_date
and session_date >= all (
select session_date
from Sessions
where course_id = S.course_id
and launch_date = S.launch_date);

select start_date, end_date INTO _start_date, _end_date
from Course_offerings
where NEW.course_id = course_id
and NEW.launch_date = launch_date;

IF NOT (_start_date = earliest_session_date and _end_date = latest_session_date) THEN
	RAISE EXCEPTION 'Start/end date of course offering is not the date of its earliest/latest session';
END IF;

END;
$$ LANGUAGE plpgsql;

drop trigger if exists course_offering_date_trigger on Sessions;

CREATE CONSTRAINT TRIGGER course_offering_date_trigger
AFTER INSERT OR UPDATE OR DELETE ON Sessions
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE course_offering_date_func();


--checks if the instructor specialises in the area of the session he is assigned to
--checks if the instructor is teaching 2 consecutive sessions
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
and (DATE_PART('hour', NEW.start_time-end_time) = 0
or DATE_PART('hour', start_time-NEW.end_time) = 0);

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
	
IF inst_time > 0 THEN
	RAISE NOTICE 'Instructor not allowed to teach consecutive courses';
END IF;

IF inst_spec = 0 or inst_time > 0 or part_time_inst_hrs + session_duration > 30 THEN
	RAISE EXCEPTION 'Operation aborted';
END IF;

END;
$$ LANGUAGE plpgsql;

drop trigger if exists session_instructor_trigger on Sessions;

CREATE CONSTRAINT TRIGGER session_instructor_trigger
AFTER INSERT OR UPDATE ON Sessions
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE session_instructor_func();


--checks if the session to be inserted clashes with another session of the same course offering
--checks if the room to be inserted is being used by other sessions
--checks if the instructor assigned has other sessions at the same time
CREATE OR REPLACE FUNCTION session_time_func() RETURNS TRIGGER
AS $$
DECLARE
same_session_time int;
BEGIN

same_session_time := 0;

select count(*) INTO same_session_time
from Sessions
where NEW.session_date = session_date
and ((NEW.start_time >= start_time and NEW.start_time <= end_time)
or (NEW.end_time >= start_time and NEW.end_time <= end_time)
or (NEW.start_time < start_time and NEW.end_time > end_time))
and (NEW.course_id = course_id
or NEW.rid = rid
or NEW.eid = eid);

IF same_session_time > 1 THEN
	RAISE EXCEPTION 'This session is in conflict with other sessions';
END IF;

END;
$$ LANGUAGE plpgsql;

drop trigger if exists session_time_trigger on Sessions;

CREATE CONSTRAINT TRIGGER session_time_trigger
AFTER INSERT OR UPDATE ON Sessions
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE session_time_func();


--checks if a customer has already registered for a course session for a particular course using credit card
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

IF num_reg > 1 THEN
	RAISE NOTICE 'Customer has already registered for a course session for this course offering';
END IF;

IF num_reg > 1 or num_redeem > 0 or NEW.reg_date > reg_deadline or num_registration = capacity THEN
	RAISE EXCEPTION 'Operation aborted';
END IF;

END;
$$ LANGUAGE plpgsql;

drop trigger if exists registration_limit_trigger on Registers;

CREATE CONSTRAINT TRIGGER registration_limit_trigger
AFTER INSERT OR UPDATE ON Registers
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE registration_limit_func();


--checks if a customer has already registered for a course session for a particular course using course package redemption
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
	
IF num_redeem > 1 THEN
	RAISE NOTICE 'Customer has already redeemed for a course session for this course offering';
END IF;

IF num_reg > 0 or num_redeem > 1 or NEW.redeem_date > reg_deadline or num_registration = capacity THEN
	RAISE EXCEPTION 'Operation aborted';
END IF;

END;
$$ LANGUAGE plpgsql;

drop trigger if exists redemption_limit_trigger on Redeems;

CREATE CONSTRAINT TRIGGER redemption_limit_trigger
AFTER INSERT OR UPDATE ON Redeems
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE redemption_limit_func();


--check if a customer has more than 1 active/partially active packages
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
	
IF num_active_pkg > 1 THEN
	RAISE NOTICE 'Customer can only have at most 1 active package';
END IF;
IF num_partially_active_pkg > 1 THEN
	RAISE NOTICE 'Customer can only have at most 1 partially active package';
END IF;

IF num_active_pkg > 1 or num_partially_active_pkg > 1 THEN
	RAISE EXCEPTION 'Operation aborted';
END IF;
END;
$$ LANGUAGE plpgsql;

drop trigger if exists package_trigger on Buys;

CREATE CONSTRAINT TRIGGER package_trigger
AFTER INSERT OR UPDATE ON Buys
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE package_func();
