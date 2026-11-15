-- Триггеры (FOOD-101, FOOD-105)
-- Флаг dunaev_food.bulk_load ставит insert_test_data на время своей работы.
-- Пока он включен, триггеры пересчета рейтинга и pay_status ничего не делают.

SET search_path TO dunaev_food, exts;

-- Блюдо должно быть из ресторана заказа (BR-7.3)
CREATE OR REPLACE FUNCTION dunaev_food.order_structure_check()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_restaurant   uuid;
    v_product_restaurant uuid;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE')
       AND (TG_OP = 'DELETE' OR (OLD.order_id, OLD.product_id) IS DISTINCT FROM (NEW.order_id, NEW.product_id))
       AND EXISTS (SELECT 1 FROM dunaev_food.review r
                   WHERE r.order_id = OLD.order_id
                     AND r.entity_type = 'блюдо'
                     AND r.entity_id = OLD.product_id) THEN
        RAISE EXCEPTION 'Нельзя убрать блюдо % из заказа %: на него есть отзыв (BR-9.2)',
            OLD.product_id, OLD.order_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    SELECT o.restaurant_id INTO v_order_restaurant
    FROM dunaev_food."order" o WHERE o.order_id = NEW.order_id;

    SELECT p.restaurant_id INTO v_product_restaurant
    FROM dunaev_food.product p WHERE p.product_id = NEW.product_id;

    IF v_order_restaurant IS NOT NULL AND v_product_restaurant IS NOT NULL
       AND v_order_restaurant <> v_product_restaurant THEN
        RAISE EXCEPTION 'Блюдо % принадлежит другому ресторану, чем заказ % (BR-7.3)',
            NEW.product_id, NEW.order_id
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER order_structure_check_trg
BEFORE INSERT OR UPDATE OR DELETE ON dunaev_food.order_structure
FOR EACH ROW EXECUTE FUNCTION dunaev_food.order_structure_check();

-- Нельзя сменить ресторан заказа, если в нем блюда другого ресторана (BR-7.3)
CREATE OR REPLACE FUNCTION dunaev_food.order_restaurant_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.restaurant_id IS DISTINCT FROM OLD.restaurant_id THEN
        IF EXISTS (SELECT 1
                   FROM dunaev_food.order_structure os
                   JOIN dunaev_food.product p ON p.product_id = os.product_id
                   WHERE os.order_id = NEW.order_id
                     AND p.restaurant_id <> NEW.restaurant_id) THEN
            RAISE EXCEPTION 'Нельзя сменить ресторан заказа %: в нём есть блюда другого ресторана (BR-7.3)',
                NEW.order_id USING ERRCODE = 'check_violation';
        END IF;
        IF EXISTS (SELECT 1 FROM dunaev_food.review r
                   WHERE r.order_id = NEW.order_id
                     AND r.entity_type = 'ресторан'
                     AND r.entity_id <> NEW.restaurant_id) THEN
            RAISE EXCEPTION 'Нельзя сменить ресторан заказа %: есть отзыв на прежний ресторан (BR-9.2)',
                NEW.order_id USING ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER order_restaurant_guard_trg
BEFORE UPDATE OF restaurant_id ON dunaev_food."order"
FOR EACH ROW EXECUTE FUNCTION dunaev_food.order_restaurant_guard();

-- Нельзя перенести блюдо в другой ресторан, если оно уже есть в заказах (BR-7.3)
CREATE OR REPLACE FUNCTION dunaev_food.product_restaurant_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.restaurant_id IS DISTINCT FROM OLD.restaurant_id
       AND EXISTS (SELECT 1
                   FROM dunaev_food.order_structure os
                   JOIN dunaev_food."order" o ON o.order_id = os.order_id
                   WHERE os.product_id = NEW.product_id
                     AND o.restaurant_id <> NEW.restaurant_id) THEN
        RAISE EXCEPTION 'Нельзя сменить ресторан блюда %: оно есть в заказах прежнего ресторана (BR-7.3)',
            NEW.product_id USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER product_restaurant_guard_trg
BEFORE UPDATE OF restaurant_id ON dunaev_food.product
FOR EACH ROW EXECUTE FUNCTION dunaev_food.product_restaurant_guard();

-- Отзыв только на то, что есть в заказе (BR-9.2)
CREATE OR REPLACE FUNCTION dunaev_food.review_validate()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.entity_type = 'заказ' THEN
        IF NEW.entity_id <> NEW.order_id THEN
            RAISE EXCEPTION 'Отзыв на заказ: entity_id (%) должен совпадать с order_id (%) (BR-9.2)',
                NEW.entity_id, NEW.order_id USING ERRCODE = 'foreign_key_violation';
        END IF;
    ELSIF NEW.entity_type = 'ресторан' THEN
        IF NOT EXISTS (SELECT 1 FROM dunaev_food."order" o
                       WHERE o.order_id = NEW.order_id
                         AND o.restaurant_id = NEW.entity_id) THEN
            RAISE EXCEPTION 'Отзыв на ресторан %: заказ % сделан не в этом ресторане (BR-9.2)',
                NEW.entity_id, NEW.order_id USING ERRCODE = 'foreign_key_violation';
        END IF;
    ELSIF NEW.entity_type = 'блюдо' THEN
        IF NOT EXISTS (SELECT 1 FROM dunaev_food.order_structure os
                       WHERE os.order_id = NEW.order_id
                         AND os.product_id = NEW.entity_id) THEN
            RAISE EXCEPTION 'Отзыв на блюдо %: этого блюда нет в заказе % (BR-9.2)',
                NEW.entity_id, NEW.order_id USING ERRCODE = 'foreign_key_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER review_validate_trg
