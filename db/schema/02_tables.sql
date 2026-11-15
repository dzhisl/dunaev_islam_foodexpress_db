-- Таблицы и ограничения (FOOD-101)

SET search_path TO dunaev_food, exts;

-- address (BR-3.1, BR-3.2)
CREATE TABLE dunaev_food.address (
    address_id       uuid         NOT NULL DEFAULT exts.uuid_generate_v4(),
    street           varchar(100) NOT NULL,
    house_number     varchar(10)  NOT NULL,
    apartment_office varchar(10),                     -- NULL: BR-3.2
    CONSTRAINT address_pk PRIMARY KEY (address_id),
    CONSTRAINT address_street_not_blank_chk    CHECK (btrim(street) <> ''),
    CONSTRAINT address_house_not_blank_chk     CHECK (btrim(house_number) <> ''),
    CONSTRAINT address_apartment_not_blank_chk CHECK (apartment_office IS NULL OR btrim(apartment_office) <> ''),
    CONSTRAINT address_physical_uq UNIQUE NULLS NOT DISTINCT (street, house_number, apartment_office)
);

-- client
CREATE TABLE dunaev_food.client (
    client_id    uuid        NOT NULL DEFAULT exts.uuid_generate_v4(),
    login        varchar(50) NOT NULL,
    password     char(32)    NOT NULL,
    phone_number char(12)    NOT NULL,
    CONSTRAINT client_pk PRIMARY KEY (client_id),
    CONSTRAINT client_login_uq UNIQUE (login),
    CONSTRAINT client_phone_uq UNIQUE (phone_number),
    CONSTRAINT client_login_not_blank_chk CHECK (btrim(login) <> ''),
    CONSTRAINT client_password_md5_chk    CHECK (password ~ '^[0-9a-f]{32}$'),
    CONSTRAINT client_phone_format_chk    CHECK (phone_number ~ '^\+7[0-9]{10}$')
);

-- client_address (BR-2.4, BR-2.5)
CREATE TABLE dunaev_food.client_address (
    client_id  uuid NOT NULL,
    address_id uuid NOT NULL,
    CONSTRAINT client_address_pk PRIMARY KEY (client_id, address_id),
    CONSTRAINT client_address_client_fk FOREIGN KEY (client_id)
        REFERENCES dunaev_food.client (client_id) ON DELETE CASCADE,
    CONSTRAINT client_address_address_fk FOREIGN KEY (address_id)
        REFERENCES dunaev_food.address (address_id) ON DELETE RESTRICT
);
CREATE INDEX client_address_address_idx ON dunaev_food.client_address (address_id);

-- restaurant
CREATE TABLE dunaev_food.restaurant (
    restaurant_id   uuid         NOT NULL DEFAULT exts.uuid_generate_v4(),
    restaurant_name varchar(100) NOT NULL,
    address_id      uuid         NOT NULL,
    description     text         NOT NULL,
    work_start      time         NOT NULL,
    work_end        time         NOT NULL,
    company_details text         NOT NULL,
    rating          numeric(3,2),                     -- NULL: нет отзывов (BR-9.7)
    status          dunaev_food.restaurant_status NOT NULL DEFAULT 'активен',
    CONSTRAINT restaurant_pk PRIMARY KEY (restaurant_id),
    CONSTRAINT restaurant_address_uq UNIQUE (address_id),
    CONSTRAINT restaurant_address_fk FOREIGN KEY (address_id)
        REFERENCES dunaev_food.address (address_id) ON DELETE RESTRICT,
    CONSTRAINT restaurant_name_not_blank_chk CHECK (btrim(restaurant_name) <> ''),
    CONSTRAINT restaurant_work_time_chk      CHECK (work_end > work_start),
    CONSTRAINT restaurant_rating_chk         CHECK (rating BETWEEN 0 AND 5)
);

-- product_category (BR-5.7)
CREATE TABLE dunaev_food.product_category (
    product_category_id   uuid         NOT NULL DEFAULT exts.uuid_generate_v4(),
    product_category_name varchar(100) NOT NULL,
    CONSTRAINT product_category_pk PRIMARY KEY (product_category_id),
    CONSTRAINT product_category_name_uq UNIQUE (product_category_name),
    CONSTRAINT product_category_name_not_blank_chk CHECK (btrim(product_category_name) <> '')
);

