/*
    Цель задания:
    Проверить навыки написания простой функции Greenplum
*/


Реализовать в Greenplum функцию загрузки данных из STG в ODS определенного источника данных
Описание функции:
- данные источника могут фильтроваться (см. p_src_filter). 
Условие может быть произвольным, в зависимости от бизнес потребности, но в рамках атрибутивного состава источника данных
    Динамический sql использовать только на этапе получения данных из источника.
- бизнес-ключ - поле id. По данному полю происходит сравнение данных источника с данными ODS
    - если id новый, то данные загружаются с eff_dttm_from = момент расчета, а eff_dttm_to = 2999-12-31
    - если id уже есть в ODS, то активная строка (current_timestamp between eff_dttm_from and eff_dttm_to) по этому ключу закрывается, 
	т.е. eff_dttm_to = момент расчета, а новые данные загружаются, как в пункте выше
- на каждый шаг в функции пишем лог через функцию
    add_log(
        p_wf_id int4,           -- ИД потока
        p_wf_load_id int4,      -- ИД экземпляра запуска потока
        p_function_name text,   -- Название функции
        p_step_info text        -- Краткая информация по конкретному шагу в функции
    )
- по таблице ods получить кол-во записей: удаленных, измененных, загруженных
    эту информацию сохранить через функцию
    add_metric(
        p_wf_id int4,           -- ИД потока
        p_wf_load_id int4,      -- ИД экземпляра запуска потока
        p_table_name text,      -- Название таблицы
        p_metric_type text,     -- Тип метрики (deleted, updated, inserted)
        p_metric_value int4     -- Значение метрики (кол-во записей)
    )




Дано:
STG
(
    id int4 not null,
    field1 text,
    ....
    fieldN text
)
distributed by (id);

ODS
(
    id int4 not null,
    field1 text,
    ....
    fieldN text,

    /*Технические поля для каждой строки*/
    eff_dttm_from timestamp not null,       -- время открытия строки
    eff_dttm_to timestamp not null,         -- время закрытия строки

    /*Технические поля потока*/
    wf_id int4 not null,                    -- ИД потока
    wf_load_id int4 not null                -- ИД экземпляра запуска потока
)
distributed by (id, eff_dttm_to);

--Пример объявления функции загрузки данных
create or replace function schema_name.ods_load
(
    p_src_filter text,      --фильтр источника данных
    p_wf_id int4,           --ИД потока
    p_wf_load_id int4       --ИД экземпляра запуска потока
)
....



--1
create table STG
(
    id int4 not null,
    field1 text,
    field2 text,
    field3 text
)
distributed by (id);




create table ODS
(
    id int4 not null,
    field1 text,
    field2 text,
    field3 text,

    /*Технические поля для каждой строки*/
    eff_dttm_from timestamp not null,       -- время открытия строки
    eff_dttm_to timestamp not null,         -- время закрытия строки

    /*Технические поля потока*/
    wf_id int4 not null,                    -- ИД потока
    wf_load_id int4 not null                -- ИД экземпляра запуска потока
)
distributed by (id, eff_dttm_to);

--1 









Псевдо-SQL (PostgreSQL-совместимый стиль):

-определить изменения и обработать их пакетно
WITH current AS (
  SELECT d.customer_sk, d.customer_id, d.name AS old_name, d.address AS old_address,
         d.city AS old_city, d.phone AS old_phone,
         d.effective_from, d.end_date, d.is_current
  FROM dim_customer_scd d
  WHERE d.is_current = true -- определяем актуальные записи 
),
changes AS (
  SELECT s.customer_id, s.name AS new_name, s.address AS new_address, s.city AS new_city, s.phone AS new_phone,
         CURRENT_DATE AS change_date
  FROM staging_customer s -- новые записи 
)
-если есть различия, вставляем новую версию и обновляем старую
INSERT INTO dim_customer_scd (customer_id, name, address, city, phone, effective_from, end_date, is_current, version)
SELECT c.customer_id, c.new_name, c.new_address, c.new_city, c.new_phone, ch.change_date, DATE '9999-12-31', true,
       COALESCE((SELECT MAX(version) FROM dim_customer_scd WHERE customer_id = c.customer_id), 0) + 1
