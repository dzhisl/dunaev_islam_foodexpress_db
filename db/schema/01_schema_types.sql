-- Схема dunaev_food и enum типы (FOOD-101)
-- Схема exts с uuid-ossp уже есть в базе

DROP SCHEMA IF EXISTS dunaev_food CASCADE;
CREATE SCHEMA dunaev_food;

SET search_path TO dunaev_food, exts;

-- BR-4.3
CREATE TYPE dunaev_food.restaurant_status AS ENUM ('активен', 'неактивен');

-- BR-5.5
CREATE TYPE dunaev_food.product_status AS ENUM ('доступно', 'нет_в_наличии', 'архив');

-- BR-6.2
CREATE TYPE dunaev_food.courier_status AS ENUM ('свободен', 'занят', 'на_доставке', 'уволен');

-- BR-7.7
CREATE TYPE dunaev_food.order_status AS ENUM ('создан', 'готовится', 'в_доставке', 'доставлен', 'отменён');

-- BR-7.9
CREATE TYPE dunaev_food.order_pay_status AS ENUM ('ожидает', 'оплачен', 'ошибка');

-- BR-8.2 (статус попытки оплаты)
CREATE TYPE dunaev_food.payment_status AS ENUM ('успех', 'ошибка', 'в_обработке');

-- BR-8.2 (тип оплаты)
CREATE TYPE dunaev_food.payment_type AS ENUM ('карта', 'наличные', 'безнал');

-- BR-9.1
CREATE TYPE dunaev_food.review_entity_type AS ENUM ('блюдо', 'ресторан', 'заказ');
