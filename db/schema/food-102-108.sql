
BEGIN;
-- FOOD-102: генератор тестовых данных для схемы egorov_food.
-- Повторный вызов добавляет новую порцию данных, не очищая старые записи.

CREATE OR REPLACE PROCEDURE egorov_food.insert_test_data(value integer)
LANGUAGE plpgsql
AS $$
DECLARE
    v_clients uuid[] := ARRAY[]::uuid[];
    v_couriers uuid[] := ARRAY[]::uuid[];
    v_categories uuid[] := ARRAY[]::uuid[];
    v_restaurants uuid[] := ARRAY[]::uuid[];
    v_addresses uuid[] := ARRAY[]::uuid[];
    v_products uuid[] := ARRAY[]::uuid[];
    v_orders uuid[] := ARRAY[]::uuid[];
    v_order_products uuid[] := ARRAY[]::uuid[];
    v_order_restaurants uuid[] := ARRAY[]::uuid[];
    v_order_clients uuid[] := ARRAY[]::uuid[];
    v_order_couriers uuid[] := ARRAY[]::uuid[];
    v_order_months date[] := ARRAY[]::date[];
    v_order_commissions numeric[] := ARRAY[]::numeric[];
    v_order_totals numeric[] := ARRAY[]::numeric[];
    v_order_timestamps timestamp[] := ARRAY[]::timestamp[];
    v_order_addresses uuid[] := ARRAY[]::uuid[];
    v_id uuid;
    v_hire_date date;
    v_dismissal date;
    v_status egorov_food.courier_status;
    v_review_type egorov_food.review_entity_type;
    v_payment_type egorov_food.payment_type;
    v_i integer;
    v_j integer;
    v_client_idx integer;
    v_restaurant_idx integer;
    v_product_idx integer;
    v_courier_idx integer;
    v_month_start date;
    v_month_end date;
    v_order_ts timestamp;
    v_amount numeric(12,2);
    v_commission numeric(12,2);
    v_total numeric(12,2);
    v_quantity numeric(10,3);
    v_coefficient numeric(2,1);
    v_next_coefficient numeric(2,1);
    v_deliveries integer;
    v_commission_sum numeric(14,2);
    v_last_month date;
