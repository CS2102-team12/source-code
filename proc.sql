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