# Протокол тестирования FoodExpress

Проект: `egorov_food`  
База для проверки: `foodexpress_check`  
Роль аудитора: `inspector`  
Пароль: `NetoSQL2025`  
Версия PostgreSQL: 15+



## 1. Подготовка и восстановление backup


### 1.1. Создать чистую тестовую базу и схему exts

Если база уже существует, удалить и создать заново:

```bash
dropdb -U postgres --if-exists foodexpress_check
createdb -U postgres foodexpress_check
```
```sql
CREATE SCHEMA IF NOT EXISTS exts;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" SCHEMA exts;
```

### 1.2. Восстановить архив под postgres

Из каталога, где находится файл `foodexpress_egorov.backup`:

```bash
pg_restore -h localhost -p 5432 -U postgres -W -d foodexpress_check --no-owner foodexpress_egorov.backup
```

### 1.3. Применить grants.sql под postgres

Скрипт:
grants.sql



### 1.5. Подключиться как inspector и запустить SQL-файл

```bash
psql -U inspector -d foodexpress_check -h localhost
```

Введи пароль `NetoSQL2025`. Внутри `psql` можно выполнить весь тестовый SQL-файл:


## 2. Окружение и роль

Все следующие проверки выполняются под `inspector`.

```sql
SELECT version();
SELECT current_user;
```

Ожидается:
- версия PostgreSQL 15 или выше;
- `current_user = inspector`.

## 3. FOOD-101 — структура схемы

### 3.1. Схема существует

```sql
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name = 'egorov_food';
```

Ожидается: одна строка `egorov_food`.

### 3.2. Схема exts и расширение uuid-ossp

```sql
SELECT extname, extnamespace::regnamespace AS schema
FROM pg_catalog.pg_extension
WHERE extname = 'uuid-ossp';
```

Ожидается: `uuid-ossp`, схема `exts`.

### 3.3. Таблицы проекта

```sql
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'egorov_food'
  AND table_type = 'BASE TABLE'
ORDER BY table_name;
```

Ожидаются 12 исходных таблиц + дополнительные таблицы, если они появились при нормализации:
`address`, `client`, `client_address`, `courier`, `courier_pay`, `order`, `order_structure`, `payment`, `product`, `product_category`, `restaurant`, `review`.

### 3.4. Все идентификаторы *_id имеют тип uuid

```sql
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'egorov_food'
  AND column_name LIKE '%\_id' ESCAPE '\'
  AND data_type <> 'uuid'
ORDER BY table_name, column_name;
```

Ожидается: 1 transaction_id тип varchar (BR 8.3)

### 3.5. Enum-типы

```sql
SELECT t.typname,
       array_agg(e.enumlabel ORDER BY e.enumsortorder) AS enum_values
FROM pg_catalog.pg_type t
JOIN pg_catalog.pg_enum e ON e.enumtypid = t.oid
JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
WHERE n.nspname = 'egorov_food'
GROUP BY t.typname
ORDER BY t.typname;
```

Ожидается: 8 enum-типов со значениями, соответствующими `constraints.md`.

### 3.6. Внешние ключи

```sql
SELECT con.conname,
       con.conrelid::regclass AS table_name,
       con.confrelid::regclass AS referenced_table
FROM pg_catalog.pg_constraint con
WHERE con.contype = 'f'
  AND con.connamespace = 'egorov_food'::regnamespace
ORDER BY table_name, con.conname;
```

Ожидается: не менее 15 FK; связи соответствуют `docs/erd.md`.

### 3.7. Пароли хранятся в MD5-формате

```sql
SELECT length(c.password) AS password_length, c.password
FROM egorov_food.client c
LIMIT 5;
```

Ожидается: длина 32 символа, hex-строка.

---

## 4. FOOD-102/103 — генерация и очистка тестовых данных

### 4.1. Очистить схему

```sql
CALL egorov_food.erase_test_data();
```

Ожидается: без ошибок.

### 4.2. Сгенерировать 10 тестовых наборов

```sql
CALL egorov_food.insert_test_data(10);
```

Ожидается: без ошибок.

### 4.3. Проверить количество строк (BR-11.7)

```sql
SELECT 'client' AS tbl, count(*) FROM egorov_food.client
UNION ALL SELECT 'courier', count(*) FROM egorov_food.courier
UNION ALL SELECT 'product_category', count(*) FROM egorov_food.product_category
UNION ALL SELECT 'restaurant', count(*) FROM egorov_food.restaurant
UNION ALL SELECT 'address', count(*) FROM egorov_food.address
UNION ALL SELECT 'product', count(*) FROM egorov_food.product
UNION ALL SELECT 'order', count(*) FROM egorov_food."order"
UNION ALL SELECT 'review', count(*) FROM egorov_food.review
UNION ALL SELECT 'payment', count(*) FROM egorov_food.payment
ORDER BY tbl;
```

Ожидается: `10, 10, 10, 10, 50, 50, 50, 50, 50` соответственно.

### 4.4. Адреса ресторанов и клиентов (BR-11.7)

```sql
SELECT 'restaurant addresses' AS category, count(*)
FROM egorov_food.restaurant
WHERE address_id IS NOT NULL
UNION ALL
SELECT 'all addresses', count(*)
FROM egorov_food.address;
```

Ожидается: 10 ресторанных адресов, 50 адресов всего (40 клиентских).

### 4.5. Нет пустых обязательных строк