BEGIN
    IF value IS NULL OR value <= 0 THEN
        RAISE EXCEPTION 'Параметр value должен быть положительным целым числом';
    END IF;

    -- 1. Клиенты: value строк.
    FOR v_i IN 1..value LOOP
        INSERT INTO egorov_food.client (login, password, phone_number)
        VALUES (
            'client_' || md5(random()::text || clock_timestamp()::text),
            md5(random()::text),
            '+7' || lpad(floor(random() * 10000000000)::bigint::text, 10, '0')
        ) RETURNING client_id INTO v_id;
        v_clients := array_append(v_clients, v_id);
    END LOOP;

    -- 2. Курьеры: минимум один гарантированно работающий (BR-6.6).
    FOR v_i IN 1..value LOOP
        -- Курьеры наняты до начала генерируемого периода и остаются работающими:
        -- это позволяет согласованно назначать им доставки во всех шести месяцах.
        v_hire_date := current_date - 180;
        IF v_i = 1 THEN
            v_status := 'свободен'::egorov_food.courier_status;
        ELSE
            -- Берём только первые три значения enum: все они означают работающего курьера.
            v_status := (enum_range(NULL::egorov_food.courier_status))[
                floor(random() * 3)::integer + 1
            ];
        END IF;
        v_dismissal := NULL;
        INSERT INTO egorov_food.courier
            (fio, phone_number, status, hire_date, dismissal_date, coefficient)
        VALUES (
            'Курьер ' || v_i || ' ' || substring(md5(random()::text), 1, 8),
            '+7' || lpad(floor(random() * 10000000000)::bigint::text, 10, '0'),
            v_status, v_hire_date, v_dismissal, 0.1
        ) RETURNING courier_id INTO v_id;
        v_couriers := array_append(v_couriers, v_id);
    END LOOP;

    -- 3. Категории: value строк.
    FOR v_i IN 1..value LOOP
        INSERT INTO egorov_food.product_category(product_category_name)
        VALUES ('Категория ' || v_i || '_' || substring(md5(random()::text), 1, 6))
        RETURNING product_category_id INTO v_id;
        v_categories := array_append(v_categories, v_id);
    END LOOP;

    -- 4. Адреса: value * 5. Первые value предназначены ресторанам.
    FOR v_i IN 1..(value * 5) LOOP
        INSERT INTO egorov_food.address(street, house_number, apartment_office)
        VALUES (
            'Улица ' || v_i || ' ' || substring(md5(random()::text), 1, 6),
            (1 + floor(random() * 200))::integer::text,
            CASE WHEN random() < 0.35 THEN NULL
                 ELSE (1 + floor(random() * 300))::integer::text END
        ) RETURNING address_id INTO v_id;
        v_addresses := array_append(v_addresses, v_id);
    END LOOP;

    -- 5. Рестораны: каждому выделен отдельный адрес из первых value адресов.
    FOR v_i IN 1..value LOOP
        INSERT INTO egorov_food.restaurant
            (restaurant_name, address_id, description, work_start, work_end,
             company_details, rating, status)
        VALUES (
            'Ресторан ' || v_i || '_' || substring(md5(random()::text), 1, 6),
            v_addresses[v_i],
            'Тестовое описание ресторана ' || v_i,
            TIME '09:00', TIME '22:00',
            'ИНН ' || lpad(floor(random() * 10000000000)::bigint::text, 10, '0') ||
            '; ОГРН ' || lpad(floor(random() * 10000000000000)::bigint::text, 13, '0'),
            NULL,
            (enum_range(NULL::egorov_food.restaurant_status))[
                floor(random() * cardinality(enum_range(NULL::egorov_food.restaurant_status)))::integer + 1
            ]
        ) RETURNING restaurant_id INTO v_id;
        v_restaurants := array_append(v_restaurants, v_id);
    END LOOP;

    -- 6. Связи клиент—адрес: каждому клиенту назначаем его четыре адреса.
    FOR v_i IN 1..value LOOP
        FOR v_j IN 1..4 LOOP
            INSERT INTO egorov_food.client_address(client_id, address_id)
            VALUES (v_clients[v_i], v_addresses[value + (v_i - 1) * 4 + v_j]);
        END LOOP;
    END LOOP;

    -- 7. Блюда: по пять блюд на каждый ресторан, всего value * 5.
    FOR v_i IN 1..(value * 5) LOOP
        v_restaurant_idx := ((v_i - 1) / 5)::integer + 1;
        INSERT INTO egorov_food.product
            (product_name, product_category_id, price, restaurant_id,
             photo_url, rating, status, description)
        VALUES (
            'Блюдо ' || v_i || '_' || substring(md5(random()::text), 1, 6),
            v_categories[((v_i - 1) % value) + 1],
            round((1200 + random() * 3800)::numeric, 2),
            v_restaurants[v_restaurant_idx],
            CASE WHEN random() < 0.25 THEN NULL
                 ELSE 'https://cdn.foodexpress.ru/test/' || md5(random()::text) || '.jpg' END,
            NULL,
            (enum_range(NULL::egorov_food.product_status))[
                floor(random() * cardinality(enum_range(NULL::egorov_food.product_status)))::integer + 1
            ],
            'Тестовое описание блюда ' || v_i
        ) RETURNING product_id INTO v_id;
        v_products := array_append(v_products, v_id);
    END LOOP;

    -- 8. Заказы: value * 5. Все создаваемые заказы доставлены.
    --    Для каждого заказа берём блюдо того же ресторана и адрес его клиента.
    FOR v_i IN 1..(value * 5) LOOP
        v_client_idx := ((v_i - 1) % value) + 1;
        v_restaurant_idx := ((v_i - 1) % value) + 1;
        v_product_idx := (v_restaurant_idx - 1) * 5 + ((v_i - 1) / value)::integer + 1;
        v_courier_idx := ((v_i - 1) % value) + 1;
        v_quantity := 1.000;

        -- Равномерно распределяем заказы по шести последним календарным месяцам.
        v_month_start := (date_trunc('month', current_date)::date -
                          ((5 - ((v_i - 1) % 6)) * interval '1 month'))::date;
        v_month_end := LEAST((v_month_start + interval '1 month - 1 day')::date, current_date);
        v_order_ts := LEAST(
            (v_month_start + floor(random() * (v_month_end - v_month_start + 1))::integer)
              + time '10:00' + (floor(random() * 36000)::integer * interval '1 second'),
            localtimestamp - interval '3 hours'
        );

        SELECT price * v_quantity INTO v_amount
        FROM egorov_food.product WHERE product_id = v_products[v_product_idx];
        v_amount := round(v_amount, 2);
        v_commission := round(v_amount * 0.10, 2);
        v_total := v_amount + v_commission;

        INSERT INTO egorov_food."order"
            (courier_id, client_id, address_id, restaurant_id, order_timestamp,
             delivery_timestamp, order_amount, commission, total_amount,
             status, pay_status, description)
        VALUES (
            v_couriers[v_courier_idx], v_clients[v_client_idx],
            v_addresses[value + (v_client_idx - 1) * 4 + 1],
            v_restaurants[v_restaurant_idx], v_order_ts,
            v_order_ts + (15 + floor(random() * 105)::integer) * interval '1 minute',
            v_amount, v_commission, v_total,
            'доставлен'::egorov_food.order_status,
            'оплачен'::egorov_food.order_pay_status,
            'Тестовый заказ ' || v_i
        ) RETURNING order_id INTO v_id;

        v_orders := array_append(v_orders, v_id);
        v_order_products := array_append(v_order_products, v_products[v_product_idx]);
        v_order_restaurants := array_append(v_order_restaurants, v_restaurants[v_restaurant_idx]);
        v_order_clients := array_append(v_order_clients, v_clients[v_client_idx]);
        v_order_couriers := array_append(v_order_couriers, v_couriers[v_courier_idx]);
        v_order_months := array_append(v_order_months, date_trunc('month', v_order_ts)::date);
        v_order_commissions := array_append(v_order_commissions, v_commission);
        v_order_totals := array_append(v_order_totals, v_total);
        v_order_timestamps := array_append(v_order_timestamps, v_order_ts);
        v_order_addresses := array_append(v_order_addresses,
            v_addresses[value + (v_client_idx - 1) * 4 + 1]);
    END LOOP;

    -- 9. Позиции заказов: одна уникальная позиция на каждый заказ.
    FOR v_i IN 1..cardinality(v_orders) LOOP
        INSERT INTO egorov_food.order_structure(order_id, product_id, quantity)
        VALUES (v_orders[v_i], v_order_products[v_i], 1.000);
    END LOOP;

    -- 10. Оплаты: одна успешная попытка на заказ, сумма = total_amount.
    FOR v_i IN 1..cardinality(v_orders) LOOP
        v_payment_type := (enum_range(NULL::egorov_food.payment_type))[
            floor(random() * cardinality(enum_range(NULL::egorov_food.payment_type)))::integer + 1
        ];
        INSERT INTO egorov_food.payment
            (order_id, payment_type, amount, transaction_id, transaction_timestamp, status)
        VALUES (
            v_orders[v_i], v_payment_type, v_order_totals[v_i],
            'test_tx_' || md5(random()::text || clock_timestamp()::text),
            v_order_timestamps[v_i] + interval '1 minute',
            'успех'::egorov_food.payment_status
        );
    END LOOP;

    -- 11. Отзывы: по одному отзыву на заказ. Объект всегда заказан этим клиентом.
    FOR v_i IN 1..cardinality(v_orders) LOOP
        v_review_type := (enum_range(NULL::egorov_food.review_entity_type))[
            floor(random() * cardinality(enum_range(NULL::egorov_food.review_entity_type)))::integer + 1
        ];
        INSERT INTO egorov_food.review
            (client_id, review_timestamp, entity_id, entity_type, order_id,
             description, photo_url, rating)
        VALUES (
            v_order_clients[v_i], LEAST(v_order_timestamps[v_i] + interval '2 hours', localtimestamp),
            CASE v_review_type
                WHEN 'блюдо' THEN v_order_products[v_i]
                WHEN 'ресторан' THEN v_order_restaurants[v_i]
                ELSE v_orders[v_i]
            END,
            v_review_type, v_orders[v_i],
            'Тестовый отзыв ' || v_i || ': ' || substring(md5(random()::text), 1, 12),
            CASE WHEN random() < 0.30 THEN NULL
                 ELSE 'https://cdn.foodexpress.ru/reviews/' || md5(random()::text) || '.jpg' END,
            (floor(random() * 5)::integer + 1)::numeric(2,1)
        );
    END LOOP;

    -- 12. История выплат за шесть последних календарных месяцев.
    --     Для каждого курьера и каждого месяца создаётся ровно одна строка.
    --     coefficient_used применяется к комиссиям доставленных заказов.
    --     Новый коэффициент определяется по числу доставок и действует далее.
    FOR v_i IN 1..value LOOP
        v_coefficient := 0.1;
        FOR v_j IN 0..5 LOOP
            v_month_start := (date_trunc('month', current_date)::date -
                              ((5 - v_j) * interval '1 month'))::date;
            SELECT count(*), COALESCE(sum(o.commission), 0)
              INTO v_deliveries, v_commission_sum
              FROM egorov_food."order" o
             WHERE o.courier_id = v_couriers[v_i]
               AND o.status = 'доставлен'
               AND o.order_timestamp >= v_month_start::timestamp
               AND o.order_timestamp < (v_month_start + interval '1 month');

            INSERT INTO egorov_food.courier_pay
                (year, month, courier_id, amount, coefficient_used)
            VALUES (
                extract(year FROM v_month_start)::integer,
                extract(month FROM v_month_start)::integer,
                v_couriers[v_i],
                round(v_coefficient * v_commission_sum, 2),
                v_coefficient
            );

            IF v_deliveries <= 150 THEN
                v_next_coefficient := 0.1;
            ELSIF v_deliveries <= 250 THEN
                v_next_coefficient := 0.2;
            ELSIF v_deliveries <= 500 THEN
                v_next_coefficient := 0.3;
            ELSE
                v_next_coefficient := 0.5;
            END IF;
            v_coefficient := v_next_coefficient;
        END LOOP;

        -- После последнего месяца coefficient хранит коэффициент следующего месяца.
        UPDATE egorov_food.courier
           SET coefficient = v_coefficient
         WHERE courier_id = v_couriers[v_i]
           AND status <> 'уволен';
    END LOOP;
