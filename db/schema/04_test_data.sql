-- Генерация и удаление тестовых данных (FOOD-102, FOOD-103)
-- Каждый вызов insert_test_data добавляет новую порцию данных.
-- Заказы, отзывы и выплаты связаны только с данными этого же вызова,
-- поэтому старые записи courier_pay остаются правильными.
-- Все даты за последние 6 месяцев.

SET search_path TO dunaev_food, exts;

CREATE OR REPLACE PROCEDURE dunaev_food.insert_test_data(value integer)
LANGUAGE plpgsql
AS $$
DECLARE
    v_n            integer := value;

    -- списки слов для генерации
    v_street_types text[] := ARRAY['ул.', 'пр-т', 'пер.', 'б-р', 'ш.', 'наб.'];
    v_streets      text[] := ARRAY['Ленина', 'Пушкина', 'Гагарина', 'Советская', 'Мира', 'Садовая',
                                   'Лесная', 'Школьная', 'Набережная', 'Молодёжная', 'Центральная',
                                   'Заречная', 'Полевая', 'Солнечная', 'Строителей', 'Победы',
                                   'Кирова', 'Чехова', 'Толстого', 'Горького'];
    v_last_names   text[] := ARRAY['Иванов', 'Петров', 'Сидоров', 'Смирнов', 'Кузнецов', 'Попов',
                                   'Васильев', 'Соколов', 'Михайлов', 'Новиков', 'Фёдоров', 'Морозов'];
    v_first_names  text[] := ARRAY['Алексей', 'Иван', 'Дмитрий', 'Сергей', 'Андрей', 'Максим',
                                   'Артём', 'Никита', 'Михаил', 'Егор', 'Тимур', 'Руслан'];
    v_middle_names text[] := ARRAY['Алексеевич', 'Иванович', 'Дмитриевич', 'Сергеевич', 'Андреевич',
                                   'Петрович', 'Михайлович', 'Олегович', 'Игоревич', 'Романович'];
    v_categories   text[] := ARRAY['Пицца', 'Суши', 'Роллы', 'Бургеры', 'Супы', 'Салаты', 'Десерты',
                                   'Напитки', 'Паста', 'Шаурма', 'Завтраки', 'Гриль', 'Выпечка',
                                   'Вок', 'Закуски'];
    v_rest_kinds   text[] := ARRAY['Кафе', 'Ресторан', 'Бистро', 'Пиццерия', 'Суши-бар', 'Бургерная',
                                   'Столовая', 'Кофейня', 'Трактир', 'Гриль-бар'];
    v_rest_names   text[] := ARRAY['Вкусно', 'Уют', 'Огонёк', 'Сытый кот', 'Тануки', 'Прованс',
                                   'Берёзка', 'Восток', 'Самурай', 'Маэстро', 'Старый город', 'Хинкальная №1'];
    v_dish_adj     text[] := ARRAY['Домашний', 'Острый', 'Сырный', 'Фирменный', 'Классический',
                                   'Овощной', 'Куриный', 'Говяжий', 'Грибной', 'Летний'];
    v_dish_noun    text[] := ARRAY['борщ', 'ролл', 'бургер', 'салат', 'суп', 'пирог', 'сэндвич',
                                   'плов', 'шашлык', 'омлет', 'чизкейк', 'лагман'];
    v_comments     text[] := ARRAY['Позвонить за 10 минут', 'Оставить у двери', 'Без лука',
                                   'Домофон не работает, позвонить', 'Побольше салфеток',
                                   'Без комментариев', 'Не звонить в дверь, спит ребёнок',
                                   'Приборы на двоих'];
    v_review_texts text[] := ARRAY['Очень вкусно, закажу ещё', 'Нормально, но долго везли',
                                   'Порция маленькая', 'Всё горячее и аккуратно упаковано',
                                   'Курьер вежливый', 'Слишком солёно', 'Лучшее в городе',
                                   'Перепутали соус', 'Цена соответствует качеству'];

    -- окно дат: последние 6 месяцев
    v_now          timestamp := localtimestamp;
    v_window_start timestamp := date_trunc('month', localtimestamp) - interval '5 months';

    -- id текущего вызова
    v_category_ids   uuid[] := '{}';
    v_courier_ids    uuid[] := '{}';
    v_courier_hire   date[] := '{}';
    v_courier_dism   date[] := '{}';
    v_rest_addr_ids  uuid[] := '{}';
    v_cli_addr_ids   uuid[] := '{}';
    v_restaurant_ids uuid[] := '{}';
    v_client_ids     uuid[] := '{}';
    v_product_ids    uuid[] := '{}';
    v_product_price  numeric[] := '{}';
    v_order_ids      uuid[] := '{}';

    v_active_statuses dunaev_food.courier_status[] :=
        ARRAY['свободен', 'занят', 'на_доставке']::dunaev_food.courier_status[];
    v_order_statuses  dunaev_food.order_status[]   := enum_range(NULL::dunaev_food.order_status);
    v_rest_statuses   dunaev_food.restaurant_status[] := enum_range(NULL::dunaev_food.restaurant_status);
    v_prod_statuses   dunaev_food.product_status[] := enum_range(NULL::dunaev_food.product_status);
    v_pay_types       dunaev_food.payment_type[]   := enum_range(NULL::dunaev_food.payment_type);

    v_id        uuid;
    v_try       integer;
    i           integer;
    j           integer;
    k           integer;

    -- переменные для заказов
    v_courier_idx   integer;
    v_client_idx    integer;
    v_rest_idx      integer;
    v_lo            timestamp;
    v_hi            timestamp;
    v_ts            timestamp;
    v_status        dunaev_food.order_status;
    v_pay_status    dunaev_food.order_pay_status;
    v_payment_stat  dunaev_food.payment_status;
    v_items_cnt     integer;
    v_offset        integer;
    v_item_idx      integer[];
    v_item_qty      numeric[];
    v_amount        numeric;
    v_total         numeric;

    -- переменные для courier_pay
    v_month_start   timestamp;
    v_cnt           bigint;
    v_sum           numeric;
    v_coef          numeric;
    v_hire          date;
    v_dism          date;
    v_status_c      dunaev_food.courier_status;
