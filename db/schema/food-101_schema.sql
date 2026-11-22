/*
FOOD-101 — физическая схема FoodExpress
PostgreSQL


Порядок:
  1. ENUM;
  2. таблицы без зависимостей;
  3. таблицы со связями;
  4. дополнительные FK/ограничения;
  5. триггеры для межтабличных бизнес-правил.
*/

BEGIN;

--Перед восстановлением
CREATE SCHEMA IF NOT EXISTS exts;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" SCHEMA exts;
--CREATE SCHEMA IF NOT EXISTS egorov_food;

SET LOCAL search_path = egorov_food, exts, public;

-- ============================================================
-- 1. ENUM-типы (BR-11.5)
-- ============================================================

CREATE TYPE egorov_food.restaurant_status AS ENUM (
    'активен',
    'неактивен'
);

CREATE TYPE egorov_food.product_status AS ENUM (
    'доступно',
    'нет_в_наличии',
    'архив'
);

CREATE TYPE egorov_food.courier_status AS ENUM (
    'свободен',
    'занят',
    'на_доставке',
    'уволен'
);

CREATE TYPE egorov_food.order_status AS ENUM (
    'создан',
    'готовится',
    'в_доставке',
    'доставлен',
    'отменён'
);

CREATE TYPE egorov_food.order_pay_status AS ENUM (
    'ожидает',
    'оплачен',
    'ошибка'
);

CREATE TYPE egorov_food.payment_status AS ENUM (
    'успех',
    'ошибка',
    'в_обработке'
);

CREATE TYPE egorov_food.payment_type AS ENUM (
    'карта',
    'наличные',
    'безнал'
);

CREATE TYPE egorov_food.review_entity_type AS ENUM (
    'блюдо',
    'ресторан',
    'заказ'
);

-- ============================================================
-- 2. Таблицы без внешних зависимостей
-- ============================================================

-- 2.1 Клиенты (BR-2.1—BR-2.3, BR-2.6)
CREATE TABLE egorov_food.client (
    client_id UUID PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    login VARCHAR(50) NOT NULL,
    password VARCHAR(32) NOT NULL,
    phone_number CHAR(12) NOT NULL,

    CONSTRAINT uq_client_login UNIQUE (login),
    CONSTRAINT uq_client_phone_number UNIQUE (phone_number),
    CONSTRAINT chk_client_login_not_empty
        CHECK (length(trim(login)) > 0),
    CONSTRAINT chk_client_password_md5_length
        CHECK (length(password) = 32),
    CONSTRAINT chk_client_phone_not_empty
        CHECK (length(trim(phone_number)) > 0)
);

-- 2.2 Адреса (BR-3.1, BR-3.2)
CREATE TABLE egorov_food.address (
    address_id UUID PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    street VARCHAR(150) NOT NULL,
    house_number VARCHAR(20) NOT NULL,
    apartment_office VARCHAR(20),

    CONSTRAINT chk_address_street_not_empty
        CHECK (length(trim(street)) > 0),
    CONSTRAINT chk_address_house_number_not_empty
        CHECK (length(trim(house_number)) > 0),
    CONSTRAINT chk_address_apartment_not_empty
        CHECK (
            apartment_office IS NULL
            OR length(trim(apartment_office)) > 0
        )
);

-- 2.3 Курьеры (BR-6.1—BR-6.5)
CREATE TABLE egorov_food.courier (
    courier_id UUID PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    fio VARCHAR(150) NOT NULL,
    phone_number CHAR(12) NOT NULL,
    status egorov_food.courier_status NOT NULL,
    hire_date DATE NOT NULL,
    dismissal_date DATE,
    coefficient NUMERIC(2,1) NOT NULL DEFAULT 0.1,

    CONSTRAINT chk_courier_fio_not_empty
        CHECK (length(trim(fio)) > 0),
    CONSTRAINT chk_courier_phone_not_empty
        CHECK (length(trim(phone_number)) > 0),
    CONSTRAINT chk_courier_coefficient
        CHECK (coefficient BETWEEN 0.1 AND 0.5),
    CONSTRAINT chk_courier_dismissal_status
        CHECK (
            status <> 'уволен'
            OR dismissal_date IS NOT NULL
        ),
    CONSTRAINT chk_courier_dismissal_after_hire
        CHECK (
            dismissal_date IS NULL
            OR dismissal_date >= hire_date
        )
);