END;
$$;


-- ============================================================
-- FOOD-103. Удаление тестовых данных
-- ============================================================

CREATE OR REPLACE PROCEDURE egorov_food.erase_test_data()
LANGUAGE plpgsql
AS $$
BEGIN
    /*
      Удаляем дочерние записи раньше родительских:
      review/payment/order_structure -> order;
      product -> restaurant/product_category;
      client_address -> client/address.
      DELETE, а не DROP/TRUNCATE: структура БД остаётся нетронутой.
    */

    DELETE FROM egorov_food.review;
    DELETE FROM egorov_food.payment;
    DELETE FROM egorov_food.order_structure;
    DELETE FROM egorov_food."order";

    DELETE FROM egorov_food.courier_pay;

    DELETE FROM egorov_food.product;
    DELETE FROM egorov_food.restaurant;

    DELETE FROM egorov_food.client_address;

    DELETE FROM egorov_food.client;
    DELETE FROM egorov_food.address;
    DELETE FROM egorov_food.courier;
    DELETE FROM egorov_food.product_category;
END;
$$;


-- ============================================================
-- FOOD-104. Добавление блюда
-- ============================================================

CREATE OR REPLACE PROCEDURE egorov_food.add_product(
    IN p_restaurant_id UUID,
    IN p_product_category_id UUID,
    IN p_name TEXT,
    IN p_price NUMERIC(12,2),
    IN p_rating NUMERIC(3,2),
    IN p_status egorov_food.product_status,
    IN p_description TEXT,
    IN p_photo_url TEXT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Проверяем ссылки отдельно, чтобы сообщить понятную причину ошибки.
    IF NOT EXISTS (
        SELECT 1
        FROM egorov_food.restaurant r
        WHERE r.restaurant_id = p_restaurant_id
    ) THEN
        RAISE EXCEPTION
            'Нельзя добавить блюдо: ресторан с id % не существует',
            p_restaurant_id
            USING ERRCODE = '23503';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM egorov_food.product_category pc
        WHERE pc.product_category_id = p_product_category_id
    ) THEN
        RAISE EXCEPTION
            'Нельзя добавить блюдо: категория с id % не существует',
            p_product_category_id
            USING ERRCODE = '23503';
    END IF;

    -- Проверки бизнес-правил и CHECK до выполнения INSERT.
    IF p_name IS NULL OR length(trim(p_name)) = 0 THEN
        RAISE EXCEPTION 'Название блюда не должно быть пустым'
            USING ERRCODE = '23514';
    END IF;

    IF p_price IS NULL OR p_price < 0 THEN
        RAISE EXCEPTION 'Цена блюда должна быть неотрицательной'
            USING ERRCODE = '23514';
    END IF;

    IF p_rating IS NOT NULL AND p_rating NOT BETWEEN 0 AND 5 THEN
        RAISE EXCEPTION 'Рейтинг блюда должен быть от 0 до 5 либо NULL'
            USING ERRCODE = '23514';
    END IF;

    IF p_status IS NULL THEN
        RAISE EXCEPTION 'Статус блюда должен быть указан'
            USING ERRCODE = '23502';
    END IF;

    IF p_description IS NULL OR length(trim(p_description)) = 0 THEN
        RAISE EXCEPTION 'Описание блюда не должно быть пустым'
            USING ERRCODE = '23514';
    END IF;

    -- product_id не передаём: используется DEFAULT exts.uuid_generate_v4().
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
    VALUES (
        p_name,
        p_product_category_id,
        p_price,
        p_restaurant_id,
        p_photo_url,
        p_rating,
        p_status,
        p_description
    );