```sql
SELECT count(*) AS invalid_clients
FROM egorov_food.client
WHERE login = '' OR password = '' OR phone_number = '';
```

Ожидается: 0. Аналогично должны быть проверены остальные обязательные varchar-поля.

### 4.6. Нет NULL в обязательных полях заказа

```sql
SELECT count(*) AS invalid_orders
FROM egorov_food."order"
WHERE client_id IS NULL
   OR restaurant_id IS NULL
   OR courier_id IS NULL
   OR address_id IS NULL
   OR total_amount IS NULL;
```

Ожидается: 0.

### 4.7. Есть хотя бы один активный курьер (BR-6.6)

```sql
SELECT count(*) AS active_couriers
FROM egorov_food.courier
WHERE status <> 'уволен';
```

Ожидается: значение не меньше 1.

### 4.8. Выплаты курьерам согласованы с комиссиями (BR-10.2)

```sql
SELECT cp.year, cp.month, cp.courier_id,
       cp.amount, cp.coefficient_used,
       round(coalesce((
           SELECT sum(o.commission)
           FROM egorov_food."order" o
           WHERE o.courier_id = cp.courier_id
             AND o.status = 'доставлен'
             AND extract(year FROM o.order_timestamp) = cp.year
             AND extract(month FROM o.order_timestamp) = cp.month
       ), 0) * cp.coefficient_used, 2) AS expected_amount
FROM egorov_food.courier_pay cp
ORDER BY cp.year, cp.month, cp.courier_id
LIMIT 20;
```

Ожидается: `amount = expected_amount` в каждой строке. Если `courier_pay` пока пустая, сначала выполни `CALL egorov_food.courier_salary();`.

### 4.9. Повторный вызов генератора

```sql
DO $$
BEGIN
    FOR i IN 1..10 LOOP
        CALL egorov_food.insert_test_data(10);
    END LOOP;
END
$$;
```

Ожидается: без ошибок. Данные добавляются или заменяются в соответствии с реализацией и документированным решением проекта.

---

## 5. Проверки бизнес-правил

### 5.1. Все основные FK валидны (нет orphan-записей)

```sql
SELECT 'order_structure -> order' AS fk, count(*) AS orphans
FROM egorov_food.order_structure os
LEFT JOIN egorov_food."order" o ON os.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'order_structure -> product', count(*)
FROM egorov_food.order_structure os
LEFT JOIN egorov_food.product p ON os.product_id = p.product_id
WHERE p.product_id IS NULL
UNION ALL
SELECT 'payment -> order', count(*)
FROM egorov_food.payment pmt
LEFT JOIN egorov_food."order" o ON pmt.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'review -> order', count(*)
FROM egorov_food.review r
LEFT JOIN egorov_food."order" o ON r.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'courier_pay -> courier', count(*)
FROM egorov_food.courier_pay cp
LEFT JOIN egorov_food.courier c ON cp.courier_id = c.courier_id
WHERE c.courier_id IS NULL
UNION ALL
SELECT 'client_address -> client', count(*)
FROM egorov_food.client_address ca
LEFT JOIN egorov_food.client c ON ca.client_id = c.client_id
WHERE c.client_id IS NULL
UNION ALL
SELECT 'client_address -> address', count(*)
FROM egorov_food.client_address ca
LEFT JOIN egorov_food.address a ON ca.address_id = a.address_id
WHERE a.address_id IS NULL;
```

Ожидается: все значения `orphans` равны 0.

### 5.2. Минимальная сумма заказа (BR-1.8)

```sql
SELECT count(*) AS invalid_orders
FROM egorov_food."order"
WHERE total_amount < 1000;
```

Ожидается: 0.

### 5.3. Комиссия равна 10% (BR-1.4)

```sql
SELECT count(*) AS invalid_commission
FROM egorov_food."order"
WHERE round(order_amount * 0.10, 2) <> commission;
```

Ожидается: 0.

### 5.4. Итоговая сумма = сумма заказа + комиссия

```sql
SELECT count(*) AS invalid_total
FROM egorov_food."order"
WHERE round(order_amount + commission, 2) <> total_amount;
```

Ожидается: 0.

### 5.5. Доставка не раньше создания (BR-7.13)

```sql
SELECT count(*) AS invalid_delivery_dates
FROM egorov_food."order"
WHERE delivery_timestamp IS NOT NULL
  AND delivery_timestamp < order_timestamp;
```

Ожидается: 0.

### 5.6. Адрес доставки принадлежит клиенту (BR-7.4)

```sql
SELECT count(*) AS invalid_delivery_addresses
FROM egorov_food."order" o
LEFT JOIN egorov_food.client_address ca
  ON ca.client_id = o.client_id
 AND ca.address_id = o.address_id
WHERE ca.client_id IS NULL;
```

Ожидается: 0.

### 5.7. Блюда в заказе принадлежат ресторану заказа (BR-7.3)

```sql
SELECT count(DISTINCT os.order_id) AS invalid_orders
FROM egorov_food.order_structure os
JOIN egorov_food."order" o ON os.order_id = o.order_id
JOIN egorov_food.product p ON os.product_id = p.product_id
WHERE p.restaurant_id <> o.restaurant_id;
```

Ожидается: 0.

### 5.8. Ровно одна успешная оплата на заказ (BR-8.1)

```sql
SELECT order_id, count(*) AS successful_payments
FROM egorov_food.payment
WHERE status = 'успех'
GROUP BY order_id
HAVING count(*) <> 1;
```

