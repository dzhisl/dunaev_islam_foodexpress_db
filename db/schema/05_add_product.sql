-- Добавление блюда (FOOD-104)
-- У нового блюда нет отзывов, поэтому rating сохраняется как NULL (BR-9.7).

SET search_path TO dunaev_food, exts;

CREATE OR REPLACE PROCEDURE dunaev_food.add_product(
    p_restaurant_id       uuid,
    p_product_category_id uuid,
    p_name                varchar,
    p_price               numeric,
    p_description         text,
    p_status              dunaev_food.product_status DEFAULT 'доступно',
    p_photo_url           text    DEFAULT NULL,
    p_rating              numeric DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_product_id uuid := exts.uuid_generate_v4();
    v_constraint text;
    v_message    text;
BEGIN
    IF p_restaurant_id IS NULL
       OR NOT EXISTS (SELECT 1 FROM dunaev_food.restaurant r WHERE r.restaurant_id = p_restaurant_id) THEN
        RAISE EXCEPTION 'add_product: ресторан с id % не существует', p_restaurant_id
            USING ERRCODE = 'foreign_key_violation', HINT = 'Проверьте restaurant_id (BR-5.1).';
    END IF;

    IF p_product_category_id IS NULL
       OR NOT EXISTS (SELECT 1 FROM dunaev_food.product_category c
                      WHERE c.product_category_id = p_product_category_id) THEN
        RAISE EXCEPTION 'add_product: категория блюда с id % не существует', p_product_category_id
            USING ERRCODE = 'foreign_key_violation', HINT = 'Проверьте product_category_id (BR-5.1, BR-5.7).';
    END IF;

    IF p_name IS NULL OR btrim(p_name) = '' THEN
        RAISE EXCEPTION 'add_product: название блюда не может быть пустым'
            USING ERRCODE = 'not_null_violation', HINT = 'BR-5.2, BR-11.3.';
    END IF;

    IF p_price IS NULL OR p_price < 0 THEN
        RAISE EXCEPTION 'add_product: цена должна быть неотрицательной, получено %', p_price
            USING ERRCODE = 'check_violation', HINT = 'BR-5.3.';
    END IF;

    IF p_description IS NULL THEN
        RAISE EXCEPTION 'add_product: описание блюда обязательно'
            USING ERRCODE = 'not_null_violation', HINT = 'BR-5.2, BR-11.3.';
    END IF;

    IF p_rating IS NOT NULL THEN
        IF p_rating < 0 OR p_rating > 5 THEN
            RAISE EXCEPTION 'add_product: рейтинг должен быть от 0 до 5, получено %', p_rating
                USING ERRCODE = 'check_violation', HINT = 'BR-5.4.';
        END IF;
        RAISE NOTICE 'add_product: у нового блюда нет отзывов, rating сохранён как NULL (BR-9.7); переданное значение % проигнорировано', p_rating;
    END IF;

    BEGIN
        INSERT INTO dunaev_food.product (product_id, product_name, product_category_id, price,
                                         restaurant_id, photo_url, rating, status, description)
        VALUES (v_product_id, p_name, p_product_category_id, p_price,
                p_restaurant_id, p_photo_url, NULL, coalesce(p_status, 'доступно'), p_description);
    EXCEPTION
        WHEN check_violation OR not_null_violation OR string_data_right_truncation
             OR foreign_key_violation OR unique_violation THEN
            GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME, v_message = MESSAGE_TEXT;
            RAISE EXCEPTION 'add_product: данные блюда нарушают ограничение %: %',
                coalesce(nullif(v_constraint, ''), 'нет'), v_message
                USING ERRCODE = SQLSTATE;
    END;

    RAISE NOTICE 'add_product: добавлено блюдо % (product_id = %)', p_name, v_product_id;
END;
$$;
