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

CALL add_customer ('Sapphira Swinley','1526 Jenna Park','124-648-8011','sswinley0@ehow.com',337941961691093,'2022-11-30',568);
CALL add_customer ('Hans Riddiough','35192 Atwood Circle','708-920-4203','hriddiough1@loc.gov',337941239704397,'2022-05-14',613);
CALL add_customer ('Willabella Christescu','2900 Sauthoff Trail','263-218-2174','wchristescu2@admin.ch',375673994596261,'2022-11-11',429);
CALL add_customer ('Salim Bellwood','2296 Towne Place','492-653-3676','sbellwood3@census.gov',349676044124227,'2022-07-09',841);
CALL add_customer ('Kathi Presnell','3 Arkansas Hill','202-849-5229','kpresnell4@ebay.com',374622637622597,'2021-07-08',135);
CALL add_customer ('Samara Rhule','6201 Loomis Place','108-601-1574','srhule5@lycos.com',378877486224053,'2023-02-09',907);
CALL add_customer ('Hall Metson','65974 Basil Street','899-498-8972','hmetson6@creativecommons.org',370957497094485,'2021-09-17',370);
CALL add_customer ('Jennette Issacoff','633 Anniversary Center','341-943-5463','jissacoff7@google.co.jp',374283448986638,'2021-04-26',113);
CALL add_customer ('Camilla DAlmeida','02109 Arapahoe Park','877-747-3039','cdalmeida8@feedburner.com',374288439396457,'2023-01-13',846);
CALL add_customer ('Conrade Bessey','44811 Maywood Trail','171-506-1643','cbessey9@free.fr',374622164896176,'2021-09-13',832);
CALL add_customer ('Stefano Havile','271 Morrow Pass','648-574-0170','shavilea@nifty.com',374288372074301,'2022-12-22',289);
CALL add_customer ('Teddy Duke','6332 Valley Edge Point','425-504-3950','tdukeb@indiegogo.com',374288248316142,'2022-02-03',523);
CALL add_customer ('Catlaina Roxbrough','3984 Melby Way','854-297-3829','croxbroughc@icq.com',347542557452029,'2021-12-15',866);
CALL add_customer ('Raddy MacKeig','480 Del Mar Center','412-919-7082','rmackeigd@walmart.com',374288779575975,'2022-12-12',53);
CALL add_customer ('Bram Schenfisch','844 Daystar Pass','382-685-5211','bschenfische@nbcnews.com',348024809032247,'2021-09-13',331);

CALL add_course_package ('A',10,'2021-01-01','2021-12-31',10922);
CALL add_course_package ('B',11,'2021-02-01','2021-03-03',30190);
CALL add_course_package ('C',1290,'2021-01-01','2023-12-30',10933);
CALL add_course_package ('D',29,'2021-09-09','2021-09-10',1900);
CALL add_course_package ('E',10,'2021-01-04','2021-04-01',2900);
CALL add_course_package ('F',28,'2021-03-05','2021-05-03',10000);
CALL add_course_package ('G',2,'2021-01-01','2021-12-31',100);
CALL add_course_package ('H',3,'2021-02-01','2021-03-03',200);
CALL add_course_package ('I',4,'2021-01-01','2023-12-30',319);
CALL add_course_package ('J',5,'2021-09-09','2021-09-10',69);
CALL add_course_package ('K',6,'2021-01-04','2021-04-01',1889);
CALL add_course_package ('L',10,'2021-03-05','2021-05-03',100);
CALL add_course_package ('M',100,'2021-02-01','2021-03-03',1000);
CALL add_course_package ('N',11,'2021-01-01','2023-12-30',110);
CALL add_course_package ('O',15,'2021-05-05','2023-05-05',1001);