END;
$$;


-- ============================================================
-- FOOD-105. Автоматический пересчёт рейтинга
-- ============================================================

CREATE OR REPLACE FUNCTION egorov_food.rating_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_old_type egorov_food.review_entity_type;
    v_old_id   UUID;
    v_new_type egorov_food.review_entity_type;
    v_new_id   UUID;
BEGIN
    /*
      Для UPDATE могут измениться:
      - только rating;
      - entity_type;
      - entity_id;
      - одновременно несколько атрибутов.
      Поэтому сохраняем обе стороны изменения.
    */

    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        v_old_type := OLD.entity_type;
        v_old_id   := OLD.entity_id;
    END IF;

    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        v_new_type := NEW.entity_type;
        v_new_id   := NEW.entity_id;
    END IF;

    -- Пересчитываем прежнюю сущность при DELETE или переносе отзыва.
    IF v_old_type = 'блюдо'
       AND (
           TG_OP = 'DELETE'
           OR v_old_type IS DISTINCT FROM v_new_type
           OR v_old_id IS DISTINCT FROM v_new_id
       )
    THEN
        UPDATE egorov_food.product p
           SET rating = (
               SELECT AVG(r.rating)
               FROM egorov_food.review r
               WHERE r.entity_type = 'блюдо'
                 AND r.entity_id = v_old_id
           )
         WHERE p.product_id = v_old_id;

    ELSIF v_old_type = 'ресторан'
       AND (
           TG_OP = 'DELETE'
           OR v_old_type IS DISTINCT FROM v_new_type
           OR v_old_id IS DISTINCT FROM v_new_id
       )
    THEN
        UPDATE egorov_food.restaurant rest
           SET rating = (
               SELECT AVG(r.rating)
               FROM egorov_food.review r
               WHERE r.entity_type = 'ресторан'
                 AND r.entity_id = v_old_id
           )
         WHERE rest.restaurant_id = v_old_id;
    END IF;

    -- Пересчитываем новую сущность при INSERT и при любом UPDATE,
    -- в том числе когда изменился только rating, а цель отзыва прежняя.
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        IF v_new_type = 'блюдо' THEN
            UPDATE egorov_food.product p
               SET rating = (
                   SELECT AVG(r.rating)
                   FROM egorov_food.review r
                   WHERE r.entity_type = 'блюдо'
                     AND r.entity_id = v_new_id
               )
             WHERE p.product_id = v_new_id;

        ELSIF v_new_type = 'ресторан' THEN
            UPDATE egorov_food.restaurant rest
               SET rating = (
                   SELECT AVG(r.rating)
                   FROM egorov_food.review r
                   WHERE r.entity_type = 'ресторан'
                     AND r.entity_id = v_new_id
               )
             WHERE rest.restaurant_id = v_new_id;
        END IF;
    END IF;

    /*
      Для entity_type = 'заказ' намеренно ничего не обновляем:
      у заказа нет агрегированного поля rating (BR-9.6).
    */

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_rating_change ON egorov_food.review;

