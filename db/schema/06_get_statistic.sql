-- Статистика по ресторанам (FOOD-106)
-- Таблица order читается один раз, без оконных функций и подзапросов.
-- Учитываются только доставленные заказы.

SET search_path TO dunaev_food, exts;

CREATE OR REPLACE FUNCTION dunaev_food.get_statistic()
RETURNS TABLE (
    restaurant_name   varchar,
    best_product_name varchar,
    total_amount      numeric,
    avg_amount        numeric,
    best_user         varchar
)
LANGUAGE sql
VOLATILE                       -- random() для случайного выбора при равенстве
AS $$
    WITH delivered AS MATERIALIZED (
        SELECT o.order_id, o.restaurant_id, o.client_id, o.total_amount
        FROM dunaev_food."order" o
        WHERE o.status = 'доставлен'
    ),
    restaurant_sums AS (
        SELECT d.restaurant_id,
               sum(d.total_amount)           AS total_amount,
               round(avg(d.total_amount), 2) AS avg_amount
        FROM delivered d
        GROUP BY d.restaurant_id
    ),
    best_product AS (
        SELECT DISTINCT ON (d.restaurant_id)
               d.restaurant_id, os.product_id
        FROM delivered d
        JOIN dunaev_food.order_structure os ON os.order_id = d.order_id
        GROUP BY d.restaurant_id, os.product_id
        ORDER BY d.restaurant_id, sum(os.quantity) DESC, random()
    ),
    best_client AS (
        SELECT DISTINCT ON (d.restaurant_id)
               d.restaurant_id, d.client_id
        FROM delivered d
        GROUP BY d.restaurant_id, d.client_id
        ORDER BY d.restaurant_id, count(*) DESC, random()
    )
    SELECT r.restaurant_name::varchar,
           p.product_name::varchar,
           coalesce(rs.total_amount, 0)::numeric,
           coalesce(rs.avg_amount, 0)::numeric,
           c.login::varchar
    FROM dunaev_food.restaurant r
    LEFT JOIN restaurant_sums rs   ON rs.restaurant_id = r.restaurant_id
    LEFT JOIN best_product bp      ON bp.restaurant_id = r.restaurant_id
    LEFT JOIN dunaev_food.product p ON p.product_id = bp.product_id
    LEFT JOIN best_client bc       ON bc.restaurant_id = r.restaurant_id
    LEFT JOIN dunaev_food.client c ON c.client_id = bc.client_id
    ORDER BY r.restaurant_name;
$$;
