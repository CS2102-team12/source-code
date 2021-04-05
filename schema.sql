create table Customers (
cust_id int primary key,
address text,
phone text,
name text,
email text
);

create table Credit_cards (
card_number bigint primary key,
CVV int not null,
expiry_date date not null
);

create table Owns (
card_number bigint references Credit_cards,
cust_id int references Customers,
from_date date,
primary key(card_number,cust_id)
);

create table Employees (
eid int primary key,
name text,
phone text,
address text,
email text,
depart_date date,
join_date date not null
);

create table Pay_slips (
payment_date date,
amount numeric,
num_work_hours numeric
check (num_work_hours <= 30),
num_work_days int,
eid int references Employees
on delete cascade,
primary key(eid,payment_date)
);

create table Part_time_Emp (
hourly_rate numeric,
eid int primary key references Employees
on delete cascade
);

create table Full_time_Emp (
monthly_salary numeric,
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
sale_start_date date,
sale_end_date date,
num_free_registrations int,
name text,
price numeric
);

create table Rooms (
rid int primary key,
location text,
seating_capacity int
);

create table Course_areas (
name text primary key,
eid int not null references Managers
);

create table Courses (
course_id int primary key,
duration int,
title text,
description text, 
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
launch_date date,
start_date date,
end_date date,
registration_deadline date
check ( DATE_PART('day',start_date::timestamp-registration_deadline::timestamp) >= 10),
target_number_registrations int,
seating_capacity int,
fees numeric,
eid int not null references Administrators,
mid int not null references Managers,
course_id int references Courses
on delete cascade,
primary key(launch_date,course_id)
);

create table Sessions (
sid int,
session_date date
check ( extract(dow from session_date::timestamp) >= 1 and extract(dow from session_date::timestamp) <= 5),
start_time time
check ( start_time::time >= '0900' and start_time::time < '1200' or start_time::time >= '1400' and start_time::time < '1800'),
end_time time
check (end_time::time <= '1800' and end_time::time > '0900'),
rid int not null references Rooms,
eid int not null references Instructors,
launch_date date,
course_id int,
foreign key(launch_date, course_id) references Course_offerings
on delete cascade,
primary key(sid,course_id,launch_date)
);

create table Cancels (
cancel_date date,
refund_amt numeric,
package_credit int,
cust_id int references Customers,
sid int,
course_id int,
launch_date date,
foreign key(sid,course_id,launch_date) references Sessions,
primary key(cust_id,cancel_date,sid,course_id,launch_date)
);

create table Registers (
reg_date date,
card_number bigint,
cust_id int,
sid int,
course_id int,
launch_date date,
foreign key(card_number,cust_id) references Owns,
foreign key(sid,course_id,launch_date) references Sessions,
primary key(card_number,cust_id,reg_date,sid,course_id,launch_date)
);

create table Buys (
buy_date date,
package_id int references Course_packages,
card_number bigint,
cust_id int,
num_remaining_redemptions int not null,
foreign key(card_number,cust_id) references Owns,
primary key(buy_date,package_id,card_number,cust_id)
);

create table Redeems (
redeem_date date,
buy_date date,
package_id int references Course_packages,
card_number bigint,
cust_id int,
sid int,
course_id int,
launch_date date,
foreign key(sid,course_id,launch_date) references Sessions,
foreign key(buy_date,package_id,card_number,cust_id) references Buys,
primary key(redeem_date,sid,course_id,launch_date,buy_date,package_id,card_number,cust_id)
);


--checks if the instructor specialises in the area of the session he is assigned to
--checks if the instructor is teaching 2 consecutive sessions
CREATE TRIGGER session_inst_trigger
BEFORE INSERT ON Sessions
FOR EACH ROW EXECUTE FUNCTION session_inst_func();

CREATE OR REPLACE FUNCTION session_inst_func() RETURNS TRIGGER
AS $$
DECLARE
inst_spec int;
inst_time int;
courseArea text;
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
and (DATE_PART('minute', NEW.start_time-end_time) < 60
or DATE_PART('minute', start_time-NEW.end_time) < 60);

IF inst_spec = 0 or inst_time > 0 THEN
RETURN NULL;
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

IF same_session_time > 0 THEN
RETURN NULL;
END IF;

END;
$$ LANGUAGE plpgsql;

--checks if a customer has already registered for a course session for a particular course using credit card
CREATE TRIGGER registration_limit_trigger
BEFORE INSERT ON Registers
FOR EACH ROW EXECUTE FUNCTION registration_limit_func();

CREATE OR REPLACE FUNCTION registration_limit_func() RETURNS TRIGGER
AS $$
DECLARE
num_reg int;
num_redeem int;
reg_deadline date;
BEGIN

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
where NEW.course_id = course_id; 

IF num_reg > 0 or num_redeem > 0 or NEW.reg_date > reg_deadline THEN
RETURN NULL;
END IF;

END;
$$ LANGUAGE plpgsql;


--checks if a customer has already registered for a course session for a particular course using course package redemption
CREATE TRIGGER redemption_limit_trigger
BEFORE INSERT ON Redeems
FOR EACH ROW EXECUTE FUNCTION redemption_limit_func();

CREATE OR REPLACE FUNCTION redemption_limit_func() RETURNS TRIGGER
AS $$
DECLARE
num_reg int;
num_redeem int;
reg_deadline date;
BEGIN

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
where NEW.course_id = course_id; 

IF num_reg > 0 or num_redeem > 0 or NEW.redeem_date > reg_deadline THEN
RETURN NULL;
END IF;

END;
$$ LANGUAGE plpgsql;

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
from (Redeems R1 natural join Sessions S1) RS
where package_id = B1.package_id
and (S1.session_date - now() >= 7)
);

IF num_active_pkg > 1 or num_partially_active_pkg > 1 THEN
RETURN NULL;
END IF;

END;
$$ LANGUAGE plpgsql;

--check if a customer has more than 1 active/partially active packages
CREATE TRIGGER package_trigger
BEFORE INSERT ON Buys
FOR EACH ROW EXECUTE FUNCTION package_func();
