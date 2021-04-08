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

call add_employee('Joon Leon', '770 Pine View Lane', '82910192', 'jl@gmail.com', '2020-01-09', 'full_time', 80000, 'Manager', array['Chemistry','Physics', 'Human Resource']);
call add_employee('Joon Lee', '0588 Crownhardt Crossing', '82193819', 'jl2@gmail.com', '2021-01-01', 'full_time', 1029, 'Administrator', null);
call add_employee('Joseph', '8880 Merry Parkway', '92819820', 'jjj99@hotmail.com', '2006-09-09', 'full_time', 99999, 'Manager', array['a', 'b', 'c']);
call add_employee('Iowa', '6 Brentwood Avenue', '10010100', 'iowal@gmail.com', '2008-06-07', 'full_time', 100000, 'Manager', array['p', 'q', 'r', 's']);
call add_employee('James', '93234 Golf View Plaza','10930184','james@gmail.com','2020-01-09','full_time',1209,'Administrator',null);
call add_employee('Jason', '3 Spaight Hill', '131314154', 'jason@gmail.com', '2020-01-09', 'full_time', 130193, 'Administrator',null);
call add_employee('Zook',	'28140 Stang Avenue', '13981331', 'zzzzz9191@gmail.com', '2008-09-06', 'full_time',	9138, 'Administrator',null);
call add_employee('Bob the builder',	'1109 Cottonwood Parkway',	'131138913', 'b0b@gmail.com', '2013-03-10', 'full_time', 894, 'Instructor', array['Physics', 'Human Resource']);
call add_employee('Yam', '04 Donald Park', '397592845', 'purple@gmail.com', '2013-02-28', 'full_time', 8394, 'Instructor', array['a', 'b']);
call add_employee('Anna',	'74 Autumn Leaf Crossing', '29875933', 'naan@gmail.com', '2012-02-28', 'full_time', 13091, 'Instructor', array['Chemistry', 'c']);
call add_employee('Kay',	'93 Brentwood Place','30987538', 'okay@gmail.com', '2020-01-09', 'full_time', 444, 'Instructor', array['p', 'q']);
call add_employee('Onion', '915 Drewry Court', '98340988', 'pink@gmail.com', '2018-01-01', 'part_time', 5,'Instructor', array['r', 's']);
call add_employee('Garlic', '6 Westerfield Pass',  '19292348', 'smells_great@gmail.com',	'2017-09-11', 'part_time', 5, 'Instructor', array['a', 'b', 'c', 'p', 'q', 'r', 's']);
call add_employee('Ginger', '58 Esker Place', '42492420',	'ginger@gmail.com',	'2021-01-02', 'part_time', 10,'Instructor', array['p', 'q', 'r', 's']);
call add_employee('Pepper', '39509 Veith Trail', '94024848', 'pepper9@gmail.com',	'2020-12-31', 'part_time', 100, 'Instructor', array['Human Resource']);
call add_employee('Nessy Webber', '786 Hovde Parkway','85274156', 'cwolton8@myspace.com', date '2020-05-06', 'full_time', 5500, 'Instructor', array['Chemistry', 'Human Resource']);

call add_course_in_bulk();                                                                                                                                                    
                                                                                                                                                    
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
                                                                                                                                        
                                                                                                                                        
INSERT  INTO  Rooms(rid,  location,  seating_capacity)  VALUES(1 ,'LT1','50');
INSERT  INTO  Rooms(rid,  location,  seating_capacity)  VALUES(2 ,'LT2','25');
INSERT  INTO  Rooms(rid,  location,  seating_capacity)  VALUES(3 ,'LT3','50');
INSERT  INTO  Rooms(rid,  location,  seating_capacity)  VALUES(4 ,'LT4','22');
INSERT  INTO  Rooms(rid,  location,  seating_capacity)  VALUES(5 ,'LT5','55');
INSERT  INTO  Rooms(rid,  location,  seating_capacity)  VALUES(6 ,'LT6','50');
INSERT  INTO  Rooms(rid,  location,  seating_capacity)  VALUES(7 ,'LT7','67');
INSERT  INTO  Rooms(rid,  location,  seating_capacity)  VALUES(8 ,'LT8','81');
INSERT  INTO  Rooms(rid,  location,  seating_capacity)  VALUES(9 ,'LT9','33');
INSERT  INTO  Rooms(rid,  location,  seating_capacity)  VALUES(10 ,'LT10','35');
INSERT  INTO  Rooms(rid,  location,  seating_capacity)  VALUES(11 ,'LT11','71');
INSERT  INTO  Rooms(rid,  location,  seating_capacity)  VALUES(12 ,'LT12','72');
INSERT  INTO  Rooms(rid,  location,  seating_capacity)  VALUES(13 ,'LT13','21');
INSERT  INTO  Rooms(rid,  location,  seating_capacity)  VALUES(14 ,'LT14','31');
INSERT  INTO  Rooms(rid,  location,  seating_capacity)  VALUES(15 ,'LT15','14');

