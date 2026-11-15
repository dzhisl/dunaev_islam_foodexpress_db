-- Зарплата курьеров за текущий месяц (FOOD-107, BR-10.2)
-- Если запись за месяц уже есть, берется ее коэффициент,
-- поэтому повторный вызов дает тот же результат.

SET search_path TO dunaev_food, exts;

CREATE OR REPLACE PROCEDURE dunaev_food.courier_salary()
LANGUAGE plpgsql
AS $$
DECLARE
    v_month_start timestamp := date_trunc('month', localtimestamp);
    v_month_end   timestamp := date_trunc('month', localtimestamp) + interval '1 month';
    v_year        integer   := extract(year  FROM localtimestamp)::int;
    v_month       integer   := extract(month FROM localtimestamp)::int;
BEGIN
    WITH stats AS (
        SELECT c.courier_id,
               c.status,
               count(o.order_id)                          AS delivered_cnt,
               coalesce(sum(o.commission), 0)             AS commission_sum,
               coalesce(cp.coefficient_used, c.coefficient) AS coef_current
        FROM dunaev_food.courier c
        LEFT JOIN dunaev_food."order" o
               ON o.courier_id = c.courier_id
              AND o.status = 'доставлен'
              AND o.order_timestamp >= v_month_start
              AND o.order_timestamp <  v_month_end
        LEFT JOIN dunaev_food.courier_pay cp
               ON cp.courier_id = c.courier_id
              AND cp.year = v_year
              AND cp.month = v_month
        WHERE c.status <> 'уволен'
           OR c.dismissal_date >= v_month_start::date
           OR cp.courier_id IS NOT NULL
        GROUP BY c.courier_id, c.status, cp.coefficient_used, c.coefficient
    ),
    upsert AS (
        INSERT INTO dunaev_food.courier_pay AS t (year, month, courier_id, amount, coefficient_used)
        SELECT v_year, v_month, s.courier_id,
               round(s.coef_current * s.commission_sum, 2),
               s.coef_current
        FROM stats s
        ON CONFLICT (year, month, courier_id) DO UPDATE
            SET amount           = EXCLUDED.amount,
                coefficient_used = EXCLUDED.coefficient_used
        RETURNING t.courier_id
    )
    UPDATE dunaev_food.courier c
    SET coefficient = CASE
            WHEN s.delivered_cnt <= 150 THEN 0.1
            WHEN s.delivered_cnt <= 250 THEN 0.2
            WHEN s.delivered_cnt <= 500 THEN 0.3
            ELSE 0.5
        END
    FROM stats s
    WHERE c.courier_id = s.courier_id
      AND s.status <> 'уволен';
END;
$$;