Ожидается: пустой результат.

### 5.9. Сумма оплаты совпадает с суммой заказа (BR-8.4)

```sql
SELECT count(*) AS invalid_payments
FROM egorov_food.payment p
JOIN egorov_food."order" o ON o.order_id = p.order_id
WHERE p.amount <> o.total_amount;
```

Ожидается: 0.

### 5.10. Нет дубликатов в client_address (BR-2.5)

```sql
SELECT client_id, address_id, count(*)
FROM egorov_food.client_address
GROUP BY client_id, address_id
HAVING count(*) > 1;
```

Ожидается: пустой результат.

### 5.11. Нет дубликатов в order_structure (BR-7.16)

```sql
SELECT order_id, product_id, count(*)
FROM egorov_food.order_structure
GROUP BY order_id, product_id
HAVING count(*) > 1;
```

Ожидается: пустой результат.

### 5.12. Время работы ресторана корректно (BR-4.4)

```sql
SELECT count(*) AS invalid_restaurants
FROM egorov_food.restaurant
WHERE work_end <= work_start;
```

Ожидается: 0.

### 5.13. Дата увольнения не раньше даты найма (BR-6.3)

```sql
SELECT count(*) AS invalid_couriers
FROM egorov_food.courier
WHERE dismissal_date IS NOT NULL
  AND dismissal_date < hire_date;
```

Ожидается: 0.

### 5.14. Рейтинг блюда соответствует отзывам (BR-9.6)

```sql
SELECT p.product_id, p.rating,
       (SELECT round(avg(r.rating), 2)
        FROM egorov_food.review r
        WHERE r.entity_type = 'блюдо'
          AND r.entity_id = p.product_id) AS expected_rating
FROM egorov_food.product p
WHERE p.rating IS NOT NULL
ORDER BY p.product_id
LIMIT 20;
```

Ожидается: `rating = expected_rating`.

---

## 6. Функции и процедуры

### 6.1. add_product — успешное добавление

```sql
SELECT count(*) AS before_count FROM egorov_food.product;

DO $$
DECLARE
    v_rest_id uuid;
    v_cat_id  uuid;
BEGIN
    SELECT restaurant_id INTO v_rest_id FROM egorov_food.restaurant LIMIT 1;
    SELECT product_category_id INTO v_cat_id FROM egorov_food.product_category LIMIT 1;

    CALL egorov_food.add_product(
        p_restaurant_id => v_rest_id,
        p_product_category_id => v_cat_id,
        p_name => 'Тестовое блюдо',
        p_price => 250,
        p_rating => 4.5,
        p_status => 'доступно',
        p_description => 'Описание'
    );
END $$;

SELECT count(*) AS after_count FROM egorov_food.product;
```

Ожидается: `after_count = before_count + 1`. 

### 6.2. add_product — несуществующий ресторан

Проверка намеренно должна завершиться ошибкой с понятным сообщением.
```sql
DO $$
DECLARE
    v_cat_id uuid;
BEGIN
    SELECT product_category_id INTO v_cat_id FROM egorov_food.product_category LIMIT 1;

    CALL egorov_food.add_product(
        p_restaurant_id => '00000000-0000-0000-0000-000000000000',  -- несуществующий ресторан
        p_product_category_id => v_cat_id,
        p_name => 'Тестовое блюдо',
        p_price => 250,
        p_rating => 4.5,
        p_status => 'доступно',
        p_description => 'Описание'
    );
END $$;
```

Ожидается: контролируемая ошибка, а не успешное добавление.

### 6.3. rating_change — пересчёт рейтинга