-- 2.4 Категории блюд (BR-5.7)
CREATE TABLE egorov_food.product_category (
    product_category_id UUID PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    product_category_name VARCHAR(100) NOT NULL,

    CONSTRAINT chk_product_category_name_not_empty
        CHECK (length(trim(product_category_name)) > 0)
);

-- ============================================================
-- 3. Таблицы со связями
-- ============================================================

-- 3.1 Связь клиент—адрес M:N (BR-2.4, BR-2.5, BR-3.5)
CREATE TABLE egorov_food.client_address (
    client_id UUID NOT NULL,
    address_id UUID NOT NULL,

    CONSTRAINT pk_client_address PRIMARY KEY (client_id, address_id),
    CONSTRAINT fk_client_address_client
        FOREIGN KEY (client_id)
        REFERENCES egorov_food.client(client_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_client_address_address
        FOREIGN KEY (address_id)
        REFERENCES egorov_food.address(address_id)
        ON DELETE RESTRICT
);

-- 3.2 Рестораны (BR-3.3, BR-4.1—BR-4.5)
CREATE TABLE egorov_food.restaurant (
    restaurant_id UUID PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    restaurant_name VARCHAR(100) NOT NULL,
    address_id UUID NOT NULL,
    description TEXT NOT NULL,
    work_start TIME NOT NULL,
    work_end TIME NOT NULL,
    company_details TEXT NOT NULL,
    rating NUMERIC(3,2),
    status egorov_food.restaurant_status NOT NULL,

    CONSTRAINT uq_restaurant_address UNIQUE (address_id),
    CONSTRAINT fk_restaurant_address
        FOREIGN KEY (address_id)
        REFERENCES egorov_food.address(address_id)
        ON DELETE RESTRICT,
    CONSTRAINT chk_restaurant_name_not_empty
        CHECK (length(trim(restaurant_name)) > 0),
    CONSTRAINT chk_restaurant_description_not_empty
        CHECK (length(trim(description)) > 0),
    CONSTRAINT chk_restaurant_company_details_not_empty
        CHECK (length(trim(company_details)) > 0),
    CONSTRAINT chk_restaurant_work_time
        CHECK (work_end > work_start),
    CONSTRAINT chk_restaurant_rating
        CHECK (rating IS NULL OR rating BETWEEN 0 AND 5)
);

-- 3.3 Ежемесячные выплаты курьерам (BR-10.2—BR-10.4)
CREATE TABLE egorov_food.courier_pay (
    year INTEGER NOT NULL,
    month INTEGER NOT NULL,
    courier_id UUID NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    coefficient_used NUMERIC(2,1) NOT NULL,

    CONSTRAINT pk_courier_pay PRIMARY KEY (year, month, courier_id),
    CONSTRAINT fk_courier_pay_courier
        FOREIGN KEY (courier_id)
        REFERENCES egorov_food.courier(courier_id)
        ON DELETE RESTRICT,
    CONSTRAINT chk_courier_pay_year CHECK (year > 0),
    CONSTRAINT chk_courier_pay_month CHECK (month BETWEEN 1 AND 12),
    CONSTRAINT chk_courier_pay_amount CHECK (amount >= 0),
    CONSTRAINT chk_courier_pay_coefficient
        CHECK (coefficient_used BETWEEN 0.1 AND 0.5)
);

-- 3.4 Блюда (BR-5.1—BR-5.6)
CREATE TABLE egorov_food.product (
    product_id UUID PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    product_name VARCHAR(150) NOT NULL,
    product_category_id UUID NOT NULL,
    price NUMERIC(12,2) NOT NULL,
    restaurant_id UUID NOT NULL,
    photo_url TEXT,
    rating NUMERIC(3,2),
    status egorov_food.product_status NOT NULL,
    description TEXT NOT NULL,

    CONSTRAINT fk_product_category
        FOREIGN KEY (product_category_id)
        REFERENCES egorov_food.product_category(product_category_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_product_restaurant
        FOREIGN KEY (restaurant_id)
        REFERENCES egorov_food.restaurant(restaurant_id)
        ON DELETE RESTRICT,
    CONSTRAINT chk_product_name_not_empty
        CHECK (length(trim(product_name)) > 0),
    CONSTRAINT chk_product_price CHECK (price >= 0),
    CONSTRAINT chk_product_rating
        CHECK (rating IS NULL OR rating BETWEEN 0 AND 5),
    CONSTRAINT chk_product_description_not_empty
        CHECK (length(trim(description)) > 0)
);

-- 3.5 Заказы (BR-7.1—BR-7.13)
CREATE TABLE egorov_food."order" (
    order_id UUID PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    courier_id UUID NOT NULL,
    client_id UUID NOT NULL,
    address_id UUID NOT NULL,
    restaurant_id UUID NOT NULL,
    order_timestamp TIMESTAMP NOT NULL DEFAULT LOCALTIMESTAMP,
    delivery_timestamp TIMESTAMP,
    order_amount NUMERIC(12,2) NOT NULL,
    commission NUMERIC(12,2) NOT NULL,
    total_amount NUMERIC(12,2) NOT NULL,
    status egorov_food.order_status NOT NULL,
    pay_status egorov_food.order_pay_status NOT NULL DEFAULT 'ожидает',
    description TEXT NOT NULL,

    -- Ключ нужен для составного FK из review (клиент должен быть клиентом заказа).
    CONSTRAINT uq_order_order_client UNIQUE (order_id, client_id),

    CONSTRAINT fk_order_courier
        FOREIGN KEY (courier_id)
        REFERENCES egorov_food.courier(courier_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_order_client
        FOREIGN KEY (client_id)
        REFERENCES egorov_food.client(client_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_order_address
        FOREIGN KEY (address_id)
        REFERENCES egorov_food.address(address_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_order_restaurant
        FOREIGN KEY (restaurant_id)
        REFERENCES egorov_food.restaurant(restaurant_id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_order_amount_nonnegative CHECK (order_amount >= 0),
    CONSTRAINT chk_order_commission
        CHECK (commission = round(order_amount * 0.10, 2)),
    CONSTRAINT chk_order_total
        CHECK (total_amount = order_amount + commission),
    CONSTRAINT chk_order_minimum
        CHECK (total_amount >= 1000),
    CONSTRAINT chk_order_delivery_not_before_creation
        CHECK (
            delivery_timestamp IS NULL
            OR delivery_timestamp >= order_timestamp
        ),
    CONSTRAINT chk_order_delivery_timestamp_by_status
        CHECK (
            (status = 'доставлен' AND delivery_timestamp IS NOT NULL)
            OR
            (status <> 'доставлен' AND delivery_timestamp IS NULL)
        ),
    CONSTRAINT chk_order_description_not_empty
        CHECK (length(trim(description)) > 0)
);

-- 3.6 Позиции заказа (BR-7.14—BR-7.16)
CREATE TABLE egorov_food.order_structure (
    order_id UUID NOT NULL,
    product_id UUID NOT NULL,
    quantity NUMERIC(10,3) NOT NULL,

    CONSTRAINT pk_order_structure PRIMARY KEY (order_id, product_id),
    CONSTRAINT fk_order_structure_order
        FOREIGN KEY (order_id)
        REFERENCES egorov_food."order"(order_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_order_structure_product
        FOREIGN KEY (product_id)
        REFERENCES egorov_food.product(product_id)
        ON DELETE RESTRICT,
    CONSTRAINT chk_order_structure_quantity CHECK (quantity > 0)
);

-- 3.7 Попытки оплаты (BR-8.1—BR-8.7)
CREATE TABLE egorov_food.payment (
    payment_id UUID PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    order_id UUID NOT NULL,
    payment_type egorov_food.payment_type NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    transaction_id VARCHAR(150) NOT NULL,
    transaction_timestamp TIMESTAMP NOT NULL DEFAULT LOCALTIMESTAMP,
    status egorov_food.payment_status NOT NULL,

    CONSTRAINT fk_payment_order
        FOREIGN KEY (order_id)
        REFERENCES egorov_food."order"(order_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_payment_transaction_id UNIQUE (transaction_id),
    CONSTRAINT chk_payment_amount_positive CHECK (amount > 0),
    CONSTRAINT chk_payment_transaction_id_not_empty
        CHECK (length(trim(transaction_id)) > 0)
);

-- 3.8 Отзывы (BR-9.1—BR-9.7)
CREATE TABLE egorov_food.review (
    review_id UUID PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    client_id UUID NOT NULL,
    review_timestamp TIMESTAMP NOT NULL DEFAULT LOCALTIMESTAMP,
    entity_id UUID NOT NULL,
    entity_type egorov_food.review_entity_type NOT NULL,
    order_id UUID NOT NULL,
    description TEXT NOT NULL,
    photo_url TEXT,
    rating NUMERIC(2,1) NOT NULL,

    CONSTRAINT fk_review_client
        FOREIGN KEY (client_id)
        REFERENCES egorov_food.client(client_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_review_order_client
        FOREIGN KEY (order_id, client_id)
        REFERENCES egorov_food."order"(order_id, client_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_review_order_entity
        UNIQUE (order_id, entity_type, entity_id),
    CONSTRAINT chk_review_rating CHECK (rating BETWEEN 1 AND 5),
    CONSTRAINT chk_review_description_not_empty
        CHECK (length(trim(description)) > 0)
);

-- ============================================================
-- 4. Дополнительные FK и межтабличные ограничения
-- ============================================================

-- Адрес доставки должен быть привязан именно к клиенту этого заказа (BR-7.4).
ALTER TABLE egorov_food."order"
    ADD CONSTRAINT fk_order_client_address
    FOREIGN KEY (client_id, address_id)
    REFERENCES egorov_food.client_address(client_id, address_id)
    ON DELETE RESTRICT;

-- ============================================================
-- 5. Триггерные проверки межтабличных бизнес-правил
-- ============================================================

-- 5.1 Блюда в заказе должны принадлежать ресторану заказа (BR-7.3).
CREATE OR REPLACE FUNCTION egorov_food.fn_check_order_product_restaurant()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_restaurant UUID;
    v_product_restaurant UUID;
BEGIN
    SELECT restaurant_id
      INTO v_order_restaurant
      FROM egorov_food."order"
     WHERE order_id = NEW.order_id;

    SELECT restaurant_id
      INTO v_product_restaurant
      FROM egorov_food.product
     WHERE product_id = NEW.product_id;

    IF v_order_restaurant IS DISTINCT FROM v_product_restaurant THEN
        RAISE EXCEPTION
            'Блюдо % не принадлежит ресторану заказа %',
            NEW.product_id, NEW.order_id;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_check_order_product_restaurant
BEFORE INSERT OR UPDATE OF order_id, product_id
ON egorov_food.order_structure
FOR EACH ROW
EXECUTE FUNCTION egorov_food.fn_check_order_product_restaurant();

-- 5.2 При изменении ресторана блюда не допускаем нарушения уже созданных заказов (BR-7.3).
CREATE OR REPLACE FUNCTION egorov_food.fn_check_product_restaurant_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.restaurant_id IS DISTINCT FROM OLD.restaurant_id
       AND EXISTS (
            SELECT 1
              FROM egorov_food.order_structure os
              JOIN egorov_food."order" o ON o.order_id = os.order_id
             WHERE os.product_id = OLD.product_id
               AND o.restaurant_id IS DISTINCT FROM NEW.restaurant_id
       )
    THEN
        RAISE EXCEPTION
            'Нельзя изменить ресторан блюда: оно уже входит в заказ другого ресторана';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_check_product_restaurant_update
BEFORE UPDATE OF restaurant_id
ON egorov_food.product
FOR EACH ROW
EXECUTE FUNCTION egorov_food.fn_check_product_restaurant_update();

-- 5.3 При изменении ресторана заказа проверяем все его позиции (BR-7.3).
CREATE OR REPLACE FUNCTION egorov_food.fn_check_order_restaurant_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.restaurant_id IS DISTINCT FROM OLD.restaurant_id
       AND EXISTS (
            SELECT 1
              FROM egorov_food.order_structure os
              JOIN egorov_food.product p ON p.product_id = os.product_id
             WHERE os.order_id = OLD.order_id
               AND p.restaurant_id IS DISTINCT FROM NEW.restaurant_id
       )
    THEN
        RAISE EXCEPTION
            'Нельзя изменить ресторан заказа: состав заказа ему не соответствует';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_check_order_restaurant_update
BEFORE UPDATE OF restaurant_id
ON egorov_food."order"
FOR EACH ROW
EXECUTE FUNCTION egorov_food.fn_check_order_restaurant_update();

-- 5.4 Заказ должен содержать минимум одну позицию (BR-7.14).
CREATE OR REPLACE FUNCTION egorov_food.fn_check_order_has_items()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_id UUID;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_order_id := OLD.order_id;
    ELSE
        v_order_id := NEW.order_id;
    END IF;

    IF EXISTS (
        SELECT 1
          FROM egorov_food."order" o
         WHERE o.order_id = v_order_id
    )
    AND NOT EXISTS (
        SELECT 1
          FROM egorov_food.order_structure os
         WHERE os.order_id = v_order_id
    )
    THEN
        RAISE EXCEPTION 'Заказ % должен содержать хотя бы одну позицию', v_order_id;
    END IF;

    IF TG_OP = 'UPDATE' AND OLD.order_id IS DISTINCT FROM NEW.order_id THEN
        IF EXISTS (
            SELECT 1 FROM egorov_food."order" o WHERE o.order_id = OLD.order_id
        )
        AND NOT EXISTS (
            SELECT 1 FROM egorov_food.order_structure os WHERE os.order_id = OLD.order_id
        )
        THEN
            RAISE EXCEPTION 'После переноса позиции заказ % остался пустым', OLD.order_id;
        END IF;
    END IF;

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_order_must_have_items
AFTER INSERT ON egorov_food."order"
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION egorov_food.fn_check_order_has_items();

CREATE CONSTRAINT TRIGGER trg_order_structure_must_not_become_empty
AFTER UPDATE OR DELETE ON egorov_food.order_structure
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION egorov_food.fn_check_order_has_items();

-- 5.5 Сумма попытки оплаты равна total_amount заказа (BR-8.4).
CREATE OR REPLACE FUNCTION egorov_food.fn_check_payment_amount()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_total NUMERIC(12,2);
BEGIN
    SELECT total_amount
      INTO v_total
      FROM egorov_food."order"
     WHERE order_id = NEW.order_id;

    IF v_total IS NULL OR NEW.amount <> v_total THEN
        RAISE EXCEPTION
            'Сумма платежа должна совпадать с total_amount заказа %',
            NEW.order_id;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_check_payment_amount
BEFORE INSERT OR UPDATE OF order_id, amount
ON egorov_food.payment
FOR EACH ROW
EXECUTE FUNCTION egorov_food.fn_check_payment_amount();

-- 5.6 У каждого заказа ровно одна успешная попытка оплаты (BR-8.1).
-- Проверка отложенная: заказ и его платежи создаются в одной транзакции.
CREATE OR REPLACE FUNCTION egorov_food.fn_check_exactly_one_success_payment()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_id UUID;
    v_success_count INTEGER;
BEGIN
    IF TG_TABLE_NAME = 'order' THEN
        v_order_id := NEW.order_id;
    ELSIF TG_OP = 'DELETE' THEN
        v_order_id := OLD.order_id;
    ELSE
        v_order_id := NEW.order_id;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM egorov_food."order" WHERE order_id = v_order_id
    ) THEN
        RETURN NULL;
    END IF;

    SELECT count(*)
      INTO v_success_count
      FROM egorov_food.payment
     WHERE order_id = v_order_id
       AND status = 'успех';

    IF v_success_count <> 1 THEN
        RAISE EXCEPTION
            'Заказ % должен иметь ровно одну успешную попытку оплаты; найдено: %',
            v_order_id, v_success_count;
    END IF;

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_order_exactly_one_success_payment
AFTER INSERT ON egorov_food."order"
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION egorov_food.fn_check_exactly_one_success_payment();

CREATE CONSTRAINT TRIGGER trg_payment_exactly_one_success
AFTER INSERT OR UPDATE OR DELETE ON egorov_food.payment
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION egorov_food.fn_check_exactly_one_success_payment();

-- 5.7 Агрегированный статус оплаты заказа (BR-7.8, BR-7.9, BR-8.7).
CREATE OR REPLACE FUNCTION egorov_food.fn_refresh_order_pay_status()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_id UUID;
    v_new_status egorov_food.order_pay_status;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_order_id := OLD.order_id;
    ELSE
        v_order_id := NEW.order_id;
    END IF;

    IF EXISTS (
        SELECT 1 FROM egorov_food.payment
         WHERE order_id = v_order_id AND status = 'успех'
    ) THEN
        v_new_status := 'оплачен';
    ELSIF EXISTS (
        SELECT 1 FROM egorov_food.payment
         WHERE order_id = v_order_id
    ) AND NOT EXISTS (
        SELECT 1 FROM egorov_food.payment
         WHERE order_id = v_order_id AND status <> 'ошибка'
    ) THEN
        v_new_status := 'ошибка';
    ELSE
        v_new_status := 'ожидает';
    END IF;

    UPDATE egorov_food."order"
       SET pay_status = v_new_status
     WHERE order_id = v_order_id;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_refresh_order_pay_status
AFTER INSERT OR UPDATE OR DELETE
ON egorov_food.payment
FOR EACH ROW
EXECUTE FUNCTION egorov_food.fn_refresh_order_pay_status();

-- 5.8 Отзыв только на объект, связанный с данным заказом клиента (BR-9.1, BR-9.2).
CREATE OR REPLACE FUNCTION egorov_food.fn_check_review_target()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_valid BOOLEAN := FALSE;
BEGIN
    IF NEW.entity_type = 'блюдо' THEN
        SELECT EXISTS (
            SELECT 1
              FROM egorov_food.order_structure os
             WHERE os.order_id = NEW.order_id
               AND os.product_id = NEW.entity_id
        ) INTO v_valid;

    ELSIF NEW.entity_type = 'ресторан' THEN
        SELECT EXISTS (
            SELECT 1
              FROM egorov_food."order" o
             WHERE o.order_id = NEW.order_id
               AND o.restaurant_id = NEW.entity_id
        ) INTO v_valid;

    ELSIF NEW.entity_type = 'заказ' THEN
        SELECT EXISTS (
            SELECT 1
              FROM egorov_food."order" o
             WHERE o.order_id = NEW.order_id
               AND o.order_id = NEW.entity_id
        ) INTO v_valid;
    END IF;

    IF NOT v_valid THEN
        RAISE EXCEPTION
            'Объект отзыва не относится к указанному заказу клиента';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_check_review_target
BEFORE INSERT OR UPDATE OF client_id, order_id, entity_id, entity_type
ON egorov_food.review
FOR EACH ROW
EXECUTE FUNCTION egorov_food.fn_check_review_target();

-- FOOD-105 отдельно реализует пересчёт product.rating и restaurant.rating
-- при INSERT/UPDATE/DELETE review (BR-9.6, BR-9.7).
-- Здесь поля рейтинга и их диапазоны созданы, но триггер rating_change
-- намеренно не дублируется в тикете FOOD-101.

COMMIT;