FROM changes c
JOIN current cur ON cur.customer_id = c.customer_id
JOIN changes ch ON ch.customer_id = c.customer_id
WHERE (cur.old_name IS DISTINCT FROM c.new_name OR
       cur.old_address IS DISTINCT FROM c.new_address OR
       cur.old_city IS DISTINCT FROM c.new_city OR
       cur.old_phone IS DISTINCT FROM c.new_phone);
-обновить старую версию
UPDATE dim_customer_scd
SET end_date = (SELECT change_date FROM changes WHERE customer_id = dim_customer_scd.customer_id),
    is_current = false
WHERE customer_id IN (SELECT customer_id FROM changes)
  AND end_date = DATE '9999-12-31'
  AND is_current = true;
  
  


    - если id новый, то данные загружаются с eff_dttm_from = момент расчета, а eff_dttm_to = 2999-12-31
    - если id уже есть в ODS, то активная строка (current_timestamp between eff_dttm_from and eff_dttm_to) по этому ключу закрывается, 
	т.е. eff_dttm_to = момент расчета, а новые данные загружаются, как в пункте выше
	



create 
--новые данные из staging
create temp table stg_records as 

select 
    id,
    field1,
    field2,
    field3
from STG; 

--текущие актуальные записи

create temp table current_records 
as 
select * from ODS;



/* example

INSERT INTO dim_customer_scd 
SELECT c.customer_id, c.new_name, c.new_address, ...,
       ch.change_date,              -- Дата начала новой версии
       DATE '9999-12-31',           -- Конец = "вечность" (пока актуально)
       true,                        -- is_current = true (новая версия актуальна)
       MAX(version) + 1             -- Увеличиваем версию на 1
FROM changes c
JOIN current cur ON cur.customer_id = c.customer_id  -- Соединяем старые и новые данные
WHERE (cur.old_name IS DISTINCT FROM c.new_name OR ...)  -- Если есть изменения
*/
-- сначала помечаем старые записи, как устаревшие

--1. 
id, field1, field2, field3 eff_dttm_from eff_dttm_to

1   'a'     'b'     'c'    '2025-11-11'  '2999-12-31'                        -- ods 
2   'a'     'b'     'c' --new


UPDATE ODS
SET cr.eff_dttm_to = CURRENT_TIMESTAMP  -- закрываем на момент расчета
from current_records cr --ODS
join stg_records stg --STG
on ( cr.field1 = stg.field1
     and cr.field2 = stg.field2
	 and cr.field3 = stg.field3)
where cr.id is distinct from stg.id
and cr.eff_dttm_to = cast('2999-12-31' as timestamp)
and current_timestamp between eff_dttm_from and eff_dttm_to;

--после апдейта:

id, field1, field2, field3 eff_dttm_from eff_dttm_to
1   'a'     'b'     'c'    '2025-11-11'  CURRENT_TIMESTAMP                        -- ods 


--2.

--inserting new records 
insert into ODS
	select 
		    ch.id, --not null,
			ch.field1, -- text,
			ch.field2, -- text,
			ch.field3, -- text,			
			/*Технические поля для каждой строки*/
			current_timestamp(), -- eff_dttm_from timestamp not null,       -- время открытия строки
			cast('2999-12-31' as timestamp), -- eff_dttm_to timestamp not null,         -- время закрытия строки
			/*Технические поля потока*/
			wf_id, --wf_id int4 not null,                    -- ИД потока
			wf_load_id, --wf_load_id int4 not null                -- ИД экземпляра запуска потока

from stg_records as ch --STG
join current_records cr 
on ( cr.field1 = stg.field1
     and cr.field2 = stg.field2
	 and cr.field3 = stg.field3);
	 
	 
id, field1, field2, field3 eff_dttm_from eff_dttm_to

1   'a'     'b'     'c'    '2025-11-11'  '2999-12-31'                        -- ods 
2   'a'     'b'     'c'    current_timestamp() cast('2999-12-31' as timestamp)





-- Начинаем транзакцию
BEGIN;