CREATE TRIGGER trg_rating_change
AFTER INSERT OR UPDATE OR DELETE
ON egorov_food.review
FOR EACH ROW
EXECUTE FUNCTION egorov_food.rating_change();


-- ============================================================
-- FOOD-106. Статистика по ресторанам
-- ============================================================

CREATE OR REPLACE FUNCTION egorov_food.get_statistic()
RETURNS TABLE (
    restaurant_name VARCHAR(100),
    best_product_name VARCHAR(150),
    total_amount NUMERIC,
    avg_amount NUMERIC,
    best_user VARCHAR(50)
)
LANGUAGE SQL
AS $$
    WITH
    -- Один общий набор доставленных заказов.
    delivered_orders AS MATERIALIZED (
        SELECT
            o.order_id,
            o.restaurant_id,
            o.client_id,
            o.total_amount
        FROM egorov_food."order" o
        WHERE o.status = 'доставлен'
    ),

    -- Сумма проданного количества каждого блюда в ресторане.
    product_totals AS (
        SELECT
            d.restaurant_id,
            p.product_id,
            p.product_name,
            SUM(os.quantity) AS total_quantity
        FROM delivered_orders d
        JOIN egorov_food.order_structure os
          ON os.order_id = d.order_id
        JOIN egorov_food.product p
          ON p.product_id = os.product_id
        GROUP BY
            d.restaurant_id,
            p.product_id,
            p.product_name
    ),

    -- DISTINCT ON оставляет лидера; random() разрешает равенство случайно.
    best_products AS (
        SELECT DISTINCT ON (pt.restaurant_id)
            pt.restaurant_id,
            pt.product_name
        FROM product_totals pt
        ORDER BY
            pt.restaurant_id,
            pt.total_quantity DESC,
            random()
    ),

    -- Количество доставленных заказов каждого клиента в ресторане.
    user_totals AS (
        SELECT
            d.restaurant_id,
            d.client_id,
            c.login,
            COUNT(*) AS delivered_order_count
        FROM delivered_orders d
        JOIN egorov_food.client c
          ON c.client_id = d.client_id
        GROUP BY
            d.restaurant_id,
            d.client_id,
            c.login
    ),

    best_users AS (
        SELECT DISTINCT ON (ut.restaurant_id)
            ut.restaurant_id,
            ut.login
        FROM user_totals ut
        ORDER BY
            ut.restaurant_id,
            ut.delivered_order_count DESC,
            random()
    ),

    restaurant_totals AS (
        SELECT
            d.restaurant_id,
            SUM(d.total_amount) AS total_amount,
            AVG(d.total_amount) AS avg_amount
        FROM delivered_orders d
        GROUP BY d.restaurant_id
    )

    SELECT
        rest.restaurant_name,
        bp.product_name AS best_product_name,
        COALESCE(rt.total_amount, 0::NUMERIC) AS total_amount,
        rt.avg_amount,
        bu.login AS best_user
    FROM egorov_food.restaurant rest
    LEFT JOIN restaurant_totals rt
      ON rt.restaurant_id = rest.restaurant_id
    LEFT JOIN best_products bp
      ON bp.restaurant_id = rest.restaurant_id
    LEFT JOIN best_users bu
      ON bu.restaurant_id = rest.restaurant_id
    ORDER BY rest.restaurant_name;