-- product
CREATE TABLE dunaev_food.product (
    product_id          uuid          NOT NULL DEFAULT exts.uuid_generate_v4(),
    product_name        varchar(100)  NOT NULL,
    product_category_id uuid          NOT NULL,
    price               numeric(10,2) NOT NULL,
    restaurant_id       uuid          NOT NULL,
    photo_url           text,                         -- NULL: BR-5.6
    rating              numeric(3,2),                 -- NULL: нет отзывов (BR-9.7)
    status              dunaev_food.product_status NOT NULL DEFAULT 'доступно',
    description         text          NOT NULL,
    CONSTRAINT product_pk PRIMARY KEY (product_id),
    CONSTRAINT product_category_fk FOREIGN KEY (product_category_id)
        REFERENCES dunaev_food.product_category (product_category_id) ON DELETE RESTRICT,
    CONSTRAINT product_restaurant_fk FOREIGN KEY (restaurant_id)
        REFERENCES dunaev_food.restaurant (restaurant_id) ON DELETE RESTRICT,
    CONSTRAINT product_name_not_blank_chk  CHECK (btrim(product_name) <> ''),
    CONSTRAINT product_price_chk           CHECK (price >= 0),
    CONSTRAINT product_rating_chk          CHECK (rating BETWEEN 0 AND 5),
    CONSTRAINT product_photo_not_blank_chk CHECK (photo_url IS NULL OR btrim(photo_url) <> '')
);
CREATE INDEX product_restaurant_idx ON dunaev_food.product (restaurant_id);
CREATE INDEX product_category_idx   ON dunaev_food.product (product_category_id);

-- courier
CREATE TABLE dunaev_food.courier (
    courier_id     uuid         NOT NULL DEFAULT exts.uuid_generate_v4(),
    fio            varchar(150) NOT NULL,
    phone_number   char(12)     NOT NULL,
    status         dunaev_food.courier_status NOT NULL DEFAULT 'свободен',
    hire_date      date         NOT NULL,
    dismissal_date date,                              -- NULL: работает (BR-6.3)
    coefficient    numeric(3,2) NOT NULL DEFAULT 0.1, -- BR-6.5
    CONSTRAINT courier_pk PRIMARY KEY (courier_id),
    CONSTRAINT courier_phone_uq UNIQUE (phone_number),
    CONSTRAINT courier_fio_not_blank_chk     CHECK (btrim(fio) <> ''),
    CONSTRAINT courier_phone_format_chk      CHECK (phone_number ~ '^\+7[0-9]{10}$'),
    CONSTRAINT courier_coefficient_chk       CHECK (coefficient BETWEEN 0.1 AND 0.5),
    CONSTRAINT courier_dismissed_has_date_chk CHECK (status <> 'уволен' OR dismissal_date IS NOT NULL),
    CONSTRAINT courier_dismissal_after_hire_chk CHECK (dismissal_date IS NULL OR dismissal_date >= hire_date)
);

-- courier_pay
CREATE TABLE dunaev_food.courier_pay (
    year             integer       NOT NULL,
    month            integer       NOT NULL,
    courier_id       uuid          NOT NULL,
    amount           numeric(12,2) NOT NULL,
    coefficient_used numeric(3,2)  NOT NULL,
    CONSTRAINT courier_pay_pk PRIMARY KEY (year, month, courier_id),
    CONSTRAINT courier_pay_courier_fk FOREIGN KEY (courier_id)
        REFERENCES dunaev_food.courier (courier_id) ON DELETE RESTRICT,
    CONSTRAINT courier_pay_month_chk       CHECK (month BETWEEN 1 AND 12),
    CONSTRAINT courier_pay_amount_chk      CHECK (amount >= 0),
    CONSTRAINT courier_pay_coefficient_chk CHECK (coefficient_used BETWEEN 0.1 AND 0.5)
);
CREATE INDEX courier_pay_courier_idx ON dunaev_food.courier_pay (courier_id);

-- "order" в кавычках, так как order зарезервированное слово (BR-13.1)
CREATE TABLE dunaev_food."order" (
    order_id           uuid          NOT NULL DEFAULT exts.uuid_generate_v4(),
    courier_id         uuid          NOT NULL,
    client_id          uuid          NOT NULL,
    address_id         uuid          NOT NULL,
    restaurant_id      uuid          NOT NULL,
    order_timestamp    timestamp     NOT NULL DEFAULT localtimestamp,
    delivery_timestamp timestamp,                     -- NULL: не доставлен (BR-7.12)
    order_amount       numeric(12,2) NOT NULL,
    commission         numeric(12,2) GENERATED ALWAYS AS (round(order_amount * 0.10, 2)) STORED,
    total_amount       numeric(12,2) GENERATED ALWAYS AS (order_amount + round(order_amount * 0.10, 2)) STORED,
    status             dunaev_food.order_status     NOT NULL DEFAULT 'создан',
    pay_status         dunaev_food.order_pay_status NOT NULL DEFAULT 'ожидает',
    description        text          NOT NULL,
    CONSTRAINT order_pk PRIMARY KEY (order_id),
    CONSTRAINT order_order_client_uq UNIQUE (order_id, client_id),
    CONSTRAINT order_courier_fk FOREIGN KEY (courier_id)
        REFERENCES dunaev_food.courier (courier_id) ON DELETE RESTRICT,
    CONSTRAINT order_client_fk FOREIGN KEY (client_id)
        REFERENCES dunaev_food.client (client_id) ON DELETE RESTRICT,
    CONSTRAINT order_address_fk FOREIGN KEY (address_id)
        REFERENCES dunaev_food.address (address_id) ON DELETE RESTRICT,
    CONSTRAINT order_restaurant_fk FOREIGN KEY (restaurant_id)
        REFERENCES dunaev_food.restaurant (restaurant_id) ON DELETE RESTRICT,
    CONSTRAINT order_client_address_fk FOREIGN KEY (client_id, address_id)
        REFERENCES dunaev_food.client_address (client_id, address_id) ON DELETE RESTRICT,
    CONSTRAINT order_amount_chk          CHECK (order_amount >= 0),
    CONSTRAINT order_total_min_chk       CHECK (total_amount >= 1000),
    CONSTRAINT order_delivery_after_create_chk
        CHECK (delivery_timestamp IS NULL OR delivery_timestamp >= order_timestamp),
    CONSTRAINT order_delivered_has_time_chk
        CHECK (status <> 'доставлен' OR delivery_timestamp IS NOT NULL)
);
CREATE INDEX order_courier_idx    ON dunaev_food."order" (courier_id);
CREATE INDEX order_client_idx     ON dunaev_food."order" (client_id, address_id);
CREATE INDEX order_address_idx    ON dunaev_food."order" (address_id);
CREATE INDEX order_restaurant_idx ON dunaev_food."order" (restaurant_id);