-- 1. Закрываем старые актуальные записи, которые изменились
UPDATE ODS 
SET eff_dttm_to = CURRENT_TIMESTAMP  -- закрываем на момент расчета
WHERE id IN (
    SELECT ch.id 
    FROM stg_records ch
    JOIN ODS cr ON cr.id = ch.id 
               AND cr.eff_dttm_to = '2999-12-31'  -- только актуальные
               AND CURRENT_TIMESTAMP BETWEEN cr.eff_dttm_from AND cr.eff_dttm_to
    -- Если нужно отслеживать изменения полей, добавьте условие:
    -- WHERE cr.field1 IS DISTINCT FROM ch.field1 
    --    OR cr.field2 IS DISTINCT FROM ch.field2
)
AND eff_dttm_to = '2999-12-31'
AND CURRENT_TIMESTAMP BETWEEN eff_dttm_from AND eff_dttm_to;

-- 2. Вставляем все новые данные (и новые id, и обновленные)
INSERT INTO ODS (
    id, field1, field2, field3, 
    eff_dttm_from, eff_dttm_to, 
    wf_id, wf_load_id
)
SELECT 
    ch.id,
    ch.field1,
    ch.field2,
    ch.field3,
    CURRENT_TIMESTAMP,               -- eff_dttm_from = момент расчета
    CAST('2999-12-31' AS TIMESTAMP), -- eff_dttm_to = бесконечность
    ch.wf_id,
    ch.wf_load_id
FROM stg_records ch
-- Берем ВСЕ записи из стейджинга (и новые, и обновленные)
LEFT JOIN ODS cr ON cr.id = ch.id 
                AND cr.eff_dttm_to = '2999-12-31'  -- проверяем актуальную версию
WHERE cr.id IS NULL  -- Новые ID (которых нет в ODS)
   OR EXISTS (       -- Или ID, которые были закрыты в шаге 1
        SELECT 1 FROM ODS 
        WHERE id = ch.id 
          AND eff_dttm_to = CURRENT_TIMESTAMP  -- только что закрытые
          AND eff_dttm_from < CURRENT_TIMESTAMP
   );

COMMIT;





id, field1, field2, field3

1   'a'     'b'     'c' 
2   'a'     'b'     'c'

--самый правильный вариант, если учесть, что id изменяется:

BEGIN;

-- 1. Закрываем старые записи, которые "переехали" на новый ID
UPDATE ODS 
SET eff_dttm_to = CURRENT_TIMESTAMP
from ODS join 



WHERE id IN (
    SELECT m.old_id
    FROM stg_records ch
    JOIN ODS cr ON (
        cr.field1 = ch.field1 
        AND cr.field2 = ch.field2 
        AND cr.field3 = ch.field3
    )
    WHERE cr.eff_dttm_to = '2999-12-31'
      AND cr.id IS DISTINCT FROM ch.id  -- ← ID ИЗМЕНИЛСЯ!
      AND CURRENT_TIMESTAMP BETWEEN cr.eff_dttm_from AND cr.eff_dttm_to
)
AND eff_dttm_to = '2999-12-31';



ods ( 1   'a'     'b'     'c' )









-- 2. Вставляем новые записи
INSERT INTO ODS (
    id, field1, field2, field3, 
    eff_dttm_from, eff_dttm_to, 
    wf_id, wf_load_id
)
SELECT 
    ch.id,
    ch.field1,
    ch.field2,
    ch.field3,
    CURRENT_TIMESTAMP,
    CAST('2999-12-31' AS TIMESTAMP),
    ch.wf_id,
    ch.wf_load_id
FROM stg_records ch
-- Вставляем запись, если:
WHERE NOT EXISTS (
    -- 1. Нет такой же записи (по бизнес-ключам) в ODS
    SELECT 1 FROM ODS cr
    WHERE cr.field1 = ch.field1 
      AND cr.field2 = ch.field2 
      AND cr.field3 = ch.field3
      AND cr.eff_dttm_to = '2999-12-31'
      AND cr.id = ch.id  -- И ID совпадает
)
OR EXISTS (
    -- 2. Или есть запись с такими же полями, но другим ID
    SELECT 1 FROM ODS cr
    WHERE cr.field1 = ch.field1 
      AND cr.field2 = ch.field2 
      AND cr.field3 = ch.field3
      AND cr.eff_dttm_to = '2999-12-31'
      AND cr.id IS DISTINCT FROM ch.id  -- ← ID отличается!
);

COMMIT;

--более правильная версия, где id - не первичный ключ, а первичный ключ - key