```sql
BEGIN;

-- =========================================================
-- 1. Создание временных таблиц для хранения тестовых ID
-- =========================================================

CREATE TEMP TABLE test_refs (
    client_id UUID,
    client_address_id UUID,
    restaurant_address_id UUID,
    courier_id UUID,
    category_id UUID,
    restaurant_id UUID,
    product_id UUID
);

CREATE TEMP TABLE test_orders (
    order_id UUID
);

CREATE TEMP TABLE test_reviews (
    review_id UUID,
    review_rating NUMERIC(2,1)
);


-- =========================================================
-- 2. Создание клиента
-- =========================================================

INSERT INTO egorov_food.client (
    login,
    password,
    phone_number
)
VALUES (
    'rating_test_client',
    md5('rating_test_password'),
    '+79991110001'
)
RETURNING client_id;


-- =========================================================
-- 3. Создание адресов
-- =========================================================

INSERT INTO egorov_food.address (
    street,
    house_number,
    apartment_office
)
VALUES (
    'Тестовая улица клиента',
    '10',
    '15'
)
RETURNING address_id;


INSERT INTO egorov_food.address (
    street,
    house_number,
    apartment_office
)
VALUES (
    'Тестовая улица ресторана',
    '20',
    NULL
)
RETURNING address_id;


-- Сохраняем созданные идентификаторы

INSERT INTO test_refs (
    client_id,
    client_address_id,
    restaurant_address_id
)
SELECT
    c.client_id,
    a1.address_id,
    a2.address_id
FROM egorov_food.client c
CROSS JOIN egorov_food.address a1
CROSS JOIN egorov_food.address a2
WHERE c.login = 'rating_test_client'
  AND a1.street = 'Тестовая улица клиента'
  AND a2.street = 'Тестовая улица ресторана';


-- =========================================================
-- 4. Связь клиента с адресом
-- =========================================================

INSERT INTO egorov_food.client_address (
    client_id,
    address_id
)
SELECT
    client_id,
    client_address_id
FROM test_refs;


-- =========================================================
-- 5. Создание курьера
-- =========================================================

INSERT INTO egorov_food.courier (
    fio,
    phone_number,
    status,
    hire_date,
    dismissal_date,
    coefficient
)
VALUES (
    'Тестовый курьер',
    '+79991110002',
    'свободен',
    CURRENT_DATE - 30,
    NULL,
    0.1
);


-- =========================================================
-- 6. Создание категории
-- =========================================================

INSERT INTO egorov_food.product_category (
    product_category_name
)
VALUES (
    'Тестовая категория рейтинга'
);


-- =========================================================
-- 7. Создание ресторана
-- =========================================================

INSERT INTO egorov_food.restaurant (
    restaurant_name,
    address_id,
    description,
    work_start,
    work_end,
    company_details,
    rating,
    status
)
SELECT
    'Тестовый ресторан рейтинга',
    restaurant_address_id,
    'Ресторан для проверки триггера rating_change',
    TIME '09:00',
    TIME '22:00',
    'Тестовые реквизиты',
    NULL,
    'активен'
FROM test_refs;


-- =========================================================
-- 8. Создание блюда
-- =========================================================

INSERT INTO egorov_food.product (
    product_name,
    product_category_id,
    price,
    restaurant_id,
    photo_url,
    rating,
    status,
    description
)
SELECT
    'Тестовое блюдо rating_change',
    pc.product_category_id,
    1000.00,
    r.restaurant_id,
    NULL,
    NULL,
    'доступно',
    'Блюдо для проверки автоматического пересчёта рейтинга'
FROM egorov_food.product_category pc
CROSS JOIN egorov_food.restaurant r
WHERE pc.product_category_name = 'Тестовая категория рейтинга'
  AND r.restaurant_name = 'Тестовый ресторан рейтинга';


-- =========================================================
-- 9. Сохраняем идентификаторы остальных объектов
-- =========================================================

UPDATE test_refs
SET
    courier_id = (
        SELECT courier_id
        FROM egorov_food.courier
        WHERE fio = 'Тестовый курьер'
    ),
    category_id = (
        SELECT product_category_id
        FROM egorov_food.product_category
        WHERE product_category_name = 'Тестовая категория рейтинга'
    ),
    restaurant_id = (
        SELECT restaurant_id
        FROM egorov_food.restaurant
        WHERE restaurant_name = 'Тестовый ресторан рейтинга'
    ),
    product_id = (
        SELECT product_id
        FROM egorov_food.product
        WHERE product_name = 'Тестовое блюдо rating_change'
    );


-- =========================================================
-- 10. Создание трёх заказов
-- =========================================================

INSERT INTO egorov_food."order" (
    courier_id,
    client_id,
    address_id,
    restaurant_id,
    order_timestamp,
    delivery_timestamp,
    order_amount,
    commission,
    total_amount,
    status,
    pay_status,
    description
)
SELECT
    tr.courier_id,
    tr.client_id,
    tr.client_address_id,
    tr.restaurant_id,
    LOCALTIMESTAMP - INTERVAL '1 day',
    LOCALTIMESTAMP - INTERVAL '1 day' + INTERVAL '30 minutes',
    1000.00,
    100.00,
    1100.00,
    'доставлен',
    'оплачен',
    'Тестовый заказ для проверки рейтинга'
FROM test_refs tr
CROSS JOIN generate_series(1, 3);


-- Сохраняем ID заказов

INSERT INTO test_orders (order_id)
SELECT o.order_id
FROM egorov_food."order" o
JOIN test_refs tr
    ON o.client_id = tr.client_id
WHERE o.description = 'Тестовый заказ для проверки рейтинга'
ORDER BY o.order_id;


-- =========================================================
-- 11. Добавление блюд в состав заказов
-- =========================================================

INSERT INTO egorov_food.order_structure (
    order_id,
    product_id,
    quantity
)
SELECT
    o.order_id,
    tr.product_id,
    1.000
FROM test_orders o
CROSS JOIN test_refs tr;


-- =========================================================
-- 12. Создание успешных оплат
-- =========================================================

INSERT INTO egorov_food.payment (
    order_id,
    payment_type,
    amount,
    transaction_id,
    transaction_timestamp,
    status
)
SELECT
    o.order_id,
    'карта',
    1100.00,
    'rating_test_' || o.order_id::text,
    LOCALTIMESTAMP,
    'успех'
FROM test_orders o;


-- =========================================================
-- 13. ПРОВЕРКА №1 — добавление трёх отзывов
-- =========================================================

-- Ожидаемые рейтинги: 3, 4, 5

WITH inserted_reviews AS (
    INSERT INTO egorov_food.review (
        client_id,
        review_timestamp,
        entity_id,
        entity_type,
        order_id,
        description,
        photo_url,
        rating
    )
    SELECT
        tr.client_id,
        LOCALTIMESTAMP,
        tr.product_id,
        'блюдо',
        o.order_id,
        'Тестовый отзыв для rating_change',
        NULL,
        v.rating
    FROM (
        SELECT
            order_id,
            ROW_NUMBER() OVER (ORDER BY order_id) AS rn
        FROM test_orders
    ) o
    CROSS JOIN test_refs tr
    JOIN (
        VALUES
            (1, 3.0::NUMERIC(2,1)),
            (2, 4.0::NUMERIC(2,1)),
            (3, 5.0::NUMERIC(2,1))
    ) v(rn, rating)
        ON v.rn = o.rn
    RETURNING review_id, rating
)
INSERT INTO test_reviews
SELECT review_id, rating
FROM inserted_reviews;


-- Проверяем результат INSERT

SELECT
    p.product_name,
    p.rating AS actual_rating,
    ROUND(AVG(r.rating), 2) AS expected_rating,
    CASE
        WHEN p.rating = ROUND(AVG(r.rating), 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END AS test_result
FROM egorov_food.product p
JOIN test_refs tr
    ON tr.product_id = p.product_id
JOIN egorov_food.review r
    ON r.entity_id = p.product_id
   AND r.entity_type = 'блюдо'
GROUP BY p.product_id, p.product_name, p.rating;


-- =========================================================
-- 14. ПРОВЕРКА №2 — удаление одного отзыва
-- =========================================================

-- Удаляем отзыв с рейтингом 3

DELETE FROM egorov_food.review
WHERE review_id = (
    SELECT review_id
    FROM test_reviews
    WHERE review_rating = 3.0
);


-- Проверяем результат DELETE

SELECT
    p.product_name,
    p.rating AS actual_rating,
    ROUND(AVG(r.rating), 2) AS expected_rating,
    CASE
        WHEN p.rating = ROUND(AVG(r.rating), 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END AS test_result
FROM egorov_food.product p
JOIN test_refs tr
    ON tr.product_id = p.product_id
JOIN egorov_food.review r
    ON r.entity_id = p.product_id
   AND r.entity_type = 'блюдо'
GROUP BY p.product_id, p.product_name, p.rating;


-- =========================================================
-- 15. ПРОВЕРКА №3 — удаление всех оставшихся отзывов
-- =========================================================

DELETE FROM egorov_food.review
WHERE review_id IN (
    SELECT review_id
    FROM test_reviews
);


-- Проверяем результат DELETE всех отзывов

SELECT
    p.product_name,
    p.rating AS actual_rating,
    CASE
        WHEN p.rating IS NULL
        THEN 'PASS'
        ELSE 'FAIL'
    END AS test_result
FROM egorov_food.product p
JOIN test_refs tr
    ON tr.product_id = p.product_id;


-- =========================================================
-- 16. Итоговая проверка триггера
-- =========================================================

SELECT
    trigger_name,
    event_manipulation,
    action_timing,
    action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'egorov_food'
  AND event_object_table = 'review'
  AND trigger_name = 'trg_rating_change'
ORDER BY event_manipulation;


-- =========================================================
-- 17. Откат тестовых данных
-- =========================================================

ROLLBACK;
```

