/* add courses. */
create or replace procedure add_course_in_bulk() as $$
BEGIN
    call add_course('C1', 'this is a course', 'Chemistry', 2);
    call add_course('C2', 'this is a course', 'Physics', 2);
    call add_course('C3', 'this is a course', 'Human Resource', 2);
    call add_course('C4', 'this is a course', 'a', 2);
    call add_course('C5', 'this is a course', 'b', 2);
    call add_course('C6', 'this is a course', 'c', 2);
    call add_course('C7', 'this is a course', 'p', 2);
    call add_course('C8', 'this is a course', 'q', 2);
    call add_course('C9', 'this is a course', 'r', 2);
    call add_course('C10', 'this is a course', 's', 2);
    call add_course('C11', 'this is a course', 'a', 2);
    call add_course('C12', 'this is a course', 'Physics', 2);
    call add_course('C13', 'this is a course', 'Chemistry', 2);
    call add_course('C14', 'this is a course', 'Human Resource', 2);
    call add_course('C15', 'this is a course', 's', 2);
END;
$$ LANGUAGE plpgsql;

call add_course_in_bulk();