call buy_course_package(0,1);
call buy_course_package(0,2);
call buy_course_package(1,3);
call buy_course_package(2,4);
call buy_course_package(3,5);
call buy_course_package(6,6);
call buy_course_package(7,7);
call buy_course_package(8,7);
call buy_course_package(9,9);
call buy_course_package(10,10);
call buy_course_package(11,11);
call buy_course_package(12,12);

call  add_course_offering(0, date  '2020-04-05',631.33,date  '2020-10-01',48470,2,'(2020-11-27,16,2)','(2020-10-23,09,3)','(2020-11-03,10,1)'); 
call  add_course_offering(2 , date  '2020-02-10' ,91.01, date  '2020-09-04' ,4602,5, '(2020-11-06,10,1)',  '(2020-12-02,15,4)'); 
call  add_course_offering(3 , date  '2020-10-23' ,517.71, date  '2020-12-11' ,18563,7, '(2020-11-27,16,2)',  '(2020-10-23,9,3)',  '(2020-11-03,10,1)'); 
call  add_course_offering(4 , date  '2021-02-10' ,962.80, date  '2021-03-01' ,922,6, '(2021-05-17,14,1)',  '(2021-05-21,16,10)',  '(2021-06-01,12,14)'); 
call  add_course_offering(4 , date  '2021-02-10' ,962.80, date  '2021-03-01' ,922,5, '(2021-05-17,15,1)',  '(2021-05-21,16,10)',  '(2021-06-01,14,13)'); 
call  add_course_offering(5 , date  '2021-02-28' ,511.29, date  '2021-03-27' ,9,2, '(2021-04-6,10,7)',  '(2021-04-09,9,5)',  '(2021-05-05,10,9)'); 
call  add_course_offering(6 , date  '2021-04-18' ,795.08, date  '2021-06-24' ,49810,7, '(2021-07-05,9,3)',  '(2021-07-12,10,12)',  '(2021-08-10,16,8)'); 
call  add_course_offering(7 , date  '2020-11-16' ,108.96, date  '2021-03-27' ,650,5, '(2021-04-12,14,11)',  '(2021-04-29,16,15)',  '(2021-04-09,10,11)'); 
call  add_course_offering(8 , date  '2021-03-08' ,925.38, date  '2021-06-01' ,61,2, '(2021-08-12,16,5)',  '(2021-10-31,9,14)'); 
call  add_course_offering(9 , date  '2021-03-15' ,273.06, date  '2021-04-10' ,9,5, '(2021-06-09,10,2)',  '(2021-06-23,14,3)',  '(2021-06-29,15,1)'); 
call  add_course_offering(10 , date  '2020-04-18' ,645.79, date  '2020-06-29' ,8340,7, '(2020-09-08,16,13)',  '(2020-09-25,9,3)'); 
call  add_course_offering(11 , date  '2020-07-29' ,534.47, date  '2020-09-23' ,30621,5, '(2020-11-26,16,10)',  '(2020-10-23,9,3)',  '(2020-11-25,10,6)'); 
call  add_course_offering(12 , date  '2020-05-08' ,549.12, date  '2020-07-25' ,18,6, '(2020-08-13,10,7)',  '(2020-08-28,16,9)'); 
call  add_course_offering(13 , date  '2020-07-29' ,31.28, date  '2020-10-12' ,785,5, '(2020-11-30,10,8)',  '(2020-12-16,9,11)'); 
call  add_course_offering(14 , date  '2021-02-09' ,410.86, date  '2021-04-04' ,3149,2, '(2021-04-30,17,5)',  '(2021-05-06,14,6)'); 
call  add_course_offering(14 , date  '2021-02-09' ,410.86, date  '2021-04-04' ,3149,2, '(2021-04-30,10,5)',  '(2021-05-06,14,6)'); 
call  add_course_offering(13 , date  '2020-12-03' ,329.53, date  '2021-02-04' ,6,5, '(2021-02-14,17,10)',  '(2021-02-23,10,15)',  '(2021-03-25,14,11)'); 
call  add_course_offering(1 , date  '2020-04-05' ,631.33, date  '2020-10-01' ,48470,7, '(2020-11-27,17,2)',  '(2020-10-23,9,3)',  '(2020-11-03,10,1)'); 
call  add_course_offering(11 , date  '2020-07-29' ,534.47, date  '2020-09-23' ,30621,5, '(2020-11-26,16,10)',  '(2020-10-23,9,4)',  '(2020-11-25,10,6)'); 
call  add_course_offering(3 , date  '2020-10-23' ,517.71, date  '2020-12-11' ,18563,2, '(2020-12-30,16,14)',  '(2021-01-06,9,12)',  '(2021-01-21,14,4)'); 
call  add_course_offering(0 , date  '2021-1-23' ,517.71, date  '2021-05-11' ,18563,2, '(2021-12-30,16,14)'); 
call  add_course_offering(6 , date  '2021-03-18' ,795.08, date  '2021-06-20' ,49810,7, '(2021-07-02,9,3)');
call  add_course_offering(0 , date  '2021-1-24' ,517.71, date  '2021-05-12' ,18563,2, '(2021-12-20,16,14)');                                                                                                   
call  add_course_offering(7 , date  '2021-02-01' ,534.47, date  '2021-05-24' ,100,5, '(2021-06-24,16,10)');
call  add_course_offering(7 , date  '2021-03-01' ,534.47, date  '2021-05-25' ,100,5, '(2021-06-25,16,10)');