### 6.4. get_statistic()

```sql
SELECT * FROM egorov_food.get_statistic();
```

Ожидается:
- колонки `restaurant_name`, `best_product_name`, `total_amount`, `avg_amount`, `best_user`;
- одна строка на ресторан;
- `best_user` — `client.login`;
- учитываются доставленные заказы.

### 6.5. courier_salary()

```sql
BEGIN;

SET LOCAL search_path = egorov_food, exts, public;

-- ------------------------------------------------------------
-- 1. Создаём тестового клиента
-- ------------------------------------------------------------

INSERT INTO egorov_food.client (
    client_id,
    login,
    password,
    phone_number
)
VALUES (
    'a0000000-0000-0000-0000-000000000001',
    'food107_test_client',
    md5('food107_test_password'),
    '+70000000001'
);

-- ------------------------------------------------------------
-- 2. Создаём адрес клиента и адрес ресторана
-- ------------------------------------------------------------

INSERT INTO egorov_food.address (
    address_id,
    street,
    house_number,
    apartment_office
)
VALUES
(
    'a0000000-0000-0000-0000-000000000002',
    'Тестовая улица',
    '10',
    '15'
),
(
    'a0000000-0000-0000-0000-000000000006',
    'Тестовый проспект',
    '20',
    NULL
);

-- ВАЖНО:
-- Связываем клиента с адресом доставки.
-- Без этой записи INSERT в таблицу order нарушит fk_order_client_address.

INSERT INTO egorov_food.client_address (
    client_id,
    address_id
)
VALUES (
    'a0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000002'
);

-- ------------------------------------------------------------
-- 3. Создаём ресторан
-- ------------------------------------------------------------

INSERT INTO egorov_food.restaurant (
    restaurant_id,
    restaurant_name,
    address_id,
    description,
    work_start,
    work_end,
    company_details,
    rating,
    status
)
VALUES (
    'a0000000-0000-0000-0000-000000000003',
    'FOOD-107 Тестовый ресторан',
    'a0000000-0000-0000-0000-000000000006',
    'Ресторан для проверки расчёта зарплаты курьеров',
    '09:00',
    '22:00',
    'Тестовые реквизиты FOOD-107',
    5.00,
    'активен'
);

-- ------------------------------------------------------------
-- 4. Создаём пять тестовых курьеров
-- ------------------------------------------------------------

INSERT INTO egorov_food.courier (
    courier_id,
    fio,
    phone_number,
    status,
    hire_date,
    dismissal_date,
    coefficient
)
VALUES
(
    'a0000000-0000-0000-0000-000000000010',
    'FOOD107 Курьер 0 заказов',
    '+70000000101',
    'свободен',
    CURRENT_DATE -  INTERVAL '1 year',
    NULL,
    0.5
),
(
    'a0000000-0000-0000-0000-000000000011',
    'FOOD107 Курьер 151 заказ',
    '+70000000102',
    'свободен',
    CURRENT_DATE - INTERVAL '1 year',
    NULL,
    0.1
),
(
    'a0000000-0000-0000-0000-000000000012',
    'FOOD107 Курьер 251 заказ',
    '+70000000103',
    'занят',
    CURRENT_DATE - INTERVAL '1 year',
    NULL,
    0.2
),
(
    'a0000000-0000-0000-0000-000000000013',
    'FOOD107 Курьер 501 заказ',
    '+70000000104',
    'на_доставке',
    CURRENT_DATE - INTERVAL '1 year',
    NULL,
    0.3
),
(
    'a0000000-0000-0000-0000-000000000014',
    'FOOD107 Уволенный курьер',
    '+70000000105',
    'уволен',
    CURRENT_DATE - INTERVAL '1 year',
    CURRENT_DATE - 1,
    0.3
);

-- ------------------------------------------------------------
-- 5. Создаём заказы
-- ------------------------------------------------------------
-- Каждый доставленный заказ:
-- order_amount = 1000
-- commission   = 100
-- total_amount = 1100
--
-- Все заказы созданы в текущем календарном месяце.
-- ------------------------------------------------------------

-- 5.1. Курьер без доставленных заказов.
-- Добавляем заказы с разными статусами, чтобы проверить,
-- что они не учитываются при расчёте зарплаты.

INSERT INTO egorov_food."order" (
    courier_id,
    client_id,
    address_id,
    restaurant_id,
    order_timestamp,
    delivery_timestamp,
    order_amount,
    commission,
    total_amount,
    status,
    description
)
VALUES
(
    'a0000000-0000-0000-0000-000000000010',
    'a0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000002',
    'a0000000-0000-0000-0000-000000000003',
    date_trunc('month', CURRENT_DATE) + INTERVAL '1 day',
    NULL, 1000, 100, 1100,
    'создан',
    'FOOD-107 Проверка статуса создан'
),
(
    'a0000000-0000-0000-0000-000000000010',
    'a0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000002',
    'a0000000-0000-0000-0000-000000000003',
    date_trunc('month', CURRENT_DATE) + INTERVAL '1 day',
    NULL, 1000, 100, 1100,
    'готовится',
    'FOOD-107 Проверка статуса готовится'
),
(
    'a0000000-0000-0000-0000-000000000010',
    'a0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000002',
    'a0000000-0000-0000-0000-000000000003',
    date_trunc('month', CURRENT_DATE) + INTERVAL '1 day',
    NULL, 1000, 100, 1100,
    'в_доставке',
    'FOOD-107 Проверка статуса в доставке'
),
(
    'a0000000-0000-0000-0000-000000000010',
    'a0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000002',
    'a0000000-0000-0000-0000-000000000003',
    date_trunc('month', CURRENT_DATE) + INTERVAL '1 day',
    NULL, 1000, 100, 1100,
    'отменён',
    'FOOD-107 Проверка статуса отменён'
);

-- 5.2. Для остальных курьеров создаём доставленные заказы.
-- 151, 251, 501 и 151 заказ соответственно.

INSERT INTO egorov_food."order" (
    courier_id,
    client_id,
    address_id,
    restaurant_id,
    order_timestamp,
    delivery_timestamp,
    order_amount,
    commission,
    total_amount,
    status,
    description
)
SELECT
    v.courier_id,
    'a0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000002',
    'a0000000-0000-0000-0000-000000000003',
    date_trunc('month', CURRENT_DATE) + INTERVAL '1 day',
    date_trunc('month', CURRENT_DATE) + INTERVAL '1 day 30 minutes',
    1000,
    100,
    1100,
    'доставлен',
    'FOOD-107 Тестовый доставленный заказ'
FROM (
    VALUES
        ('a0000000-0000-0000-0000-000000000011'::UUID, 151),
        ('a0000000-0000-0000-0000-000000000012'::UUID, 251),
        ('a0000000-0000-0000-0000-000000000013'::UUID, 501),
        ('a0000000-0000-0000-0000-000000000014'::UUID, 151)
) AS v(courier_id, order_count)
CROSS JOIN LATERAL generate_series(1, v.order_count);

-- ------------------------------------------------------------
-- 6. Проверяем исходные данные до вызова процедуры
-- ------------------------------------------------------------

SELECT
    c.fio,
    c.coefficient AS initial_coefficient,
    COUNT(o.order_id) FILTER (
        WHERE o.status = 'доставлен'
    ) AS delivered_orders,
    COALESCE(
        SUM(o.commission) FILTER (
            WHERE o.status = 'доставлен'
        ),
        0
    ) AS delivered_commission
FROM egorov_food.courier c
LEFT JOIN egorov_food."order" o
    ON o.courier_id = c.courier_id
   AND o.order_timestamp >= date_trunc('month', CURRENT_DATE)
   AND o.order_timestamp < date_trunc('month', CURRENT_DATE)
                              + INTERVAL '1 month'
WHERE c.courier_id BETWEEN
    'a0000000-0000-0000-0000-000000000010'::UUID
    AND
    'a0000000-0000-0000-0000-000000000014'::UUID
GROUP BY c.courier_id, c.fio, c.coefficient
ORDER BY c.courier_id;

-- ------------------------------------------------------------
-- 7. Первый запуск FOOD-107
-- ------------------------------------------------------------

CALL egorov_food.courier_salary();

-- ------------------------------------------------------------
-- 8. Проверяем рассчитанную зарплату и новые коэффициенты
-- ------------------------------------------------------------

SELECT
    c.fio,
    cp.amount AS calculated_salary,
    cp.coefficient_used AS coefficient_for_current_month,
    c.coefficient AS coefficient_for_next_month
FROM egorov_food.courier_pay cp
JOIN egorov_food.courier c
    ON c.courier_id = cp.courier_id
WHERE cp.year = EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER
  AND cp.month = EXTRACT(MONTH FROM CURRENT_DATE)::INTEGER
  AND c.courier_id BETWEEN
      'a0000000-0000-0000-0000-000000000010'::UUID
      AND
      'a0000000-0000-0000-0000-000000000014'::UUID
ORDER BY c.courier_id;

-- Ожидаемые результаты:
--
-- Курьер 0 заказов:
--   зарплата = 0
--   коэффициент текущего месяца = 0.5
--   коэффициент следующего месяца = 0.1
--
-- Курьер 151 заказ:
--   зарплата = 1510
--   коэффициент текущего месяца = 0.1
--   коэффициент следующего месяца = 0.2
--
-- Курьер 251 заказ:
--   зарплата = 5020
--   коэффициент текущего месяца = 0.2
--   коэффициент следующего месяца = 0.3
--
-- Курьер 501 заказ:
--   зарплата = 15030
--   коэффициент текущего месяца = 0.3
--   коэффициент следующего месяца = 0.5
--
-- Уволенный курьер:
--   зарплата = 4530
--   коэффициент текущего месяца = 0.3
--   коэффициент следующего месяца остаётся 0.3


-- ------------------------------------------------------------
-- 9. Второй запуск FOOD-107
-- Проверяем повторный запуск и отсутствие дублирования выплат
-- ------------------------------------------------------------

CALL egorov_food.courier_salary();

SELECT
    c.fio,
    COUNT(cp.courier_id) AS payment_records,
    MAX(cp.amount) AS salary_after_second_call,
    MAX(cp.coefficient_used) AS coefficient_used,
    c.coefficient AS coefficient_for_next_month
FROM egorov_food.courier c
LEFT JOIN egorov_food.courier_pay cp
    ON cp.courier_id = c.courier_id
   AND cp.year = EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER
   AND cp.month = EXTRACT(MONTH FROM CURRENT_DATE)::INTEGER
WHERE c.courier_id BETWEEN
    'a0000000-0000-0000-0000-000000000010'::UUID
    AND
    'a0000000-0000-0000-0000-000000000014'::UUID
GROUP BY c.courier_id, c.fio, c.coefficient
ORDER BY c.courier_id;

-- Для каждого курьера payment_records должен быть равен 1.
-- Суммы зарплаты и coefficient_used должны совпадать с первым запуском.


-- ------------------------------------------------------------
-- 10. Откатываем все тестовые изменения
-- ------------------------------------------------------------

ROLLBACK;
```