$$;


-- ============================================================
-- FOOD-107. Ежемесячный расчёт зарплаты курьеров
-- ============================================================

CREATE OR REPLACE PROCEDURE egorov_food.courier_salary()
LANGUAGE plpgsql
AS $$
DECLARE
    v_month_start DATE := date_trunc('month', CURRENT_DATE)::DATE;
    v_next_month  DATE := (date_trunc('month', CURRENT_DATE)
                           + INTERVAL '1 month')::DATE;
    v_year        INTEGER := EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER;
    v_month       INTEGER := EXTRACT(MONTH FROM CURRENT_DATE)::INTEGER;
BEGIN
    /*
      В расчёт входят доставленные заказы, созданные в текущем календарном
      месяце. Это соответствует проверке согласованности courier_pay
      в шаблоне проекта (C.8), где месяц определяется по order_timestamp.
    */

    WITH courier_month_stats AS (
        SELECT
            c.courier_id,
            -- При повторном запуске берём уже зафиксированный коэффициент
            -- этого месяца, а не новый коэффициент, назначенный на следующий.
            COALESCE(cp.coefficient_used, c.coefficient) AS coefficient_used,
            COUNT(o.order_id)::INTEGER AS delivered_count,
            COALESCE(SUM(o.commission), 0::NUMERIC) AS commission_sum
        FROM egorov_food.courier c
        LEFT JOIN egorov_food.courier_pay cp
          ON cp.courier_id = c.courier_id
         AND cp.year = v_year
         AND cp.month = v_month
        LEFT JOIN egorov_food."order" o
          ON o.courier_id = c.courier_id
         AND o.status = 'доставлен'
         AND o.order_timestamp >= v_month_start
         AND o.order_timestamp < v_next_month
        GROUP BY c.courier_id, c.coefficient, cp.coefficient_used
    )
    INSERT INTO egorov_food.courier_pay AS cp_target (
        year,
        month,
        courier_id,
        amount,
        coefficient_used
    )
    SELECT
        v_year,
        v_month,
        cms.courier_id,
        ROUND(cms.coefficient_used * cms.commission_sum, 2),
        cms.coefficient_used
    FROM courier_month_stats cms
    ON CONFLICT (year, month, courier_id)
    DO UPDATE SET
        amount = EXCLUDED.amount,
        -- Коэффициент текущего месяца уже был зафиксирован при первом запуске.
        -- Повторный запуск не должен подменять его коэффициентом следующего месяца.
        coefficient_used = cp_target.coefficient_used;

    -- Новый коэффициент применяется только со следующего месяца.
    -- Уволенным курьерам выплата выше уже рассчитана, но коэффициент не меняем.
    WITH courier_month_stats AS (
        SELECT
            c.courier_id,
            COUNT(o.order_id)::INTEGER AS delivered_count
        FROM egorov_food.courier c
        LEFT JOIN egorov_food."order" o
          ON o.courier_id = c.courier_id
         AND o.status = 'доставлен'
         AND o.order_timestamp >= v_month_start
         AND o.order_timestamp < v_next_month
        GROUP BY c.courier_id
    )
    UPDATE egorov_food.courier c
       SET coefficient = CASE
           WHEN cms.delivered_count BETWEEN 0 AND 150 THEN 0.1
           WHEN cms.delivered_count BETWEEN 151 AND 250 THEN 0.2
           WHEN cms.delivered_count BETWEEN 251 AND 500 THEN 0.3
           ELSE 0.5
       END
      FROM courier_month_stats cms
     WHERE cms.courier_id = c.courier_id
       AND c.status <> 'уволен';