BEGIN
    IF v_n IS NULL OR v_n < 1 THEN
        RAISE EXCEPTION 'insert_test_data: value должен быть >= 1, получено %', value;
    END IF;

    PERFORM set_config('dunaev_food.bulk_load', 'on', true);

    -- 1. product_category: value строк, имя уникально (BR-5.7)
    v_try := 0;
    WHILE coalesce(array_length(v_category_ids, 1), 0) < v_n LOOP
        v_try := v_try + 1;
        INSERT INTO dunaev_food.product_category (product_category_id, product_category_name)
        VALUES (exts.uuid_generate_v4(),
                v_categories[1 + floor(random() * array_length(v_categories, 1))::int]
                || CASE WHEN v_try <= array_length(v_categories, 1) THEN ''
                        ELSE ' ' || (1 + floor(random() * 100000))::int::text END)
        ON CONFLICT DO NOTHING
        RETURNING product_category_id INTO v_id;
        IF v_id IS NOT NULL THEN
            v_category_ids := v_category_ids || v_id;
        END IF;
    END LOOP;

    -- 2. courier: value строк; минимум один активный (BR-6.6)
    i := 0;
    WHILE coalesce(array_length(v_courier_ids, 1), 0) < v_n LOOP
        i := coalesce(array_length(v_courier_ids, 1), 0) + 1;
        v_hire := (v_window_start + floor(random() * 15)::int * interval '1 day')::date;
        IF i = 1 OR random() >= 0.2 THEN
            v_status_c := v_active_statuses[1 + floor(random() * 3)::int];
            v_dism := NULL;
        ELSE
            v_status_c := 'уволен';
            -- от hire+30 до сегодня включительно (dismissal >= hire, BR-6.3)
            v_dism := v_hire + 30 + floor(random() * (current_date - (v_hire + 30) + 1))::int;
        END IF;

        INSERT INTO dunaev_food.courier (courier_id, fio, phone_number, status,
                                         hire_date, dismissal_date, coefficient)
        VALUES (exts.uuid_generate_v4(),
                v_last_names[1 + floor(random() * array_length(v_last_names, 1))::int] || ' ' ||
                v_first_names[1 + floor(random() * array_length(v_first_names, 1))::int] || ' ' ||
                v_middle_names[1 + floor(random() * array_length(v_middle_names, 1))::int],
                '+79' || lpad(floor(random() * 1000000000)::bigint::text, 9, '0'),
                v_status_c, v_hire, v_dism, 0.1)          -- BR-6.5
        ON CONFLICT DO NOTHING
        RETURNING courier_id INTO v_id;
        IF v_id IS NOT NULL THEN
            v_courier_ids  := v_courier_ids  || v_id;
            v_courier_hire := v_courier_hire || v_hire;
            v_courier_dism := v_courier_dism || v_dism;
        END IF;
    END LOOP;

    -- 3. address: value*5 строк, первые value для ресторанов, остальные для клиентов (BR-11.7)
    WHILE coalesce(array_length(v_rest_addr_ids, 1), 0) + coalesce(array_length(v_cli_addr_ids, 1), 0) < v_n * 5 LOOP
        INSERT INTO dunaev_food.address (address_id, street, house_number, apartment_office)
        VALUES (exts.uuid_generate_v4(),
                v_street_types[1 + floor(random() * array_length(v_street_types, 1))::int] || ' ' ||
                v_streets[1 + floor(random() * array_length(v_streets, 1))::int],
                (1 + floor(random() * 150))::int::text ||
                    CASE WHEN random() < 0.15 THEN 'к' || (1 + floor(random() * 4))::int::text ELSE '' END,
                CASE
                    WHEN coalesce(array_length(v_rest_addr_ids, 1), 0) < v_n THEN
                        CASE WHEN random() < 0.5 THEN 'оф. ' || (1 + floor(random() * 50))::int::text END
                    ELSE
                        CASE WHEN random() < 0.75 THEN (1 + floor(random() * 300))::int::text END
                END)
        ON CONFLICT DO NOTHING
        RETURNING address_id INTO v_id;
        IF v_id IS NOT NULL THEN
            IF coalesce(array_length(v_rest_addr_ids, 1), 0) < v_n THEN
                v_rest_addr_ids := v_rest_addr_ids || v_id;
            ELSE
                v_cli_addr_ids := v_cli_addr_ids || v_id;
            END IF;
        END IF;
    END LOOP;

    -- 4. restaurant: value строк, у каждого свой адрес (BR-3.3)
    FOR i IN 1 .. v_n LOOP
        INSERT INTO dunaev_food.restaurant (restaurant_id, restaurant_name, address_id, description,
                                            work_start, work_end, company_details, rating, status)
        SELECT exts.uuid_generate_v4(),
               v_rest_kinds[1 + floor(random() * array_length(v_rest_kinds, 1))::int] || ' «' ||
               v_rest_names[1 + floor(random() * array_length(v_rest_names, 1))::int] || '»',
               v_rest_addr_ids[i],
               'Кухня: ' || lower(v_categories[1 + floor(random() * array_length(v_categories, 1))::int]) ||
               '. Доставка по всему городу.',
               t.ws,
               t.ws + (8 + floor(random() * 5))::int * interval '1 hour',   -- work_end > work_start (BR-4.4), max 23:00
               'ИНН ' || lpad(floor(random() * 1e10)::bigint::text, 10, '0') ||
               ', ОГРН ' || lpad(floor(random() * 1e13)::bigint::text, 13, '0') ||
               ', р/с 40702810' || lpad(floor(random() * 1e12)::bigint::text, 12, '0'),
               NULL,                                         -- рейтинг считается ниже по отзывам
               v_rest_statuses[1 + floor(random() * array_length(v_rest_statuses, 1))::int]
        FROM (SELECT time '06:00' + floor(random() * 6)::int * interval '1 hour' AS ws) t
        RETURNING restaurant_id INTO v_id;
        v_restaurant_ids := v_restaurant_ids || v_id;
    END LOOP;

    -- 5. client: value строк; логин и телефон уникальны (BR-2.2), пароль md5 (BR-2.3)
    WHILE coalesce(array_length(v_client_ids, 1), 0) < v_n LOOP
        INSERT INTO dunaev_food.client (client_id, login, password, phone_number)
        VALUES (exts.uuid_generate_v4(),
                'user_' || substr(md5(random()::text), 1, 6 + floor(random() * 10)::int),  -- 11..20 символов
                md5(random()::text),
                '+79' || lpad(floor(random() * 1000000000)::bigint::text, 9, '0'))
        ON CONFLICT DO NOTHING
        RETURNING client_id INTO v_id;
        IF v_id IS NOT NULL THEN
            v_client_ids := v_client_ids || v_id;
        END IF;
    END LOOP;

    -- 6. client_address: у клиента i адреса i, i+value, i+2*value, i+3*value.
    --    Часть адресов дополнительно отдается второму клиенту (BR-2.4).
    FOR j IN 1 .. v_n * 4 LOOP
        INSERT INTO dunaev_food.client_address (client_id, address_id)
        VALUES (v_client_ids[((j - 1) % v_n) + 1], v_cli_addr_ids[j]);
    END LOOP;

    FOR j IN 1 .. v_n LOOP
        INSERT INTO dunaev_food.client_address (client_id, address_id)
        VALUES (v_client_ids[1 + floor(random() * v_n)::int],
                v_cli_addr_ids[1 + floor(random() * v_n * 4)::int])
        ON CONFLICT DO NOTHING;
    END LOOP;

    -- 7. product: value*5 строк, по 5 блюд на ресторан
    FOR i IN 1 .. v_n * 5 LOOP
        v_amount := (2 + floor(random() * 29))::int * 50;          -- цена 100..1500 ₽ (BR-5.3)
        INSERT INTO dunaev_food.product (product_id, product_name, product_category_id, price,
                                         restaurant_id, photo_url, rating, status, description)
        VALUES (exts.uuid_generate_v4(),
                v_dish_adj[1 + floor(random() * array_length(v_dish_adj, 1))::int] || ' ' ||
                v_dish_noun[1 + floor(random() * array_length(v_dish_noun, 1))::int],
                v_category_ids[1 + floor(random() * v_n)::int],
                v_amount,
                v_restaurant_ids[((i - 1) % v_n) + 1],
                CASE WHEN random() < 0.8
                     THEN 'https://cdn.foodexpress.ru/img/' || md5(random()::text) || '.jpg' END,  -- BR-5.6
                NULL,
                v_prod_statuses[1 + floor(random() * array_length(v_prod_statuses, 1))::int],
                'Состав и вес уточняйте у ресторана. Порция ' || (200 + floor(random() * 400))::int || ' г.')
        RETURNING product_id INTO v_id;
        v_product_ids   := v_product_ids   || v_id;
        v_product_price := v_product_price || v_amount;
    END LOOP;

    -- 8. "order" + order_structure + payment: по value*5 строк заказов и оплат
    FOR i IN 1 .. v_n * 5 LOOP
        v_courier_idx := 1 + floor(random() * v_n)::int;
        v_client_idx  := 1 + floor(random() * v_n)::int;
        v_rest_idx    := 1 + floor(random() * v_n)::int;

        -- время заказа: пока курьер работает и в окне 6 месяцев
        v_lo := greatest(v_window_start, v_courier_hire[v_courier_idx]::timestamp);
        v_hi := v_now - interval '2 hours';
        IF v_courier_dism[v_courier_idx] IS NOT NULL THEN
            v_hi := least(v_hi, v_courier_dism[v_courier_idx]::timestamp + interval '20 hours');
        END IF;
        v_ts := v_lo + random() * (v_hi - v_lo);

        -- старые заказы доставлены или отменены, у свежих любой статус
        IF v_courier_dism[v_courier_idx] IS NOT NULL OR v_ts < v_now - interval '1 day' THEN
            v_status := CASE WHEN random() < 0.85 THEN 'доставлен' ELSE 'отменён' END;
        ELSE
            v_status := v_order_statuses[1 + floor(random() * array_length(v_order_statuses, 1))::int];
        END IF;

        -- состав: 1..3 разных блюда ресторана (BR-7.3, BR-7.16)
        v_items_cnt := 1 + floor(random() * 3)::int;
        v_offset    := floor(random() * 5)::int;
        v_item_idx  := '{}';
        v_item_qty  := '{}';
        v_amount    := 0;
        FOR k IN 0 .. v_items_cnt - 1 LOOP
            v_item_idx := v_item_idx || (v_rest_idx + ((v_offset + k) % 5) * v_n);
            v_item_qty := v_item_qty || CASE WHEN random() < 0.1
                                             THEN 0.5 + floor(random() * 3)::int    -- дробное (BR-7.15)
                                             ELSE 1 + floor(random() * 3)::int END;
            v_amount := v_amount + v_product_price[v_item_idx[k + 1]] * v_item_qty[k + 1];
        END LOOP;
        -- минимальная сумма: total >= 1000 (BR-1.8, BR-7.11), поэтому order_amount >= 910
        IF v_amount < 910 THEN
            v_item_qty[v_items_cnt] := v_item_qty[v_items_cnt]
                + ceil((910 - v_amount) / v_product_price[v_item_idx[v_items_cnt]]);
            v_amount := 0;
            FOR k IN 1 .. v_items_cnt LOOP
                v_amount := v_amount + v_product_price[v_item_idx[k]] * v_item_qty[k];
            END LOOP;
        END IF;
        v_amount := round(v_amount, 2);
        v_total  := v_amount + round(v_amount * 0.10, 2);

        -- оплата: одна попытка на заказ, статус согласован со статусом заказа
        v_payment_stat := CASE
            WHEN v_status IN ('доставлен', 'в_доставке', 'готовится') THEN 'успех'
            WHEN v_status = 'создан' THEN 'в_обработке'
            ELSE CASE WHEN random() < 0.5 THEN 'успех' ELSE 'ошибка' END
        END;
        v_pay_status := CASE v_payment_stat
            WHEN 'успех'       THEN 'оплачен'
            WHEN 'в_обработке' THEN 'ожидает'
            ELSE 'ошибка'
        END;                                                        -- BR-8.7

        INSERT INTO dunaev_food."order" (order_id, courier_id, client_id, address_id, restaurant_id,
                                         order_timestamp, delivery_timestamp, order_amount,
                                         status, pay_status, description)
        VALUES (exts.uuid_generate_v4(),
                v_courier_ids[v_courier_idx],
                v_client_ids[v_client_idx],
                v_cli_addr_ids[v_client_idx + v_n * floor(random() * 4)::int],   -- адрес этого клиента (BR-7.4)
                v_restaurant_ids[v_rest_idx],
                v_ts,
                CASE WHEN v_status = 'доставлен'
                     THEN v_ts + (20 + floor(random() * 100))::int * interval '1 minute' END,  -- BR-7.12, BR-7.13
                v_amount,
                v_status,
                v_pay_status,
                v_comments[1 + floor(random() * array_length(v_comments, 1))::int])
        RETURNING order_id INTO v_id;
        v_order_ids := v_order_ids || v_id;

        FOR k IN 1 .. v_items_cnt LOOP
            INSERT INTO dunaev_food.order_structure (order_id, product_id, quantity)
            VALUES (v_id, v_product_ids[v_item_idx[k]], v_item_qty[k]);
        END LOOP;

        INSERT INTO dunaev_food.payment (payment_id, order_id, payment_type, amount,
                                         transaction_id, transaction_timestamp, status)
        VALUES (exts.uuid_generate_v4(),
                v_id,
                v_pay_types[1 + floor(random() * array_length(v_pay_types, 1))::int],
                v_total,                                                   -- BR-8.4
                'TX-' || upper(replace(exts.uuid_generate_v4()::text, '-', '')),  -- BR-8.3
                v_ts + random() * interval '10 minutes',
                v_payment_stat);
    END LOOP;

    -- 9. review: value*5 строк, только на то, что есть в заказе (BR-9.2, BR-9.5)
    INSERT INTO dunaev_food.review (review_id, client_id, review_timestamp, entity_id, entity_type,
                                    order_id, description, photo_url, rating)
    SELECT exts.uuid_generate_v4(),
           c.client_id,
           c.base_ts + random() * (v_now - c.base_ts),
           c.entity_id,
           c.entity_type,
           c.order_id,
           v_review_texts[1 + floor(random() * array_length(v_review_texts, 1))::int],
           CASE WHEN random() < 0.3
                THEN 'https://cdn.foodexpress.ru/reviews/' || md5(random()::text) || '.jpg' END,  -- BR-9.3
           1 + floor(random() * 5)::int                                                          -- BR-9.4
    FROM (
        SELECT o.order_id, o.client_id, o.status,
               coalesce(o.delivery_timestamp, o.order_timestamp) AS base_ts,
               'заказ'::dunaev_food.review_entity_type AS entity_type, o.order_id AS entity_id
        FROM dunaev_food."order" o WHERE o.order_id = ANY (v_order_ids)
        UNION ALL
        SELECT o.order_id, o.client_id, o.status,
               coalesce(o.delivery_timestamp, o.order_timestamp),
               'ресторан'::dunaev_food.review_entity_type, o.restaurant_id
        FROM dunaev_food."order" o WHERE o.order_id = ANY (v_order_ids)
        UNION ALL
        SELECT o.order_id, o.client_id, o.status,
               coalesce(o.delivery_timestamp, o.order_timestamp),
               'блюдо'::dunaev_food.review_entity_type, os.product_id
        FROM dunaev_food."order" o
        JOIN dunaev_food.order_structure os ON os.order_id = o.order_id
        WHERE o.order_id = ANY (v_order_ids)
    ) c
    ORDER BY (c.status <> 'доставлен'), random()
    LIMIT v_n * 5;

    -- рейтинги по отзывам, без отзывов NULL (BR-9.6, BR-9.7)
    UPDATE dunaev_food.product p
    SET rating = s.avg_rating
    FROM (SELECT r.entity_id, round(avg(r.rating), 2) AS avg_rating
          FROM dunaev_food.review r
          WHERE r.entity_type = 'блюдо' AND r.entity_id = ANY (v_product_ids)
          GROUP BY r.entity_id) s
    WHERE p.product_id = s.entity_id;

    UPDATE dunaev_food.restaurant rs
    SET rating = s.avg_rating
    FROM (SELECT r.entity_id, round(avg(r.rating), 2) AS avg_rating
          FROM dunaev_food.review r
          WHERE r.entity_type = 'ресторан' AND r.entity_id = ANY (v_restaurant_ids)
          GROUP BY r.entity_id) s
    WHERE rs.restaurant_id = s.entity_id;

    -- 10. courier_pay за 6 месяцев (BR-10.2)
    --     amount = коэффициент месяца * сумма комиссий доставленных заказов.
    --     Коэффициент на следующий месяц считается по числу доставок.
    --     У уволенного курьера коэффициент больше не меняется (BR-10.6).
    FOR k IN 1 .. v_n LOOP
        v_coef := 0.1;
        FOR j IN 0 .. 5 LOOP
            v_month_start := v_window_start + j * interval '1 month';

            SELECT count(*), coalesce(sum(o.commission), 0)
            INTO v_cnt, v_sum
            FROM dunaev_food."order" o
            WHERE o.courier_id = v_courier_ids[k]
              AND o.status = 'доставлен'                                   -- BR-10.5
              AND o.order_timestamp >= v_month_start
              AND o.order_timestamp <  v_month_start + interval '1 month';

            INSERT INTO dunaev_food.courier_pay (year, month, courier_id, amount, coefficient_used)
            VALUES (extract(year FROM v_month_start)::int,
                    extract(month FROM v_month_start)::int,
                    v_courier_ids[k],
                    round(v_coef * v_sum, 2),
                    v_coef);

            IF v_courier_dism[k] IS NULL
               OR v_courier_dism[k] >= (v_month_start + interval '1 month')::date THEN
                v_coef := CASE
                    WHEN v_cnt <= 150 THEN 0.1
                    WHEN v_cnt <= 250 THEN 0.2
                    WHEN v_cnt <= 500 THEN 0.3
                    ELSE 0.5                                               -- не больше 0.5
                END;
            END IF;
        END LOOP;

        UPDATE dunaev_food.courier SET coefficient = v_coef WHERE courier_id = v_courier_ids[k];
    END LOOP;

    PERFORM set_config('dunaev_food.bulk_load', 'off', true);
END;
$$;

-- erase_test_data удаляет все данные (FOOD-103)
-- Сначала дочерние таблицы, потом родительские.
CREATE OR REPLACE PROCEDURE dunaev_food.erase_test_data()
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM set_config('dunaev_food.bulk_load', 'on', true);

    DELETE FROM dunaev_food.review;
    DELETE FROM dunaev_food.payment;
    DELETE FROM dunaev_food.order_structure;
    DELETE FROM dunaev_food."order";
    DELETE FROM dunaev_food.courier_pay;
    DELETE FROM dunaev_food.client_address;
    DELETE FROM dunaev_food.product;
    DELETE FROM dunaev_food.product_category;
    DELETE FROM dunaev_food.restaurant;
    DELETE FROM dunaev_food.client;
    DELETE FROM dunaev_food.courier;
    DELETE FROM dunaev_food.address;

    PERFORM set_config('dunaev_food.bulk_load', 'off', true);
END;
$$;