---

## 7. FOOD-108 — представление how_much_money

### 7.1. Колонки и типы

```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'egorov_food'
  AND table_name = 'how_much_money'
ORDER BY ordinal_position;
```

Ожидается ровно 8 колонок:
- `year_month` — `text`;
- `sum_no_commission`, `sum_with_commission`, `commission`, `prev_commission`, `commission_diff`, `courier_pay`, `net_profit` — `numeric`.

### 7.2. Содержимое отчёта

```sql
SELECT *
FROM egorov_food.how_much_money
ORDER BY year_month;
```

Ожидается: все месяцы от первого до последнего месяца с доставленными заказами, без пропусков.

### 7.3. Месяцы без заказов

```sql
SELECT year_month
FROM egorov_food.how_much_money
WHERE sum_no_commission = 0;
```

Ожидается: если внутри диапазона есть месяцы без доставленных заказов, они присутствуют с нулевыми суммами.

### 7.4. Проверка арифметики отчёта

```sql
SELECT *
FROM egorov_food.how_much_money
WHERE commission <> sum_with_commission - sum_no_commission
   OR net_profit <> commission - courier_pay
   OR (prev_commission IS NOT NULL
       AND commission_diff <> commission - prev_commission);
```

Ожидается: пустой результат.

### 7.5. Проверка первого месяца