-- order_structure
CREATE TABLE dunaev_food.order_structure (
    order_id   uuid         NOT NULL,
    product_id uuid         NOT NULL,
    quantity   numeric(8,3) NOT NULL,
    CONSTRAINT order_structure_pk PRIMARY KEY (order_id, product_id),
    CONSTRAINT order_structure_order_fk FOREIGN KEY (order_id)
        REFERENCES dunaev_food."order" (order_id) ON DELETE RESTRICT,
    CONSTRAINT order_structure_product_fk FOREIGN KEY (product_id)
        REFERENCES dunaev_food.product (product_id) ON DELETE RESTRICT,
    CONSTRAINT order_structure_quantity_chk CHECK (quantity > 0)
);
CREATE INDEX order_structure_product_idx ON dunaev_food.order_structure (product_id);

-- payment
CREATE TABLE dunaev_food.payment (
    payment_id            uuid          NOT NULL DEFAULT exts.uuid_generate_v4(),
    order_id              uuid          NOT NULL,
    payment_type          dunaev_food.payment_type   NOT NULL,
    amount                numeric(12,2) NOT NULL,
    transaction_id        varchar(64)   NOT NULL,
    transaction_timestamp timestamp     NOT NULL DEFAULT localtimestamp,
    status                dunaev_food.payment_status NOT NULL DEFAULT 'в_обработке',
    CONSTRAINT payment_pk PRIMARY KEY (payment_id),
    CONSTRAINT payment_order_fk FOREIGN KEY (order_id)
        REFERENCES dunaev_food."order" (order_id) ON DELETE RESTRICT,
    CONSTRAINT payment_transaction_uq UNIQUE (transaction_id),
    CONSTRAINT payment_transaction_not_blank_chk CHECK (btrim(transaction_id) <> ''),
    CONSTRAINT payment_amount_chk CHECK (amount >= 1000)
);
CREATE INDEX payment_order_idx ON dunaev_food.payment (order_id);
-- Не больше одной успешной оплаты на заказ (BR-8.1)
CREATE UNIQUE INDEX payment_one_success_uq ON dunaev_food.payment (order_id) WHERE status = 'успех';

-- review
CREATE TABLE dunaev_food.review (
    review_id        uuid      NOT NULL DEFAULT exts.uuid_generate_v4(),
    client_id        uuid      NOT NULL,
    review_timestamp timestamp NOT NULL DEFAULT localtimestamp,
    entity_id        uuid      NOT NULL,
    entity_type      dunaev_food.review_entity_type NOT NULL,
    order_id         uuid      NOT NULL,
    description      text      NOT NULL,
    photo_url        text,                            -- NULL: BR-9.3
    rating           smallint  NOT NULL,
    CONSTRAINT review_pk PRIMARY KEY (review_id),
    CONSTRAINT review_client_fk FOREIGN KEY (client_id)
        REFERENCES dunaev_food.client (client_id) ON DELETE RESTRICT,
    CONSTRAINT review_order_fk FOREIGN KEY (order_id)
        REFERENCES dunaev_food."order" (order_id) ON DELETE RESTRICT,
    CONSTRAINT review_order_client_fk FOREIGN KEY (order_id, client_id)
        REFERENCES dunaev_food."order" (order_id, client_id) ON DELETE RESTRICT,
    CONSTRAINT review_one_per_entity_uq UNIQUE (order_id, entity_type, entity_id),
    CONSTRAINT review_rating_chk CHECK (rating BETWEEN 1 AND 5),
    CONSTRAINT review_photo_not_blank_chk CHECK (photo_url IS NULL OR btrim(photo_url) <> '')
);
CREATE INDEX review_entity_idx ON dunaev_food.review (entity_type, entity_id);
CREATE INDEX review_client_idx ON dunaev_food.review (client_id);