- бизнес-ключ - поле id. По данному полю происходит сравнение данных источника с данными ODS
    - если id новый, то данные загружаются с eff_dttm_from = момент расчета, а eff_dttm_to = 2999-12-31
    - если id уже есть в ODS, то активная строка (current_timestamp between eff_dttm_from and eff_dttm_to) по этому ключу закрывается, 
	т.е. eff_dttm_to = момент расчета, а новые данные загружаются, как в пункте выше


--1
create table STG
(	sk BIGSERIAL primary key,
    id int4 not null,
    field1 text,
    field2 text,
    field3 text,
	src text
)
distributed by (id);

--1.1

create temp table filtered_by_src_STG 
as 
	select 
	sk,
    id,
    field1,
    field2,
    field3,
	src
from STG 
where src = p_src_filter



--2
create table ODS
(	sk BIGSERIAL primary key,
    id int4 not null,
    field1 text,
    field2 text,
    field3 text,
    src text,
    /*Технические поля для каждой строки*/
    eff_dttm_from timestamp not null,       -- время открытия строки
    eff_dttm_to timestamp not null,         -- время закрытия строки

    /*Технические поля потока*/
    wf_id int4 not null,                    -- ИД потока
    wf_load_id int4 not null                -- ИД экземпляра запуска потока
)
distributed by (id, eff_dttm_to);


--3
-- закрываем прошлые версии записей, которые уже есть в ODS и активны ( eff_dttm_from and eff_dttm_to)
UPDATE ODS cr 
SET eff_dttm_to = CURRENT_TIMESTAMP()  -- закрываем на момент расчета
from filtered_by_src_STG stg
where ( cr.sk = stg.sk )
	and (
		cr.id <> stg.id -- бизнес-ключ (естественный, например email изменился)
	)
and eff_dttm_to = cast('2999-12-31' as timestamp) -- проверка, что строка активная
and current_timestamp between eff_dttm_from and eff_dttm_to; -- проверка, что строка активная

--4 
--загрузка новых записей (если id новый, то данные загружаются с eff_dttm_from = момент расчета, а eff_dttm_to = 2999-12-31)

/* это пример*/

INSERT INTO dwh.dim_customers (customer_id, full_name, phone, start_date, end_date, current_flag, metadata)
SELECT s.natural_key, s.full_name, s.phone, s.created_date, NULL, TRUE, s.metadata
FROM src s
LEFT JOIN dwh.dim_customers dc ON dc.customer_id = s.natural_key AND dc.current_flag = TRUE
WHERE dc.customer_sk IS NULL
   OR (
       COALESCE(dc.full_name,'') <> COALESCE(s.full_name,'') OR
       COALESCE(dc.phone,'') <> COALESCE(s.phone,'') OR
       COALESCE(dc.metadata::text,'') <> COALESCE(s.metadata::text,'')
   );
   
-- это мой вариант 


insert into ODS(id, field1, field2, field3, src, eff_dttm_from, eff_dttm_to, wf_id, wf_load_id)
	select 
		    stg.id, --not null,
			stg.field1, -- text,
			stg.field2, -- text,
			stg.field3, -- text,	
            stg.src,		
			/*Технические поля для каждой строки*/
			current_timestamp(), -- eff_dttm_from timestamp not null,       -- время открытия строки
			cast('2999-12-31' as timestamp), -- eff_dttm_to timestamp not null,         -- время закрытия строки
			/*Технические поля потока*/
			wf_id, --wf_id int4 not null,                    -- ИД потока
			wf_load_id, --wf_load_id int4 not null                -- ИД экземпляра запуска потока

from filtered_by_src_STG as stg --STG
left join ODS cr  -- ODS
on ( cr.sk = stg.sk and 
current_timestamp between cr.eff_dttm_from and cr.eff_dttm_to -- это чтобы джойнить только актуальные записи клиентов
)
where cr.id is null -- если после left join id null, значит такого поля нет в ods

or (

	stg.id <> cr.id

) -- или если клиент существует в ods, но у записи из stg отличается id от id в ods, то такую запись тоже добавляем

--where eff_dttm_to = CURRENT_TIMESTAMP – чтобы джойнить каждую новую запись с соот-ей последней актуальной записью