```sql
SELECT *
FROM egorov_food.how_much_money
ORDER BY year_month
LIMIT 1;
```

Ожидается: `prev_commission IS NULL`, `commission_diff IS NULL`.

---

## 8. FOOD-109 — права inspector

### 8.1. Права на схему

```sql
SELECT
    n.nspname AS schema_name,
    has_schema_privilege('inspector', n.oid, 'USAGE') AS has_usage,
    has_schema_privilege('inspector', n.oid, 'CREATE') AS has_create
FROM pg_catalog.pg_namespace n
WHERE n.nspname = 'egorov_food';
```

Ожидается: `has_usage = true`, `has_create = true`.

### 8.2. Права на таблицы

```sql
SELECT table_name,
       string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE grantee = 'inspector'
  AND table_schema = 'egorov_food'
GROUP BY table_name
ORDER BY table_name;
```

Ожидается: права `SELECT`, `INSERT`, `UPDATE`, `DELETE` на таблицы схемы.

### 8.3. Чтение information_schema

```sql
SELECT count(*)
FROM information_schema.tables
WHERE table_schema = 'egorov_food';
```


### 8.4. Чтение pg_catalog

```sql
SELECT count(*)
FROM pg_catalog.pg_tables
WHERE schemaname = 'egorov_food';
```

