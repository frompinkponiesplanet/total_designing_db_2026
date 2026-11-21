# Протокол тестирования FoodExpress

Проект: `egorov_food`  
База для проверки: `foodexpress_check`  
Роль аудитора: `inspector`  
Пароль: `NetoSQL2025`  
Версия PostgreSQL: 15+



## 1. Подготовка и восстановление backup


### 1.1. Создать чистую тестовую базу

Если база уже существует, удалить и создать заново:

```bash
dropdb -U postgres --if-exists foodexpress_check
createdb -U postgres foodexpress_check
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
psql -U inspector -d foodexpress -h localhost
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

Триггер должен пересчитывать рейтинг при `INSERT`, `UPDATE` и `DELETE` в `egorov_food.review`. По проектному backlog проверка: три отзыва на одно блюдо с рейтингами 3, 4, 5 дают среднее 4; удаление одного отзыва даёт среднее 4.5; удаление всех отзывов даёт `NULL`.

Вручную выбери тестовое блюдо и заказ, вставь три тестовых отзыва с уникальными UUID через `exts.uuid_generate_v4()`, затем проверь `egorov_food.product.rating`. Удаляй только созданные тестовые отзывы.

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
SELECT courier_id, coefficient
FROM egorov_food.courier
ORDER BY courier_id;

CALL egorov_food.courier_salary();

SELECT courier_id, coefficient
FROM egorov_food.courier
ORDER BY courier_id;

SELECT year, month, courier_id, amount, coefficient_used
FROM egorov_food.courier_pay
ORDER BY year DESC, month DESC, courier_id
LIMIT 20;
```

Ожидается:
- коэффициент работающих курьеров пересчитан по BR-10.2;
- коэффициент уволенных курьеров не обновляется;
- `courier_pay` содержит запись за текущий месяц.

### 6.6. courier_salary — повторный вызов

```sql
CALL egorov_food.courier_salary();

SELECT count(*) AS current_month_payments
FROM egorov_food.courier_pay
WHERE year = extract(year FROM current_date)
  AND month = extract(month FROM current_date);
```

Ожидается: повторный вызов обновляет существующие записи и не создаёт дубликаты.

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