END;
$$;


/*
  FOOD-108 — отчёт «сколько денег»
  Проект: egorov_food
  Требование: BR-11.9 — непрерывный ряд месяцев через рекурсивный CTE.
*/

CREATE OR REPLACE VIEW egorov_food.how_much_money AS
WITH RECURSIVE
delivered_month_bounds AS (
    SELECT
        date_trunc('month', MIN(o.order_timestamp))::DATE AS first_month,
        date_trunc('month', MAX(o.order_timestamp))::DATE AS last_month
    FROM egorov_food."order" AS o
    WHERE o.status = 'доставлен'
),
months(year_month_date) AS (
    -- Если доставленных заказов нет, представление возвращает 0 строк.
    SELECT first_month
    FROM delivered_month_bounds
    WHERE first_month IS NOT NULL

    UNION ALL

    SELECT (m.year_month_date + INTERVAL '1 month')::DATE
    FROM months AS m
    CROSS JOIN delivered_month_bounds AS b
    WHERE m.year_month_date < b.last_month
),
orders_by_month AS (
    SELECT
        date_trunc('month', o.order_timestamp)::DATE AS month_date,
        SUM(o.order_amount)::NUMERIC AS sum_no_commission,
        SUM(o.total_amount)::NUMERIC AS sum_with_commission
    FROM egorov_food."order" AS o
    WHERE o.status = 'доставлен'
    GROUP BY date_trunc('month', o.order_timestamp)::DATE
),
courier_pay_by_month AS (
    SELECT
        make_date(cp.year, cp.month, 1) AS month_date,
        SUM(cp.amount)::NUMERIC AS courier_pay
    FROM egorov_food.courier_pay AS cp
    GROUP BY cp.year, cp.month
),
monthly_values AS (
    SELECT
        to_char(m.year_month_date, 'YYYY-MM')::TEXT AS year_month,
        m.year_month_date,
        COALESCE(obm.sum_no_commission, 0::NUMERIC) AS sum_no_commission,
        COALESCE(obm.sum_with_commission, 0::NUMERIC) AS sum_with_commission,
        (
            COALESCE(obm.sum_with_commission, 0::NUMERIC)
            - COALESCE(obm.sum_no_commission, 0::NUMERIC)
        )::NUMERIC AS commission,
        COALESCE(cp.courier_pay, 0::NUMERIC) AS courier_pay
    FROM months AS m
    LEFT JOIN orders_by_month AS obm
      ON obm.month_date = m.year_month_date
    LEFT JOIN courier_pay_by_month AS cp
      ON cp.month_date = m.year_month_date
),
with_previous_month AS (
    SELECT
        mv.*,
        LAG(mv.commission) OVER (ORDER BY mv.year_month_date) AS prev_commission
    FROM monthly_values AS mv
)
SELECT
    year_month,
    sum_no_commission,
    sum_with_commission,
    commission,
    prev_commission,
    CASE
        WHEN prev_commission IS NULL THEN NULL
        ELSE commission - prev_commission
    END::NUMERIC AS commission_diff,
    courier_pay,
    (commission - courier_pay)::NUMERIC AS net_profit
FROM with_previous_month
ORDER BY year_month_date;


	
COMMIT;