### 8.5. Проверка USAGE на exts

```sql
SELECT has_schema_privilege('inspector', 'exts', 'USAGE') AS exts_usage;
```

Ожидается: `true`.

### 8.6. Вызовы под inspector

Подключись непосредственно пользователем `inspector` и выполни:

```sql
CALL egorov_food.erase_test_data();
CALL egorov_food.insert_test_data(10);
CALL egorov_food.courier_salary();
SELECT * FROM egorov_food.get_statistic();
SELECT * FROM egorov_food.how_much_money LIMIT 5;
```

Ожидается: без `permission denied`.

---

## 9. FOOD-110 — проверка backup

Проверка backup считается пройденной, если:
1. архив `foodexpress_egorov.backup` создан в custom-формате `pg_dump -Fc`;
2. в архив включена схема `egorov_food` (а не все схемы базы);
3. архив восстанавливается в новую пустую БД командой из раздела 1;
4. после восстановления применение `grants.sql` создаёт роль `inspector` и выдаёт ей права;
5. под `inspector` выполняются `CALL egorov_food.insert_test_data(10);` и `SELECT * FROM egorov_food.get_statistic();`.

---

## 10. Оптимизация get_statistic (BR-11.8)

### 10.1. План с коррелированными подзапросами

```sql
EXPLAIN ANALYZE
SELECT c.courier_id,
       (SELECT count(*)
        FROM egorov_food."order" o
        WHERE o.courier_id = c.courier_id
          AND o.status = 'доставлен') AS delivered_count,
       (SELECT coalesce(sum(o.commission), 0)
        FROM egorov_food."order" o
        WHERE o.courier_id = c.courier_id
          AND o.status = 'доставлен') AS commission_sum
FROM egorov_food.courier c;
```

Ожидается: два SubPlan, каждый обращается к таблице `order`.

### 10.2. План с одним JOIN

```sql
EXPLAIN ANALYZE
SELECT c.courier_id,
       count(o.order_id) AS delivered_count,
       coalesce(sum(o.commission), 0) AS commission_sum
FROM egorov_food.courier c
LEFT JOIN egorov_food."order" o
  ON o.courier_id = c.courier_id
 AND o.status = 'доставлен'
GROUP BY c.courier_id;
```

Ожидается: один JOIN и один проход по `order`; сравни фактическое время с пунктом 10.1.

### 10.3. План get_statistic

```sql
EXPLAIN ANALYZE
SELECT * FROM egorov_food.get_statistic();
```

Ожидается: функция выполняется без ошибок; план соответствует оптимизированной реализации из проекта.

---

## 11. Финальная очистка и повторная генерация

### 11.1. Очистить все тестовые данные

```sql
CALL egorov_food.erase_test_data();
```

### 11.2. Проверить, что таблицы пустые

```sql
SELECT 'client' AS tbl, count(*) FROM egorov_food.client
UNION ALL SELECT 'courier', count(*) FROM egorov_food.courier
UNION ALL SELECT 'product_category', count(*) FROM egorov_food.product_category
UNION ALL SELECT 'restaurant', count(*) FROM egorov_food.restaurant
UNION ALL SELECT 'address', count(*) FROM egorov_food.address
UNION ALL SELECT 'product', count(*) FROM egorov_food.product
UNION ALL SELECT 'order', count(*) FROM egorov_food."order"
UNION ALL SELECT 'review', count(*) FROM egorov_food.review
UNION ALL SELECT 'payment', count(*) FROM egorov_food.payment
UNION ALL SELECT 'order_structure', count(*) FROM egorov_food.order_structure
UNION ALL SELECT 'client_address', count(*) FROM egorov_food.client_address
UNION ALL SELECT 'courier_pay', count(*) FROM egorov_food.courier_pay
ORDER BY tbl;
```

Ожидается: все значения `count` равны 0.

### 11.3. Повторная очистка

```sql
CALL egorov_food.erase_test_data();
```

Ожидается: без ошибок.

### 11.4. Повторная генерация

```sql
CALL egorov_food.insert_test_data(10);

SELECT count(*) AS orders_count
FROM egorov_food."order";
```

Ожидается: `orders_count = 50`.

---

## 12. Итоговый чек-лист

| Проверка | Ожидаемый результат | Факт | Вердикт |
|---|---|---|---|
| Восстановление backup под postgres | Без ERROR | | |
| Применение grants.sql | Без ошибок | | |
| Подключение inspector | Успешно | | |
| Схема и таблицы | Все на месте | | |
| UUID, enum, FK | Соответствуют проекту | | |
| insert_test_data(10) | Выполняется | | |
| Бизнес-правила | Нет нарушений | | |
| add_product | Добавляет 1 продукт | | |
| rating_change | Пересчитывает рейтинг | | |
| get_statistic | Корректная статистика | | |
| courier_salary | Выплаты и коэффициенты корректны | | |
| how_much_money | 8 колонок, месяцы и суммы корректны | | |
| Права inspector | Нет permission denied | | |
| erase_test_data | Все тестовые таблицы пусты | | |
| Повторная генерация | 50 заказов | | |

Вердикт по проекту: `OK` / `FAIL: ...`