BEFORE INSERT OR UPDATE ON dunaev_food.review
FOR EACH ROW EXECUTE FUNCTION dunaev_food.review_validate();

-- Пересчет рейтинга блюда и ресторана (FOOD-105)
CREATE OR REPLACE FUNCTION dunaev_food.rating_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_types dunaev_food.review_entity_type[] := '{}';
    v_ids   uuid[] := '{}';
    i       integer;
BEGIN
    IF coalesce(current_setting('dunaev_food.bulk_load', true), '') = 'on' THEN
        RETURN NULL;
    END IF;

    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        v_types := v_types || OLD.entity_type;
        v_ids   := v_ids   || OLD.entity_id;
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        v_types := v_types || NEW.entity_type;
        v_ids   := v_ids   || NEW.entity_id;
    END IF;

    FOR i IN 1 .. coalesce(array_length(v_ids, 1), 0) LOOP
        IF v_types[i] = 'блюдо' THEN
            UPDATE dunaev_food.product p
            SET rating = (SELECT round(avg(r.rating), 2)
                          FROM dunaev_food.review r
                          WHERE r.entity_type = 'блюдо' AND r.entity_id = v_ids[i])
            WHERE p.product_id = v_ids[i];
        ELSIF v_types[i] = 'ресторан' THEN
            UPDATE dunaev_food.restaurant rs
            SET rating = (SELECT round(avg(r.rating), 2)
                          FROM dunaev_food.review r
                          WHERE r.entity_type = 'ресторан' AND r.entity_id = v_ids[i])
            WHERE rs.restaurant_id = v_ids[i];
        END IF;
    END LOOP;

    RETURN NULL;
END;
$$;

CREATE TRIGGER rating_change_trg
AFTER INSERT OR UPDATE OR DELETE ON dunaev_food.review
FOR EACH ROW EXECUTE FUNCTION dunaev_food.rating_change();

-- Сумма оплаты равна сумме заказа (BR-8.4)
CREATE OR REPLACE FUNCTION dunaev_food.payment_amount_check()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_total numeric;
BEGIN
    SELECT o.total_amount INTO v_total
    FROM dunaev_food."order" o WHERE o.order_id = NEW.order_id;

    IF v_total IS NOT NULL AND NEW.amount <> v_total THEN
        RAISE EXCEPTION 'Сумма оплаты % не равна сумме заказа % (BR-8.4)', NEW.amount, v_total
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER payment_amount_check_trg
BEFORE INSERT OR UPDATE ON dunaev_food.payment
FOR EACH ROW EXECUTE FUNCTION dunaev_food.payment_amount_check();

-- Статус оплаты заказа по попыткам (BR-8.7)
CREATE OR REPLACE FUNCTION dunaev_food.order_pay_status_refresh()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_orders uuid[] := '{}';
BEGIN
    IF coalesce(current_setting('dunaev_food.bulk_load', true), '') = 'on' THEN
        RETURN NULL;
    END IF;

    IF TG_OP IN ('UPDATE', 'DELETE') THEN v_orders := v_orders || OLD.order_id; END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN v_orders := v_orders || NEW.order_id; END IF;

    UPDATE dunaev_food."order" o
    SET pay_status = CASE
            WHEN s.has_success    THEN 'оплачен'::dunaev_food.order_pay_status
            WHEN s.has_processing THEN 'ожидает'::dunaev_food.order_pay_status
            WHEN s.cnt > 0        THEN 'ошибка'::dunaev_food.order_pay_status
            ELSE 'ожидает'::dunaev_food.order_pay_status
        END
    FROM (
        SELECT ids.order_id,
               coalesce(bool_or(p.status = 'успех'), false)       AS has_success,
               coalesce(bool_or(p.status = 'в_обработке'), false) AS has_processing,
               count(p.payment_id)                                AS cnt
        FROM unnest(v_orders) AS ids(order_id)
        LEFT JOIN dunaev_food.payment p ON p.order_id = ids.order_id
        GROUP BY ids.order_id
    ) s
    WHERE o.order_id = s.order_id;

    RETURN NULL;
END;
$$;

CREATE TRIGGER order_pay_status_refresh_trg
AFTER INSERT OR UPDATE OR DELETE ON dunaev_food.payment
FOR EACH ROW EXECUTE FUNCTION dunaev_food.order_pay_status_refresh();