select get_my_course_package(0);
select get_my_course_package(1);

select pay_salary();
select top_packages(1);
select top_packages(2);
                                                                                                                                        
call register_session(0, 6, date '2021-04-18', 2, TRUE);
call register_session(1, 6, date '2021-04-18', 2, TRUE);
call register_session(2, 6, date '2021-04-18', 2, TRUE);
call register_session(3, 6, date '2021-04-18', 2, TRUE);
call register_session(1, 8, date '2021-03-08', 1, TRUE);
call register_session(3, 8, date '2021-03-08', 1, TRUE);
call register_session(4, 8, date '2021-03-08', 2, TRUE);
call register_session(0, 9, date '2021-03-15', 3, TRUE);
call register_session(1, 9, date '2021-03-15', 3, TRUE);
call register_session(2, 9, date '2021-03-15', 2, TRUE);
call register_session(3, 9, date '2021-03-15', 1, TRUE);
call register_session(0, 2, date '2021-02-03', 1, TRUE);

call register_session(4, 6, date '2021-04-18', 2, FALSE);
call register_session(2,8, date'2021-03-08', 1,FALSE);
call register_session(0,8, date'2021-03-08', 1,FALSE);
call register_session(5,8, date'2021-03-08', 1,FALSE);
call register_session(6,8, date'2021-03-08', 1,FALSE);
call register_session(9,8, date'2021-03-08', 1,FALSE);
call register_session(14,8, date'2021-03-08', 1,FALSE);
call register_session(5, 6, date '2021-04-18', 2, FALSE);
call register_session(6, 6, date '2021-04-18', 2, FALSE);
call register_session(9, 6, date '2021-04-18', 2, FALSE);
call register_session(14, 6, date '2021-04-18', 2, FALSE);
call register_session(10, 9, date '2021-03-15', 3, FALSE);
call register_session(12, 9, date '2021-03-15', 3, FALSE);

call update_course_session(0, 6, date '2021-04-18', 3);
call update_course_session(0, 8, date '2021-03-08', 2);

call update_instructor(1,0, date '2020-04-05', 16);

call update_room (4, date '2021-04-18', 2, 1);
call update_room (8, date'2021-03-08', 1, 1);
call update_room (8, date'2021-03-08', 1, 10);
call update_room ( 6, date '2021-04-18', 2, 3);
call update_room ( 9, date '2021-03-15', 3, 4);
call update_room ( 6, date '2021-04-18', 2, 5);
call update_room (9, date '2021-03-15', 3, 6);

call cancel_registration(4, 6, date '2021-04-18');
call cancel_registration(2,8, date'2021-03-08');
call cancel_registration(0,8, date'2021-03-08');
call cancel_registration(6,8, date'2021-03-08');
call cancel_registration(9,8, date'2021-03-08');
call cancel_registration(14,8, date'2021-03-08');
call cancel_registration(5, 6, date '2021-04-18');
call cancel_registration(6, 6, date '2021-04-18');
call cancel_registration(9, 6, date '2021-04-18');
call cancel_registration(14, 6, date '2021-04-18');
call cancel_registration(10, 9, date '2021-03-15');
call cancel_registration(12, 9, date '2021-03-15');

call register_session(6,8, date'2021-03-08', 1,FALSE);
call register_session(9,8, date'2021-03-08', 1,FALSE);
call register_session(14,8, date'2021-03-08', 1,FALSE);
call register_session(5, 6, date '2021-04-18', 2, FALSE);
call register_session(6, 6, date '2021-04-18', 2, FALSE);
call register_session(9, 6, date '2021-04-18', 2, FALSE);
call register_session(14, 6, date '2021-04-18', 2, FALSE);
call register_session(10, 9, date '2021-03-15', 3, FALSE);
call register_session(12, 9, date '2021-03-15', 3, FALSE);
call register_session(0, 6, date '2021-04-18', 2, TRUE);
call register_session(4, 6, date '2021-04-18', 2, FALSE);
call register_session(2,8, date'2021-03-08', 1,FALSE);
call register_session(0,8, date'2021-03-08', 1,FALSE);
call register_session(7, 6, date '2021-03-18', 1, FALSE);
call register_session(8, 6, date '2021-03-18', 1, TRUE);
call register_session(9, 0, date '2021-01-24', 1, FALSE);
call register_session(6,7,date '2021-02-01',1, FALSE);
call register_session(7,7,date '2021-03-01',1, FALSE);
call register_session(8,7,date '2021-03-01',1, FALSE);
